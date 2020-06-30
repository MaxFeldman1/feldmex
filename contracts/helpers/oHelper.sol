pragma solidity ^0.5.12;
import "../options.sol";

//allows us to deploy the options smart contract without going over gas limit
contract oHelper {
	mapping(address => address[2]) public optionsAddress;

	function deploy(address _oracleAddress, address _underlyingAssetAddress, address _strikeAssetAddress) public {
		uint8 index = optionsAddress[msg.sender][0] == address(0) ? 0 : 1;
		optionsAddress[msg.sender][index] = address(new options(_oracleAddress, _underlyingAssetAddress, _strikeAssetAddress));
		options(optionsAddress[msg.sender][index]).transferOwnership(msg.sender);
	}

}