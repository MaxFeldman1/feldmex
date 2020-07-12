pragma solidity >=0.6.0;

import "./multiCallExchange.sol";

contract mCallHelper {
	address public addr;

	function deploy(address _underlyingAssetAddress, address _optionsAddress) public {
		addr = address(new multiCallExchange(_underlyingAssetAddress, _optionsAddress));
	}
}
