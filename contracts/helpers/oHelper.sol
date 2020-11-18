pragma solidity >=0.6.0;
import "../optionsHandler/OptionsHandler.sol";
import "../interfaces/Ownable.sol";

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
		address temp = address(new OptionsHandler(_oracleAddress, _underlyingAssetAddress, _strikeAssetAddress,
			feldmexERC20HelperAddress, mOrganizerAddress, assignOptionsDelegateAddress, feeOracleAddress));
		optionsAddress[msg.sender][index] = temp;
		Ownable(temp).transferOwnership(msg.sender);
	}

}