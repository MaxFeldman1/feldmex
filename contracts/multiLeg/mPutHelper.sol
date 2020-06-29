pragma solidity >=0.5.0;

import "./multiPutExchange.sol";

contract mPutHelper {
	address public addr;

	function deploy(address _strikeAssetAddress, address _optionsAddress) public {
		addr = address(new multiPutExchange(_strikeAssetAddress, _optionsAddress));
	}
}
