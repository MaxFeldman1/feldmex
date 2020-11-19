pragma solidity >=0.6.0;

import "../../multiLeg/multiCall/MultiCallExchange.sol";

contract mCallHelper {
	address public addr;

	address feeOracleAddress;
	constructor(address _feeOracleAddress) public {
		feeOracleAddress = _feeOracleAddress;
	}

	function deploy(address _underlyingAssetAddress, address _optionsAddress) public {
		addr = address(new MultiCallExchange(_underlyingAssetAddress, _optionsAddress, feeOracleAddress));
	}
}
