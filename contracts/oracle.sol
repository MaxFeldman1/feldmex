pragma solidity ^0.5.12;

contract oracle{
    uint btceth;
    
    function set(uint _btceth) public {
        btceth = _btceth;
    }
    
    function get() public view returns(uint) {
        return btceth;
    }
    
    function height() public view returns(uint){
        return block.number;
    }
}