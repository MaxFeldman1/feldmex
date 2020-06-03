pragma solidity ^0.5.12;
import "./exchange.sol";

/*
	This contract allows us to deploy the options smart contract without going over gas limit

    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract eHelper {
	mapping(address => address) public exchangeAddress;

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		exchangeAddress[msg.sender] = address(new exchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress));
	}

}