pragma solidity >=0.8.0;

import "../../multiLeg/multiCall/MultiCallExchange.sol";

contract mCallHelper {
	address public addr;

	address feeOracleAddress;
	address delegateAddress;
	constructor(address _feeOracleAddress, address _delegateAddress) {
		feeOracleAddress = _feeOracleAddress;
		delegateAddress = _delegateAddress;
	}

	function deploy(address _underlyingAssetAddress, address _optionsAddress) public {
		addr = address(new MultiCallExchange(_underlyingAssetAddress, _optionsAddress, feeOracleAddress, delegateAddress));
	}
}
