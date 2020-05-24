pragma solidity ^0.5.12;
import "./oracle.sol";
import "./ERC20.sol";
import "./options.sol";
import "./exchange.sol";
import "./oHelper.sol";
import "./eHelper.sol";

contract container is ERC20 {
	address owner;
	
	oracle public oracleContract;
	options public optionsContract;
	exchange public exchangeContract;
	ERC20 public underlyingAssetContract;
	ERC20 public strikeAssetContract;

	address oHelperAddress;
	address eHelperAddress;

	/*
		represents the stage of setup
		progress == 0 => constructor has been executed
		progress == 1 => optionsContract has been set
		progress == 2 => exchangeContract has been set

		When progress == 2 set up is complete
	*/
	uint8 public progress;

	uint public lastWithdraw;

	mapping(address => uint) lastClaim;
	uint[] public contractBalanceUnderlying;
	uint[] public contractBalanceStrike;

	mapping(address => uint) balanceUnderlying;
	function viewUnderlyingAssetBalance() public view returns (uint) {return balanceUnderlying[msg.sender];}
	mapping(address => uint) balanceStrike;
	function viewStrikeAssetBalance() public view returns (uint) {return balanceStrike[msg.sender];}

	//ERC20 implementation
	uint public totalSupply;
	uint8 public decimals;
	mapping(address => uint) public balanceOf;
	mapping(address => mapping(address => uint)) public allowance;

	//---------------contract setup-----------------
	constructor (address _underlyingAssetAddress, address _strikeAssetAddress, address _oHelperAddress, address _eHelperAddress, uint _totalCoins, uint8 _decimals) public {
		if (_totalCoins == 0) _totalCoins = 1000000;
		if (_decimals == 0) _decimals = 4;
		owner = msg.sender;
		decimals = _decimals;
		totalSupply = _totalCoins * (uint(10) ** decimals);
		balanceOf[owner] = totalSupply;

		underlyingAssetContract = ERC20(_underlyingAssetAddress);
		strikeAssetContract = ERC20(_strikeAssetAddress);
		oracleContract = new oracle();
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
		contractBalanceUnderlying.push(0);
		contractBalanceStrike.push(0);
	}

	function depOptions() public returns (bool success){
		require(msg.sender == owner && progress == 0);
		(success, ) = oHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(oracleContract), address(underlyingAssetContract), address(strikeAssetContract)));
		require(success);
		optionsContract = options(oHelper(oHelperAddress).optionsAddress());
		progress = 1;
		return true;
	}

	function depExchange() public returns (bool success){
		require(msg.sender == owner && progress == 1);
		(success, ) = eHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(underlyingAssetContract), address(strikeAssetContract), address(optionsContract)));
		require(success);
		exchangeContract = exchange(eHelper(eHelperAddress).exchangeAddress());
		optionsContract.setExchangeAddress(address(exchangeContract));
		progress = 2;
		return true;
	}
	//----------------end contract setup------------

	function setFee(uint _feeDeonominator) public {
		require(msg.sender == owner);
		optionsContract.setFee(_feeDeonominator);
	}


	/*
		@Description: Calls options.withdrawFunds() from this contract afterwards users may claim their own portion of the funds
			may be called once a day
	*/
	function contractClaim() public returns (uint underlyingAsset, uint strikeAsset) {
		require(lastWithdraw < block.timestamp - 86400);
		lastWithdraw = block.timestamp;
		(underlyingAsset, strikeAsset) = optionsContract.withdrawFunds();
		contractBalanceUnderlying.push(contractBalanceUnderlying[contractBalanceUnderlying.length-1] + underlyingAsset);
		contractBalanceStrike.push(contractBalanceStrike[contractBalanceStrike.length-1] + strikeAsset);
		return (underlyingAsset, strikeAsset);
	}

	/*
		@Description: allows token holders to claim their portion of the cashflow
	*/
	function publicClaim() public {
		claim(msg.sender);
	}

	/*
		@Description: allows token holders to claim their portion of the cashflow
	*/
	function claim(address _addr) internal {
		uint mostRecent = lastClaim[_addr];
		lastClaim[_addr] = contractBalanceUnderlying.length-1;
		uint totalIncreace = contractBalanceUnderlying[contractBalanceUnderlying.length-1] - contractBalanceUnderlying[mostRecent];
		balanceUnderlying[_addr] += totalIncreace * balanceOf[_addr] / totalSupply;
		totalIncreace = contractBalanceStrike[contractBalanceStrike.length-1] - contractBalanceStrike[mostRecent];
		balanceStrike[_addr] += totalIncreace * balanceOf[_addr] / totalSupply;
	}


    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively

        @return uint underlyingAsset: the amount of the underlying asset that has been withdrawn
        @return uint strikeAsset: the amount of the strike asset that has been withdrawn
    */
    function withdrawFunds() public returns(uint underlyingAsset, uint strikeAsset){
        underlyingAsset = balanceUnderlying[msg.sender];
        balanceUnderlying[msg.sender] = 0;
        assert(underlyingAssetContract.transfer(msg.sender, underlyingAsset));
        strikeAsset = balanceStrike[msg.sender];
        balanceStrike[msg.sender] = 0;
        assert(strikeAssetContract.transfer(msg.sender, strikeAsset));
        return (underlyingAsset, strikeAsset);
    }


	//ERC20 implementation
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );

    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);

        claim(msg.sender);
        claim(_to);

        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= balanceOf[_from]);
        require(_value <= allowance[_from][msg.sender]);

        claim(_from);
        claim(_to);

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }


}