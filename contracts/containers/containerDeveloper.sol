pragma solidity >=0.8.0;
import "./container.sol";
import "../helpers/cHelper.sol";
import "../interfaces/Ownable.sol";

contract containerDeveloper is Ownable {
	address public cHelperAddress;
	address public oHelperAddress;
	address public eHelperAddress;
	address public orcHelperAddress;

	constructor (address _cHelperAddress, address _oHelperAddress, address _eHelperAddress, address _orcHelperAddress) {
		cHelperAddress = _cHelperAddress;
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
		orcHelperAddress = _orcHelperAddress;
	}

	/*
		@Description: deploy the necessary contracts to enable full functionality of a specific options chain

		@param address _asset1Address: one of the two assets in the trading pair
		@param address _asset2Address: the other of the two assets in the trading pair

		@return bool success: true if function executes sucessfully
		@return uint progress: the number of deployments that have been made to set up the container - 1
			because we start counting at 0
	*/
	function progressContainer(address _asset1Address, address _asset2Address) public returns (bool success, uint progress){
		//require that this is a pair on uniswap
		address containerAddress = cHelper(cHelperAddress).containerAddress(_asset1Address, _asset2Address);
		if (containerAddress == address(0)) {
			//deploy new
			(success, ) = cHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address,address,address)",_asset1Address, _asset2Address, oHelperAddress, eHelperAddress, orcHelperAddress));
			require(success, "could not deploy container");
			return (true, 0);
		}
		uint8 currentProgress = container(containerAddress).progress();
		if (currentProgress == 4) return (true, 4); //container is fully set up
		if (currentProgress%2 == 0) {
			//deploy options smart contract
			(success, ) = containerAddress.call(abi.encodeWithSignature("depOptions()"));
			require(success, "could not deploy options smart contract");
			return (true, currentProgress+1);
		}
		//current progress == 1
		//deploy exchange smart contract
		(success, ) = containerAddress.call(abi.encodeWithSignature("depExchange()"));
		require(success, "could not deploy exchange smart contract");
		success = true;
		progress = currentProgress+1;
	}
}