pragma solidity ^0.5.12;
import "./options.sol";

//allows us to deploy the options smart contract without going over gas limit
contract oHelper {
	mapping(address => address) public optionsAddress;

	function deploy(address _oracleAddress, address _underlyingAssetAddress, address _strikeAssetAddress) public {
		optionsAddress[msg.sender] = address(new options(_oracleAddress, _underlyingAssetAddress, _strikeAssetAddress));
		options(optionsAddress[msg.sender]).transferOwnership(msg.sender);
	}

}