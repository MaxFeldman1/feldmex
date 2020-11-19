pragma solidity >=0.6.0;

import "../../multiLeg/multiPut/MultiPutExchange.sol";

contract mPutHelper {
	address public addr;

	address feeOracleAddress;
	constructor(address _feeOracleAddress) public {
		feeOracleAddress = _feeOracleAddress;
	}

	function deploy(address _strikeAssetAddress, address _optionsAddress) public {
		addr = address(new MultiPutExchange(_strikeAssetAddress, _optionsAddress, feeOracleAddress));
	}
}
