pragma solidity ^0.5.12;
import "../exchange.sol";

/*
	This contract allows us to deploy the options smart contract without going over gas limit

    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract eHelper {
	mapping(address => address[2]) public exchangeAddress;

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		uint8 index = exchangeAddress[msg.sender][0] == address(0) ? 0 : 1;
		exchangeAddress[msg.sender][index] = address(new exchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress));
	}

}