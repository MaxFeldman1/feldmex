pragma solidity ^0.5.12;

import "../options.sol";
import "./mCallHelper.sol";
import "./mPutHelper.sol";

contract mOrganizer {

	//options address => [multiCallExchange address, multiPutExchange address] 
	mapping(address => address[2]) public exchangeAddresses;

	address public mCallHelperAddress;
	address public mPutHelperAddress;
	constructor (address _mCallHelperAddress, address _mPutHelperAddress) public {
		mCallHelperAddress = _mCallHelperAddress;
		mPutHelperAddress = _mPutHelperAddress;
	}

	function deployCallExchange(address _optionsAddress) public returns (bool success) {
		address _underlyingAssetAddress = options(_optionsAddress).underlyingAssetAddress();
		address _mCallHelperAddress = mCallHelperAddress;	//gas savings
		(success, ) = _mCallHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _underlyingAssetAddress, _optionsAddress));
		require(success);
		exchangeAddresses[_optionsAddress][0] = mCallHelper(_mCallHelperAddress).addr();
	}

	function deployPutExchange(address _optionsAddress) public returns (bool success) {
		address _strikeAssetAddress = options(_optionsAddress).strikeAssetAddress();
		address _mPutHelperAddress = mPutHelperAddress;	//gas savings
		(success, ) = _mPutHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _strikeAssetAddress, _optionsAddress));
		require(success);
		exchangeAddresses[_optionsAddress][1] = mPutHelper(_mPutHelperAddress).addr();
	}

}