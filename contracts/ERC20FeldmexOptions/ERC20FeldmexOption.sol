pragma solidity ^0.5.12;
import "../interfaces/ERC20.sol";
import "../options.sol";

contract ERC20FeldmexOption is ERC20 {


	address public optionsHandlerAddress;

	address public underlyingAssetAddress;
	address public strikeAssetAddress;

	uint public maturity;
	uint public strike;
	bool public call;

	uint public decimals = 0;
	string public symbol = "FDMX";
	string public name;

	uint coinSubUnits;

	// owner => spender => remaining
	mapping(address => mapping(address => uint)) public allowance;

	constructor(address _optionsHandlerAddress, uint _maturity, uint _strike, bool _call) public {
		maturity = _maturity;
		strike = _strike;
		call = _call;
		optionsHandlerAddress = _optionsHandlerAddress;
		options optionsContract = options(_optionsHandlerAddress);
		underlyingAssetAddress = optionsContract.underlyingAssetAddress();
		strikeAssetAddress = optionsContract.strikeAssetAddress();
		name = _call ? "Feldmex Call" : "Feldmex Puts";
		coinSubUnits = 10 ** uint(ERC20(_call ? underlyingAssetAddress : strikeAssetAddress).decimals());
	}

	function totalSupply() public view returns (uint supply){
		supply = 0;
	}

	function balanceOf(address _owner) public view returns (uint balance){
		int ret = options(optionsHandlerAddress).balanceOf(_owner, maturity, strike, call);
		balance = ret > 0 ? uint(ret) : 0;
	}

	function transfer(address _to, uint _value) public returns (bool success){
		options optionsContract = options(optionsHandlerAddress);
		uint _maturity = maturity;	//gas savings
		require(balanceOf(msg.sender) >= _value || optionsContract.containedStrikes(msg.sender,_maturity,strike));
		loadPosition(_value);
		optionsContract.setParams(msg.sender, _to, _maturity);
		emit Transfer(msg.sender, _to, _value);
		success = assignPosition();
	}

	function transferFrom(address _from, address _to, uint _value) public returns (bool success){
		require(allowance[_from][msg.sender] >= _value);
		options optionsContract = options(optionsHandlerAddress);
		uint _maturity = maturity;	//gas savings
		require(balanceOf(_from) >= _value || optionsContract.containedStrikes(_from,_maturity,strike));
		allowance[_from][msg.sender] -= _value;
		loadPosition(_value);
		optionsContract.setParams(_from, _to, maturity);
		emit Transfer(_from, _to, _value);
		success = assignPosition();
	}

	function approve(address _spender, uint _value) public returns (bool success){
		allowance[msg.sender][_spender] = _value;
		emit Approval(msg.sender, _spender, _value);
		success = true;
	}

	function loadPosition(uint _value) internal {
		bool _call = call; //gas savings
		uint _strike = strike;	//gas savings
		options optionsContract = options(optionsHandlerAddress);
		optionsContract.clearPositions();
		optionsContract.addPosition(_strike, int(_value), _call);
		optionsContract.setLimits(_value * (_call ? coinSubUnits : _strike), 0);
		optionsContract.setPaymentParams(true, 0);
		optionsContract.setTrustedAddressFeldmexERC20(maturity, _strike, _call);
	}

	function assignPosition() public returns (bool success) {
		address _optionsHandlerAddress = optionsHandlerAddress;
		if (call)
			(success, ) = _optionsHandlerAddress.call(abi.encodeWithSignature("assignCallPosition()"));
		else
			(success, ) = _optionsHandlerAddress.call(abi.encodeWithSignature("assignPutPosition()"));
		assert(success);
	}
}