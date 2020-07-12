pragma solidity >=0.6.0;
import "../interfaces/Ownable.sol";
import "./ERC20FeldmexOption.sol";

//---------s-u-p-p-o-r-t---E-R-C-2-0---f-o-r---s-p-e-c-i-f-c---o-p-t-i-o-n-s--------

contract FeldmexERC20Helper is Ownable {

	//optionsHandler => maturity => strike => contract address
	mapping(address => mapping(uint => mapping(uint => address))) public callAddresses;
	mapping(address => mapping(uint => mapping(uint => address))) public putAddresses;

	function deployNew(address _optionsHandlerAddress, uint _maturity, uint _strike, bool _call) public {
		require((_call ? callAddresses[_optionsHandlerAddress][_maturity][_strike] : putAddresses[_optionsHandlerAddress][_maturity][_strike]) == address(0));
		address addr = address(new ERC20FeldmexOption(_optionsHandlerAddress, _maturity, _strike, _call));
		if (_call)
			callAddresses[_optionsHandlerAddress][_maturity][_strike] = addr;
		else
			putAddresses[_optionsHandlerAddress][_maturity][_strike] = addr;
	}
}