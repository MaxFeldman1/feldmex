pragma solidity >=0.6.0;
import "./interfaces/ERC20.sol";
import "./interfaces/ITimeSeriesOracle.sol";

contract oracle is ITimeSeriesOracle {
    uint public override latestSpot;

    //lists all block heights at which spot is collected
    uint[] public override heights;
    function heightsLength() external view override returns (uint length) {length = heights.length;}
    //height => timestamp
    mapping(uint => uint) public override timestamps;
    //height => price
    mapping(uint => uint) public override heightToSpot;



    uint mostRecent;

    /*
        spots are stored at an inflated value of spot * underlyingAssetSubUnits
    */
    uint public override underlyingAssetSubUnits;

    uint public override strikeAssetSubUnits;

    address public override underlyingAssetAddress;

    address public override strikeAssetAddress;

    constructor(address _underlyingAssetAddress, address _strikeAssetAddress) public {
        underlyingAssetAddress = _underlyingAssetAddress;
        strikeAssetAddress = _strikeAssetAddress;
        underlyingAssetSubUnits = 10 ** uint(ERC20(_underlyingAssetAddress).decimals());
        strikeAssetSubUnits = 10 ** uint(ERC20(_strikeAssetAddress).decimals());
        heights.push(block.number);
        heights.push(block.number);
        heights.push(block.number);
    }

    function set(uint _spot) public override {
        latestSpot = _spot;
        if (heights[heights.length-1] != block.number) heights.push(block.number);
        timestamps[block.number] = block.timestamp;
        heightToSpot[block.number] = _spot;
    }
    
    function tsToIndex(uint _time) public view override returns (uint) {
        uint size = heights.length;
        if (_time >= timestamps[heights[size-1]]) return size-1;
        if (_time < timestamps[heights[0]] || size < 3) return 0;
        uint step = size>>2;
        for (uint i = size>>1; ;){
            uint currentTs = timestamps[heights[i]];
            uint prevTs = i < 1 ? 0 : timestamps[heights[i-1]];
            uint nextTs = i+1 < size ? timestamps[heights[i+1]]: timestamps[heights[size-1]];
            /*
                p => prevTs
                c => currentTs
                n => nextTs
                Target => _time
                    On each iteration find where Target is in relation to others
                p, c, n, Target => increace i
                p, c, Target, n => c
                p, Target, c, n => p
                Target, p, c, n => decreace i
            */
            if (_time >= nextTs)
                i = (i+step) < size ? i+step : size-1;                
            else if (_time >= currentTs)
                return i;
            else if (_time >= prevTs)
                return i-1;
            else
                i = i > step ? i-step : 0;
            step = (step>>1) > 0? step>>1: 1;
        }

    }

    function heightToIndex(uint _height) public view override returns (uint) {
        uint size = heights.length;
        if (_height >= heights[size-1]) return size-1;
        if (_height <= heights[0] || size == 3) return 0;
        uint step = size>>2;
        for (uint i = size>>1; ;){
            uint currentHeight = heights[i];
            uint prevHeight = i < 1 ? 0 : heights[i-1];
            uint nextHeight = i+1 < size ? heights[i+1]: heights[size-1];
            /*
                p => prevTs
                c => currentTs
                n => nextTs
                Target => _time
                    On each iteration find where Target is in relation to others
                p, c, n, Target => increace i
                p, c, Target, n => c
                p, Target, c, n => p
                Target, p, c, n => decreace i
            */
            if (_height > nextHeight)
                i = (i+step) < size ? i+step : size-1;
            else if (_height == nextHeight)
                return i+1 < size ? i+1 : size-1;
            else if (_height >= currentHeight)
                return i;
            else if (_height >= prevHeight)
                return i-1;
            else
                i = i > step ? i-step : 0;
            step = (step>>1) > 0? step>>1: 1;
        }

    }

    function medianPreviousIndecies(uint _index) public view override returns (uint median) {
        require(_index > 1, "index must be 2 or greater");
        require(_index < heights.length, "index must be in array");
        uint first = heightToSpot[heights[_index-2]];
        uint second = heightToSpot[heights[_index-1]];
        uint third = heightToSpot[heights[_index]];
        (first,second) = first > second ? (first, second) : (second,first);
        (second,third) = second > third ? (second, third) : (third,second);
        (first,second) = first > second ? (first, second) : (second,first);
        median = second;
    }

    function fetchSpotAtTime(uint _time, address _underlyingAssetAddress) external view override returns (uint spot) {
        spot = medianPreviousIndecies(tsToIndex(_time));
        /*
            if _underlyingAssetAddress != underlyingAssetAddress we know that the requesting options handler contract
            wants the inverse of the spot that we found on the line above.
            because spot already == trueSpot * strikeAssetSubUnits
            and we want spot to == underlyingAssetSubUnits / trueSpot
            we can achieve this by setting spot = underlyingAssetSubUnits * strikeAssetSubUnits / spot;
                underlyingAssetSubUnits * strikeAssetSubUnits / spot ==
                underlyingAssetSubUnits * strikeAssetSubUnits / (trueSpot * strikeAssetSubUnits) == 
                underlyingAssetSubUnits * trueSpot
        */
        if (_underlyingAssetAddress != underlyingAssetAddress) spot = underlyingAssetSubUnits * strikeAssetSubUnits / spot;
    }

}