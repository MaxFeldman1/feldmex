pragma solidity ^0.5.12;

contract oracle{
    uint btceth;
    
    //height => price
    mapping(uint => uint) public spots;

    function set(uint _btceth) public {
        btceth = _btceth;
        spots[block.number] = btceth;
    }
    
    function get() public view returns(uint) {
        return btceth;
    }
    
    function getUint(uint height) public view returns(uint){
        while (height > 1){
            if (spots[height] > 0)
                return spots[height];
            height--;
        }
        return 0;
    }

    function height() public view returns(uint){
        return block.number;
    }

}