pragma solidity >=0.8.0;
import "../interfaces/Ownable.sol";
import "../containers/container.sol";

/*
	This contract allows us to deploy the options smart contract without going over gas limit

    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract cHelper is Ownable {
	mapping(address => mapping(address => address)) public containerAddress;

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress, address _oHelperAddress, address _eHelperAddress, address _orcHelperAddress) onlyOwner public {
		containerAddress[_underlyingAssetAddress][_strikeAssetAddress] = address(new container(_underlyingAssetAddress, _strikeAssetAddress, _oHelperAddress, _eHelperAddress, _orcHelperAddress));
		container(containerAddress[_underlyingAssetAddress][_strikeAssetAddress]).transferOwnership(msg.sender);
		containerAddress[_strikeAssetAddress][_underlyingAssetAddress] = containerAddress[_underlyingAssetAddress][_strikeAssetAddress];
	}

}