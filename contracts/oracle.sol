pragma solidity ^0.5.12;

contract oracle{
    uint btceth;

    //lists all block heights at which spot is collected
    uint[] heights;
    //height => timestamp
    mapping(uint => uint) public timestamps;
    //timestamp => price
    mapping(uint => uint) public tsToSpot;


    uint startHeight;

    uint mostRecent;

    /*
        adds extra accuracy to spot price
        any contract interacting with this oracle shold divide out the inflator after calculatioins
        inflator shall be equal to scUnits *the amount of subUnits in one full unit of strikeAsset*
    */
    uint public inflator = 1000000;

    constructor() public {
        startHeight = block.number;
        mostRecent = startHeight;
        heights.push(block.number);
    }

    function set(uint _btceth) public {
        if (heights[heights.length-1] != block.number) heights.push(block.number);
        btceth = _btceth;
        timestamps[block.number] = block.timestamp;
        tsToSpot[block.timestamp] = btceth;
        mostRecent = startHeight;
    }
    
    function get() public view returns(uint) {
        return btceth;
    }
    
    function getUint(uint _height) public view returns(uint){
        while (_height > startHeight){
            if (tsToSpot[timestamps[_height]] > 0)
                return tsToSpot[timestamps[_height]];
            _height--;
        }
        return 0;
    }

    //returns time, height
    function timestampBehindHeight(uint _height) public view returns(uint, uint){
        while (_height > startHeight){
            if (timestamps[_height] > 0)
                return (timestamps[_height], _height);
            _height--;
        }
        return (0, _height);
    }


    function timestampAheadHeight(uint _height) public view returns(uint, uint){
        if (_height > block.number) return (0, 0);
        while (_height <= block.number){
            if (timestamps[_height] > 0)
                return (timestamps[_height], _height);
            _height++;
        }
        return (0, _height);
    }

    function getAtTime(uint _time) public view returns (uint) {

        if (_time >= timestamps[heights[heights.length-1]]) return btceth;
        if (_time < timestamps[heights[0]] || heights.length < 3) return 0;
        if (tsToSpot[_time] != 0) return tsToSpot[_time];
        uint size = heights.length;
        uint step = size>>2;
        for (uint i = size>>1; ;){
            uint currentTs = timestamps[heights[i]];
            uint prevTs = i < 1 ? 0 : timestamps[heights[i-1]];
            uint nextTs = i+1 < heights.length ? timestamps[heights[i+1]]: timestamps[heights[heights.length-1]];
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
            if (_time > nextTs)
                i = (i+step) < heights.length ? i+step : heights.length-1;                
            else if (_time > currentTs)
                return tsToSpot[currentTs];
            else if (_time > prevTs)
                return tsToSpot[prevTs];
            else
                i = i > step ? i-step : 0;
            step = (step>>1) > 0? step>>1: 1;
        }

    }

    function height() public view returns(uint){
        return block.number;
    }

}