pragma solidity ^0.5.12;
import "./oracle.sol";
import "./ERC20.sol";
import "./options.sol";
import "./exchange.sol";
import "./oHelper.sol";
import "./eHelper.sol";
import "./Ownable.sol";
import "./yield.sol";

contract container is ERC20, Ownable, yield {
	
	//smart contract that records prices, records (priceOfUnderlyingAsset)/(priceOfStrikeAsset)
	oracle public oracleContract;
	//smart contract that handles settlement of calls and puts
	options public optionsContract;
	//smart contract on which options may be traded
	exchange public exchangeContract;
	//smart contract of the asset in the numerator of oracle price
	ERC20 public underlyingAssetContract;
	//smart contract of the asset in the denominator of oracle price
	ERC20 public strikeAssetContract;

	//address of the smart contract that helps deploy optionsContract
	address oHelperAddress;
	//address of the smart contract that helps deploy exchangeContract
	address eHelperAddress;

	/*
		represents the stage of setup
		progress == 0 => constructor has been executed
		progress == 1 => optionsContract has been set
		progress == 2 => exchangeContract has been set

		When progress == 2 set up is complete
	*/
	uint8 public progress;

	//timestamp of last time this smart contract called optionContract.withdrawFunds()
	uint public lastWithdraw;



	//total amount of smallest denomination units of coin in this smart contract
	uint public totalSupply;
	//10 ** decimals == the number of sub units in a whole coin
	uint8 public decimals;
	//each user's balance of coins
	mapping(address => uint) public balanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) public allowance;

	//---------------contract setup-----------------
	/*
		@Description: Assigns inital values and credits the owner of this contract with all coins

		@param address _underlyingAssetAddress: the address of the ERC0 contract of the underlying asset
		@param address _strikeAssetAddress: the address of the ERC20 contract of the strike asset
		@param address _oHelperAddress: the address of the oHelper contract that helps with deployment of the options contract
		@param address _eHelperAddress: the address of the eHelper contract that helps with deployment of the exchange contract
		@param uint _totalCoins: the number of full coins to be included in the total supply
		@param uint _decimals: the number of digits to which each full unit of coin is divisible
	*/
	constructor (address _underlyingAssetAddress, address _strikeAssetAddress, address _oHelperAddress, address _eHelperAddress, uint _totalCoins, uint8 _decimals) public {
		if (_totalCoins == 0) _totalCoins = 1000000;
		if (_decimals == 0) _decimals = 4;
		owner = msg.sender;
		decimals = _decimals;
		totalSupply = _totalCoins * (uint(10) ** decimals);
		balanceOf[owner] = totalSupply;
		yieldDistribution[msg.sender][msg.sender] = totalSupply;
		totalYield[msg.sender] = totalSupply;

		underlyingAssetContract = ERC20(_underlyingAssetAddress);
		strikeAssetContract = ERC20(_strikeAssetAddress);
		oracleContract = new oracle();
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
		contractBalanceUnderlying.push(0);
		contractBalanceStrike.push(0);
	}

	/*
		@Description: calls oHelper contract to deploy options contract and assigns said contract to the optionsContract variable
			may only be called when progress == 0

		@return bool success: true if function executes sucessfully
	*/
	function depOptions() onlyOwner public returns (bool success){
		require(progress == 0, "progress must == 0");
		(success, ) = oHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(oracleContract), address(underlyingAssetContract), address(strikeAssetContract)));
		require(success, "could not sucessfully deploy options contract");
		optionsContract = options(oHelper(oHelperAddress).optionsAddress());
		progress = 1;
		return true;
	}

	/*
		@Description: calls eHelper contract to deploy exchange contract and assigns said contract to the exchangeContract variable
			may only be called when progress == 1

		@return bool success: true if function executes sucessfully
	*/
	function depExchange() onlyOwner public returns (bool success){
		require(progress == 1, "progress must == 1");
		(success, ) = eHelperAddress.call(abi.encodeWithSignature("deploy(address,address,address)", address(underlyingAssetContract), address(strikeAssetContract), address(optionsContract)));
		require(success, "could not sucessfully deploy exchange contract");
		exchangeContract = exchange(eHelper(eHelperAddress).exchangeAddress());
		optionsContract.setExchangeAddress(address(exchangeContract));
		progress = 2;
		return true;
	}

	function changeFeeStatus(address _addr) onlyOwner public returns (bool success){
		optionsContract.changeFeeStatus(_addr);
		return true;
	}
	//----------------end contract setup------------

	/*
		@Description: the owner may call this function to set the fee denominator in the options smart contract

		@param uint _feeDenominator: the value to pass to optionsContract.setFee
	*/
	function setFee(uint _feeDeonominator) onlyOwner public {
		optionsContract.setFee(_feeDeonominator);
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


    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value,
        address indexed _yieldOwner
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value,
        address indexed _yieldOwner
    );

    /*
		@Description: transfer a specified amount of coins from the sender to a specified

		@param address _to: the address to which to send coins
		@param address _value: the amount of sub units of coins to send

		@return bool success: true if function executes sucessfully
    */
    function transfer(address _to, uint256 _value) public returns (bool success) {
        return transferTokenOwner(_to, _value, msg.sender);
    }

    /*
		@Description: approve another address to spend coins on the function caller's behalf

		@param address _spender: the address to approve
		@param uint256 _value: the amount of sub units of coins to allow to be spent

		@return bool success: true if function executes sucessfully
    */
    function approve(address _spender, uint256 _value) public returns (bool success) {
        return approveYieldOwner(_spender, _value, msg.sender);
    }


    /*
		@Description: transfer funds from one address to another given that the from address has approved the caller of this function to spend a sufficient amount

		@param address _from: the address from which to send the funds
		@param address _to: the address to which to send the funds
		@param uint256 _value: the amount of sub units of coins to allow to be spent

		@return bool success: true if function executes sucessfully
    */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        return transferTokenOwnerFrom(_from, _to, _value, _from);
    }

    //-----------------i-m-p-l-e-m-e-n-t-s---y-i-e-l-d----------------
    mapping(address => mapping(address => uint256)) public yieldDistribution;
    mapping(address => uint) public totalYield;
    mapping(address => mapping(address => mapping(address => uint))) public specificAllowance;
    mapping(address => bool) public autoClaimYieldDisabled;
    /*
		@Description: Emitted when there is movement of _value in yeildDistribution from
			yeildDistribution[_tokenOwner][_yeildOwner] to
			yeildDistribution[_tokenOwner][_tokenOwner]
    */
    event ClaimYield(
    	address indexed _tokenOwner,
    	address indexed _yieldOwner,
    	uint256 _value
    );

    /*
		@Description: Emitted when there is movement of _value in yeildDistribution from
			yeildDistirbution[_tokenOwner][_tokenOwner] to
			yeildDistribution[_tokenOwner][_yeildOwner]
    */
    event SendYield(
    	address indexed _tokenOwner,
    	address indexed _yieldOwner,
    	uint256 _value
    );

    function claimYield(address _yieldOwner, uint256 _value) external returns (bool success) {
        claimYeildInternal(msg.sender, _yieldOwner, _value);

    	return true;
    }

    function sendYield(address _to, uint256 _value) public returns (bool success) {
    	require(yieldDistribution[msg.sender][msg.sender] >= _value);
        claimDividendInternal(msg.sender);
        claimDividendInternal(_to);
    	yieldDistribution[msg.sender][msg.sender] -= _value;
    	totalYield[msg.sender] -= _value;
    	yieldDistribution[msg.sender][_to] += _value;
    	totalYield[_to] += _value;
    	emit SendYield(msg.sender, _to, _value);

    	return true;
    }

    function transferTokenOwner(address _to, uint256 _value, address _yieldOwner) public returns (bool success) {
    	require(yieldDistribution[msg.sender][_yieldOwner] >= _value);
    	yieldDistribution[msg.sender][_yieldOwner] -= _value;
		balanceOf[msg.sender] -= _value;
		
		yieldDistribution[_to][_yieldOwner] += _value;
		balanceOf[_to] += _value;

        if (!autoClaimYieldDisabled[_to]) claimYeildInternal(_to, _yieldOwner, _value);

		emit Transfer(msg.sender, _to, _value, _yieldOwner);

		return true;
    }

    function approveYieldOwner(address _spender, uint256 _value, address _yieldOwner) public returns (bool success) {
    	allowance[msg.sender][_spender] -= specificAllowance[msg.sender][_spender][_yieldOwner];
    	specificAllowance[msg.sender][_spender][_yieldOwner] = _value;
    	allowance[msg.sender][_spender] += _value;

    	emit Approval(msg.sender, _spender, _value, _yieldOwner);

    	return true;
    }

    function transferTokenOwnerFrom(address _from, address _to, uint256 _value, address _yieldOwner) public returns (bool success) {
    	require(yieldDistribution[_from][_yieldOwner] >= _value);
    	require(specificAllowance[_from][msg.sender][_yieldOwner] >= _value);
    	yieldDistribution[_from][_yieldOwner] -= _value;
		balanceOf[_from] -= _value;

        specificAllowance[_from][msg.sender][_yieldOwner] -= _value;
		allowance[_from][msg.sender] -= _value;

		yieldDistribution[_to][_yieldOwner] += _value;
		balanceOf[_to] += _value;

        if (!autoClaimYieldDisabled[_to]) claimYeildInternal(_to, _yieldOwner, _value);

		emit Transfer(_from, _to, _value, _yieldOwner);

		return true;
    }

    function setAutoClaimYield() public {
        autoClaimYieldDisabled[msg.sender] = !autoClaimYieldDisabled[msg.sender];
    }

	/*
		@Description: allows token holders to claim their portion of the cashflow
	*/
	function claimDividend() public {
		claimDividendInternal(msg.sender);
	}

	//--------y-i-e-l-d---i-m-p-l-e-m-e-n-t-a-t-i-o-n---h-e-l-p-e-r-s-------------------
	/*
		@Description: Calls options.withdrawFunds() from this contract afterwards users may claim their own portion of the funds
			may be called once a day

		@return uint underlyingAsset: the amount of underlying asset that has been credited to this contract
		@return uint strikeAsset: the amount of strike asset that has  been credited to this contract
	*/
	function contractClaimDividend() public returns (uint underlyingAsset, uint strikeAsset) {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");
		lastWithdraw = block.timestamp;
		(underlyingAsset, strikeAsset) = optionsContract.withdrawFunds();
		contractBalanceUnderlying.push(contractBalanceUnderlying[contractBalanceUnderlying.length-1] + underlyingAsset);
		contractBalanceStrike.push(contractBalanceStrike[contractBalanceStrike.length-1] + strikeAsset);
		return (underlyingAsset, strikeAsset);
	}

	/*
		@Description: claims an address's portion of cashflow

		@param address _addr: the address for which to claim cashflow
	*/
	function claimDividendInternal(address _addr) internal {
		uint mostRecent = lastClaim[_addr];
		lastClaim[_addr] = contractBalanceUnderlying.length-1;
		uint totalIncreace = contractBalanceUnderlying[contractBalanceUnderlying.length-1] - contractBalanceUnderlying[mostRecent];
		balanceUnderlying[_addr] += totalIncreace * totalYield[_addr] / totalSupply;
		totalIncreace = contractBalanceStrike[contractBalanceStrike.length-1] - contractBalanceStrike[mostRecent];
		balanceStrike[_addr] += totalIncreace * totalYield[_addr] / totalSupply;
	}

    function claimYeildInternal(address _tokenOwner, address _yieldOwner, uint256 _value) internal {
        require(yieldDistribution[_tokenOwner][_yieldOwner] >= _value);
        claimDividendInternal(_tokenOwner);
        claimDividendInternal(_yieldOwner);
        yieldDistribution[_tokenOwner][_yieldOwner] -= _value;
        totalYield[_yieldOwner] -= _value;
        yieldDistribution[_tokenOwner][_tokenOwner] += _value;
        totalYield[_tokenOwner] += _value;
        emit ClaimYield(_tokenOwner, _yieldOwner, _value);
    }

    /*
		every time lastWithdraw is updated another value is pushed to contractBalanceUnderlying as contractBalanceStrike
		thus the length of contractBalanceUnderlying and contractBalanceStrike are always the same

		lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	*/
	//lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	mapping(address => uint) lastClaim;
	//holds the total amount of underlying asset that this contract has generated in fees
	uint[] public contractBalanceUnderlying;
	//holds the total amount of strike asset that this contract has genereated in fees
	uint[] public contractBalanceStrike;

	//each address's balance of claimed underlying asset funds that have yet to be withdrawn
	mapping(address => uint) balanceUnderlying;
	//allows users to see their value in the mapping balanceUnderlying
	function viewUnderlyingAssetBalance() public view returns (uint) {return balanceUnderlying[msg.sender];}
	//each address's balance of claimed strike asset funds that have yet to be withdrawn
	mapping(address => uint) balanceStrike;
	//allows users to see their value in the mapping balanceStrike	
	function viewStrikeAssetBalance() public view returns (uint) {return balanceStrike[msg.sender];}

}