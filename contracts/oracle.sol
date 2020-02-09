pragma solidity ^0.5.12;

contract oracle{
    uint btceth;

    //height => price
    mapping(uint => uint) public spots;
    //height => timestamp
    mapping(uint => uint) public timestamps;
    //timestamp => price
    mapping(uint => uint) public tsToSpot;

    uint startHeight;

    uint mostRecent;

    constructor() public {
        startHeight = block.number;
        mostRecent = startHeight;
    }

    function set(uint _btceth) public {
        btceth = _btceth;
        spots[block.number] = btceth;
        //if (block.timestamp == mostRecent) {
        //    timestamps[block.timestamp] = btceth;
        //}
        //for (uint i = mostRecent+1; i <= block.height;)
        timestamps[block.number] = block.timestamp;
        tsToSpot[block.timestamp] = btceth;
        mostRecent = startHeight;
    }
    
    function get() public view returns(uint) {
        return btceth;
    }
    
    function getUint(uint height) public view returns(uint){
        while (height > startHeight){
            if (spots[height] > 0)
                return spots[height];
            height--;
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
    //timestamp to spot
    function getAtTime(uint _time) public view returns (uint){
        if (_time >= block.timestamp) return btceth;
        uint height = block.number;
        //*
        for (uint i = height; i > startHeight;){
            //if (timestamps[i] == _time) return spots[i];
            (uint t, uint h) = timestampBehindHeight(i);
            if (t <= _time){
                if (t == 0) return 0;
                return tsToSpot[t];
            } i = h-1;
        }
    }

    function height() public view returns(uint){
        return block.number;
    }

}