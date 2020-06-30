pragma solidity ^0.5.12;
import "../interfaces/Ownable.sol";
import "../oracle.sol";


contract orcHelper {
	mapping(address => mapping(address => address)) public oracleAddresses;

	function deploy(address _underlyingAssetAddress, address _strikeAssetAddress) public {
		require(_underlyingAssetAddress != _strikeAssetAddress, "underlying asset must not be the same as strike asset");
		if (oracleAddresses[_underlyingAssetAddress][_strikeAssetAddress] != address(0)) return;
		oracleAddresses[_underlyingAssetAddress][_strikeAssetAddress] = address(new oracle(_underlyingAssetAddress, _strikeAssetAddress));
		oracleAddresses[_strikeAssetAddress][_underlyingAssetAddress] = oracleAddresses[_underlyingAssetAddress][_strikeAssetAddress];
	}

}