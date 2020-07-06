pragma solidity ^0.5.12;

import "../options.sol";
import "./mCallHelper.sol";
import "./mPutHelper.sol";
import "./mLegHelper.sol";

contract mOrganizer {

	//options address => [multiCallExchange address, multiPutExchange address] 
	mapping(address => address[3]) public exchangeAddresses;

	address public mCallHelperAddress;
	address public mPutHelperAddress;
	address public mLegHelperAddress;
	constructor (address _mCallHelperAddress, address _mPutHelperAddress, address _mLegHelperAddress) public {
		mCallHelperAddress = _mCallHelperAddress;
		mPutHelperAddress = _mPutHelperAddress;
		mLegHelperAddress = _mLegHelperAddress;
	}

	function deployCallExchange(address _optionsAddress) public returns (bool success) {
		require(exchangeAddresses[_optionsAddress][0] == address(0));
		address _underlyingAssetAddress = options(_optionsAddress).underlyingAssetAddress();
		address _mCallHelperAddress = mCallHelperAddress;	//gas savings
		(success, ) = _mCallHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _underlyingAssetAddress, _optionsAddress));
		require(success);
		exchangeAddresses[_optionsAddress][0] = mCallHelper(_mCallHelperAddress).addr();
	}

	function deployPutExchange(address _optionsAddress) public returns (bool success) {
		require(exchangeAddresses[_optionsAddress][1] == address(0));
		address _strikeAssetAddress = options(_optionsAddress).strikeAssetAddress();
		address _mPutHelperAddress = mPutHelperAddress;	//gas savings
		(success, ) = _mPutHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _strikeAssetAddress, _optionsAddress));
		require(success);
		exchangeAddresses[_optionsAddress][1] = mPutHelper(_mPutHelperAddress).addr();
	}

	function deployMultiLegExchange(address _optionsAddress) public returns (bool success) {
		require(exchangeAddresses[_optionsAddress][2] == address(0));
		address _underlyingAssetAddress = options(_optionsAddress).underlyingAssetAddress();
		address _strikeAssetAddress = options(_optionsAddress).strikeAssetAddress();
		address _mLegHelperAddress = mLegHelperAddress;	//gas savings
		(success, ) = _mLegHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", _underlyingAssetAddress, _strikeAssetAddress, _optionsAddress));
		require(success);
		exchangeAddresses[_optionsAddress][2] = mLegHelper(_mLegHelperAddress).addr();
	}

}