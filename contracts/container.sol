pragma solidity ^0.5.12;
import "./oracle.sol";
import "./options.sol";
import "./exchange.sol";
import "./helpers/oHelper.sol";
import "./helpers/eHelper.sol";
import "./helpers/orcHelper.sol";
import "./doubleAssetYieldEnabledToken.sol";

contract container is doubleAssetYieldEnabledToken {
	
	//smart contract that records prices, records (reservesOfAsset1)/(reservesOfAsset2)
	ITimeSeriesOracle public oracleContract;
	//smart contract on which options may be traded
	exchange public exchangeContract;
	//exchange contract for inverse trading pair
	exchange public exchangeContract2;
    //address of the FeldmexERC20Helper contract that is responsible for providing ERC20 interfaces for options
    address feldmexERC20HelperAddress;

	//address of the smart contract that helps deploy optionsContract
	address oHelperAddress;
	//address of the smart contract that helps deploy exchangeContract
	address eHelperAddress;


	/*
		@Description: Assigns inital values and credits the owner of this contract with all coins

		@param address _asset1Address: the address of the ERC0 contract of asset1
		@param address _asset2Address: the address of the ERC20 contract of asset2
		@param address _oHelperAddress: the address of the oHelper contract that helps with deployment of the options contract
		@param address _eHelperAddress: the address of the eHelper contract that helps with deployment of the exchange contract
	*/
	constructor (address _asset1Address, address _asset2Address, address _oHelperAddress, address _eHelperAddress, address _orcHelperAddress) public doubleAssetYieldEnabledToken(_asset1Address, _asset2Address) {
		address _oracleAddress = orcHelper(_orcHelperAddress).oracleAddresses(_asset1Address, _asset2Address);
		if (_oracleAddress == address(0)) {
			(bool success, ) = _orcHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _asset1Address, _asset2Address));
			assert(success);
			_oracleAddress = orcHelper(_orcHelperAddress).oracleAddresses(_asset1Address, _asset2Address);
		}
		oracleContract = ITimeSeriesOracle(_oracleAddress);
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
	}

	/*
		@Description: calls oHelper contract to deploy options contract and assigns said contract to the optionsContract variable
			may only be called when progress == 0

		@return bool success: true if function executes sucessfully
	*/
	function depOptions() onlyOwner public returns (bool success){
		uint8 _progress = progress; //gas savings
		require(_progress == 0 || _progress == 2, "progress must == 0 or 2");
		if (_progress == 0) {
			(success, ) = oHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(oracleContract), address(Asset1Contract), address(Asset2Contract)));
			require(success, "could not sucessfully deploy options contract");
			optionsContract = options(oHelper(oHelperAddress).optionsAddress(address(this), 0));
		}
		else {
			(success, ) = oHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(oracleContract), address(Asset2Contract), address(Asset1Contract)));
			require(success, "could not sucessfully deploy options contract");
			optionsContract2 = options(oHelper(oHelperAddress).optionsAddress(address(this), 1));
		}
		progress++;
	}

	/*
		@Description: calls eHelper contract to deploy exchange contract and assigns said contract to the exchangeContract variable
			may only be called when progress == 1

		@return bool success: true if function executes sucessfully
	*/
	function depExchange() onlyOwner public returns (bool success){
		uint8 _progress = progress; //gas savings
		require(_progress == 1 || _progress == 3, "progress must == 1 or 3");
		if (_progress == 1) {
			(success, ) = eHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(Asset1Contract), address(Asset2Contract), address(optionsContract)));
			require(success, "could not sucessfully deploy exchange contract");
			exchangeContract = exchange(eHelper(eHelperAddress).exchangeAddress(address(this), 0));
			optionsContract.setExchangeAddress(address(exchangeContract));
		} else {
			(success, ) = eHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(Asset2Contract), address(Asset1Contract), address(optionsContract2)));
			require(success, "could not sucessfully deploy exchange contract");
			exchangeContract2 = exchange(eHelper(eHelperAddress).exchangeAddress(address(this), 1));
			optionsContract2.setExchangeAddress(address(exchangeContract2));	
		}
		progress++;
	}

}