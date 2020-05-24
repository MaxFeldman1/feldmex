pragma solidity ^0.5.12;
import "./options.sol";

//allows us to deploy the options smart contract without going over gas limit
contract oHelper {
	address owner;

	address public optionsAddress;


	constructor () public {
		owner = msg.sender;
	}

	function setOwner(address _addr) public {
		require(msg.sender == owner);
		owner = _addr;
	}

	function deploy(address _oracleAddress, address _underlyingAssetAddress, address _strikeAssetAddress) public {
		require(owner == msg.sender);
		optionsAddress = address(new options(_oracleAddress, _underlyingAssetAddress, _strikeAssetAddress));
		options(optionsAddress).setOwner(owner);
	}

}