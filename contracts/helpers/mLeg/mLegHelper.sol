pragma solidity >=0.6.0;

import "../../multiLeg/multiLeg/MultiLegExchange.sol";

contract mLegHelper {
	address public addr;

	address delegateAddress;
	address feeOracleAddress;
	constructor (address _delegateAddress, address _feeOracleAddress) public {
		delegateAddress = _delegateAddress;
		feeOracleAddress = _feeOracleAddress;
	}

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		addr = address(new MultiLegExchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress, delegateAddress, feeOracleAddress));
	}
}
