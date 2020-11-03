pragma solidity >=0.6.0;
import "../interfaces/IERC20.sol";
import "../optionsHandler/options.sol";

contract ERC20FeldmexOption is IERC20 {


	address public optionsHandlerAddress;

	address public underlyingAssetAddress;
	address public strikeAssetAddress;

	uint public maturity;
	uint public strike;
	bool public call;

	uint8 public override decimals;
	string public symbol = "FDMX";
	string public name;

	uint coinSubUnits;

	// owner => spender => remaining
	mapping(address => mapping(address => uint)) public override allowance;

	/*
		@Description: Setup

		@param address _optionsHandlerAddress: address of the main options handler contract that this contract must interact with
		@param uint _maturity: the maturity of the option delegated to this specific contract
		@param uint _strike: the strike of the option delegated to this specific contract
		@param bool _call: true if this contract is supposed to handle calls false if puts
	*/
	constructor(address _optionsHandlerAddress, uint _maturity, uint _strike, bool _call) public {
		maturity = _maturity;
		strike = _strike;
		call = _call;
		optionsHandlerAddress = _optionsHandlerAddress;
		options optionsContract = options(_optionsHandlerAddress);
		address _underlyingAssetAddress = optionsContract.underlyingAssetAddress();
		address _strikeAssetAddress = optionsContract.strikeAssetAddress();
		decimals = IERC20(_call ? _underlyingAssetAddress : _strikeAssetAddress).decimals();
		underlyingAssetAddress = _underlyingAssetAddress;
		strikeAssetAddress = _strikeAssetAddress;
		name = _call ? "Feldmex Call" : "Feldmex Puts";
		coinSubUnits = 10 ** uint(IERC20(_call ? underlyingAssetAddress : strikeAssetAddress).decimals());
	}

	/*
		@Description: all long and short positions cancel out for a total supply of 0
	*/
	function totalSupply() public view override returns (uint supply){
		supply = 0;
	}

	/*
		@Description: if balance is positive returns the amount of options held by a specific address 
			otherwise 0 is retuned
	*/
	function balanceOf(address _owner) public view override returns (uint balance){
		int ret = options(optionsHandlerAddress).balanceOf(_owner, maturity, strike, call);
		balance = ret > 0 ? uint(ret) : 0;
	}

	/*
		@Description: mint _value quntity of options with msg.sender as the debtor and _to as the receiver
	*/
	function transfer(address _to, uint _value) public override returns (bool success){
		options optionsContract = options(optionsHandlerAddress);
		uint _maturity = maturity;	//gas savings
		require(balanceOf(msg.sender) >= _value || optionsContract.containedStrikes(msg.sender,_maturity,strike));
		loadPosition(_value);
		optionsContract.setParams(msg.sender, _to, _maturity);
		emit Transfer(msg.sender, _to, _value);
		success = assignPosition();
	}

	/*
		@Description: mint _value quntity of options with _from as the debtor and _to as the receiver
	*/
	function transferFrom(address _from, address _to, uint _value) public override returns (bool success){
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

	/*
		@Description: allow _spender to transferFrom _value quantity of options with msg.sender as the debtor
	*/
	function approve(address _spender, uint _value) public override returns (bool success){
		allowance[msg.sender][_spender] = _value;
		emit Approval(msg.sender, _spender, _value);
		success = true;
	}

	/*
		@Description: interacts with the option handler contract to prepare for assignment of the position
	*/
	function loadPosition(uint _value) internal {
		bool _call = call; //gas savings
		uint _strike = strike;	//gas savings
		options optionsContract = options(optionsHandlerAddress);
		optionsContract.clearPositions();
		optionsContract.addPosition(_strike, int(_value), _call);
		optionsContract.setLimits(int(_value * (_call ? coinSubUnits : _strike)), 0);
		optionsContract.setPaymentParams(true, 0);
		optionsContract.setTrustedAddressFeldmexERC20(maturity, _strike, _call);
	}

	/*
		@Description: interacts with the option handler contract to move options between users
	*/
	function assignPosition() public returns (bool success) {
		address _optionsHandlerAddress = optionsHandlerAddress;
		if (call)
			(success, ) = _optionsHandlerAddress.call(abi.encodeWithSignature("assignCallPosition()"));
		else
			(success, ) = _optionsHandlerAddress.call(abi.encodeWithSignature("assignPutPosition()"));
		assert(success);
	}
}