pragma solidity >=0.8.0;

abstract contract Ownable {
    address public owner;

    constructor () {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public virtual {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }
}