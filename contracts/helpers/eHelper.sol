pragma solidity >=0.8.0;
import "../singleOptionExchange/SingleLegExchange.sol";

/*
	This contract allows us to deploy the options smart contract without going over gas limit

    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract eHelper {
	mapping(address => address[2]) public exchangeAddress;

	address feeOracleAddress;
	address delegateAddress;

	constructor (address _feeOracleAddress, address _delegateAddress) {
		feeOracleAddress = _feeOracleAddress;
		delegateAddress = _delegateAddress;
	}

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		uint8 index = exchangeAddress[msg.sender][0] == address(0) ? 0 : 1;
		exchangeAddress[msg.sender][index] = address(new SingleLegExchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress, feeOracleAddress, delegateAddress));
	}

}