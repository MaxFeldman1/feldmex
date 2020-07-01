pragma solidity ^0.5.12;
import "./interfaces/Ownable.sol";
import "./ERC20FeldmexOption.sol";

//---------s-u-p-p-o-r-t---E-R-C-2-0---f-o-r---s-p-e-c-i-f-c---o-p-t-i-o-n-s--------

contract FeldmexERC20Helper is Ownable {

	//optionsHandler => maturity => strike => contract address
	mapping(address => mapping(uint => mapping(uint => address))) public callERC20s;
	mapping(address => mapping(uint => mapping(uint => address))) public putERC20s;

	function deployNew(address _optionsHandlerAddress, uint _maturity, uint _strike, bool _call) public {
		require((_call ? callERC20s[_optionsHandlerAddress][_maturity][_strike] : putERC20s[_optionsHandlerAddress][_maturity][_strike]) == address(0));
		address addr = address(new ERC20FeldmexOption(_optionsHandlerAddress, _maturity, _strike, _call));
		if (_call)
			callERC20s[_optionsHandlerAddress][_maturity][_strike] = addr;
		else
			putERC20s[_optionsHandlerAddress][_maturity][_strike] = addr;
	}
}