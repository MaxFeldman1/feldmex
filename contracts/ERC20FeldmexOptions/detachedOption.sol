pragma solidity >=0.6.0;
import "../interfaces/IERC20.sol";
import "./ERC20FeldmexOption.sol";
import "../optionsHandler/options.sol";

contract detachedOption is IERC20 {

	uint8 public override decimals;
	string public symbol = "dFDMX";

	address public baseERC20FeldmexOptionAddress;

	address public underlyingAssetAddress;
	address public strikeAssetAddress;

	uint public maturity;
	uint public strike;
	bool public call;

	bool public inPayoutPhase;
	uint public totalPayout;

	// owner => amount
	mapping(address => uint) public override balanceOf;

	// owner => spender => allowance remaining
	mapping(address => mapping(address => uint)) public override allowance;

	uint public override totalSupply;

	constructor(
		address _underlyingAssetAddress, address _strikeAssetAddress,
		uint _maturity, uint _strike, uint8 _decimals, bool _call
	) public {
		baseERC20FeldmexOptionAddress = msg.sender;
		underlyingAssetAddress = _underlyingAssetAddress;
		strikeAssetAddress = _strikeAssetAddress;
		maturity = _maturity;
		strike = _strike;
		call = _call;
		decimals = _decimals;
	}

	function transfer(address _to, uint _value) public override returns (bool success) {
		require(balanceOf[msg.sender] >= _value, "insufficent balance");
		balanceOf[msg.sender] -= _value;
		balanceOf[_to] += _value;

		emit Transfer(msg.sender, _to, _value);
		success = true;
	}

	/*
		@Description: mint _value quntity of options with _from as the debtor and _to as the receiver
	*/
	function transferFrom(address _from, address _to, uint _value) public override returns (bool success){
		require(allowance[_from][msg.sender] >= _value, "allowance must be greater than value");
		require(balanceOf[_from] >= _value, "insufficent balance");

		allowance[_from][msg.sender] -= _value;

		balanceOf[_from] -= _value;
		balanceOf[_to] += _value;

		emit Transfer(_from, _to, _value);
		success = true;
	}

	/*
		@Description: allow _spender to transferFrom _value quantity of options with msg.sender as the debtor
	*/
	function approve(address _spender, uint _value) public override returns (bool success){
		allowance[msg.sender][_spender] = _value;
		emit Approval(msg.sender, _spender, _value);
		success = true;
	}


	function deposit(uint _amount, address _to) public {
		IERC20(baseERC20FeldmexOptionAddress).transferFrom(_to, address(this), _amount);
		balanceOf[msg.sender] += _amount;
		totalSupply += _amount;
	}

	function withdraw(uint _amount, address _to) public {
		require(balanceOf[msg.sender] >= _amount);
		balanceOf[msg.sender] -= _amount;
		IERC20(baseERC20FeldmexOptionAddress).transfer(_to, _amount);
		totalSupply -= _amount;
	}

	function enterPayoutPhase() public {
		uint _maturity = maturity;	//gas savings
		require(block.timestamp > _maturity, "can only enter payout phase after maturity");

		address optionsHandlerAddress = ERC20FeldmexOption(baseERC20FeldmexOptionAddress).optionsHandlerAddress();
		(bool success, ) = optionsHandlerAddress.call(abi.encodeWithSignature("claim(uint256)", _maturity));
		require(success, "failed to claim funds in options handler");

		if (call)
			(totalPayout, ) = options(optionsHandlerAddress).withdrawFunds();
		else
			( ,totalPayout) = options(optionsHandlerAddress).withdrawFunds();

		inPayoutPhase = true;
	}

	function claim(address _to) public returns (uint _amount, uint _payout) {
		require(inPayoutPhase, "must be in payout phase before funds may be claimed");
		_amount = balanceOf[msg.sender];
		_payout = _amount * totalPayout / totalSupply;
		IERC20(call ? underlyingAssetAddress : strikeAssetAddress).transfer(_to, _amount);
	}
}