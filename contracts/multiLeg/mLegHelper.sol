pragma solidity >=0.5.0;

import "./multiLegExchange.sol";

contract mLegHelper {
	address public addr;

	address delegateAddress;
	constructor (address _delegateAddress) public {
		delegateAddress = _delegateAddress;
	}

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public {
		addr = address(new multiLegExchange(_underlyingAssetAddress, _strikeAssetAddress, _optionsAddress, delegateAddress));
	}
}
