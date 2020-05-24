pragma solidity ^0.5.12;
import "./exchange.sol";

//allows us to deploy the options smart contract without going over gas limit
contract eHelper {
	address owner;

	address public exchangeAddress;


	constructor () public {
		owner = msg.sender;
	}

	function setOwner(address _addr) public {
		require(msg.sender == owner);
		owner = _addr;
	}

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		require(owner == msg.sender);
		exchangeAddress = address(new exchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress));
	}

}