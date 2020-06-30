pragma solidity ^0.5.12;
import "./container.sol";
import "./helpers/cHelper.sol";
import "./interfaces/Ownable.sol";

contract organiser is Ownable {
	address public cHelperAddress;
	address public oHelperAddress;
	address public eHelperAddress;
	address public orcHelperAddress;

	constructor (address _cHelperAddress, address _oHelperAddress, address _eHelperAddress, address _orcHelperAddress) public {
		cHelperAddress = _cHelperAddress;
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
		orcHelperAddress = _orcHelperAddress;
	}

	function progressContainer(address _underlyingAssetAddress, address _strikeAssetAddress) public returns (bool success, uint progress){
		//require that this is a pair on uniswap
		address containerAddress = cHelper(cHelperAddress).containerAddress(_underlyingAssetAddress, _strikeAssetAddress);
		if (containerAddress == address(0)) {
			//deploy new
			(success, ) = cHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address,address,address)",_underlyingAssetAddress, _strikeAssetAddress, oHelperAddress, eHelperAddress, orcHelperAddress));
			require(success, "could not deploy container");
			return (true, 0);
		}
		uint8 currentProgress = container(containerAddress).progress();
		if (currentProgress == 2) return (true, 2); //container is fully set up
		if (currentProgress == 0) {
			//deploy options smart contract
			(success, ) = containerAddress.call(abi.encodeWithSignature("depOptions()"));
			require(success, "could not deploy options smart contract");
			return (true, 1);
		}
		//current progress == 1
		//deploy exchange smart contract
		(success, ) = containerAddress.call(abi.encodeWithSignature("depExchange()"));
		require(success, "could not deploy exchange smart contract");
		success = true;
		progress = 2;
	}
}