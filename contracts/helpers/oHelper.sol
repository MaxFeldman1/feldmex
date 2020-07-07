pragma solidity ^0.5.12;
import "../options.sol";

//allows us to deploy the options smart contract without going over gas limit
contract oHelper {
	mapping(address => address[2]) public optionsAddress;

	address feldmexERC20HelperAddress;
	address mOrganizerAddress;
	address assignOptionsDelegateAddress;
	address feeOracleAddress;
	constructor (address _feldmexERC20HelperAddress, address _mOrganizerAddress, address _assignOptionsDelegateAddress, address _feeOracleAddress) public {
		feldmexERC20HelperAddress = _feldmexERC20HelperAddress;
		mOrganizerAddress = _mOrganizerAddress;
		assignOptionsDelegateAddress = _assignOptionsDelegateAddress;
		feeOracleAddress = _feeOracleAddress;
	}

	function deploy(address _oracleAddress, address _underlyingAssetAddress, address _strikeAssetAddress) public {
		uint8 index = optionsAddress[msg.sender][0] == address(0) ? 0 : 1;
		optionsAddress[msg.sender][index] = address(new options(_oracleAddress, _underlyingAssetAddress, _strikeAssetAddress,
			feldmexERC20HelperAddress, mOrganizerAddress, assignOptionsDelegateAddress, feeOracleAddress));
		options(optionsAddress[msg.sender][index]).transferOwnership(msg.sender);
	}

}