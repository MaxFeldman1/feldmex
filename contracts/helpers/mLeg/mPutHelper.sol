pragma solidity >=0.8.0;

import "../../multiLeg/multiPut/MultiPutExchange.sol";

contract mPutHelper {
	address public addr;

	address feeOracleAddress;
	address delegateAddress;
	constructor(address _feeOracleAddress, address _delegateAddress) {
		feeOracleAddress = _feeOracleAddress;
		delegateAddress = _delegateAddress;
	}

	function deploy(address _strikeAssetAddress, address _optionsAddress) public {
		addr = address(new MultiPutExchange(_strikeAssetAddress, _optionsAddress, feeOracleAddress, delegateAddress));
	}
}
