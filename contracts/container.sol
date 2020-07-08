pragma solidity ^0.5.12;
import "./interfaces/ERC20.sol";
import "./oracle.sol";
import "./options.sol";
import "./exchange.sol";
import "./helpers/oHelper.sol";
import "./helpers/eHelper.sol";
import "./helpers/orcHelper.sol";
import "./interfaces/ITimeSeriesOracle.sol";
import "./interfaces/Ownable.sol";
import "./interfaces/yieldEnabled.sol";

contract container is ERC20, Ownable, yieldEnabled {
	
	//smart contract that records prices, records (reservesOfAsset1)/(reservesOfAsset2)
	ITimeSeriesOracle public oracleContract;
	//smart contract that handles settlement of calls and puts
	options public optionsContract;
	//smart contract on which options may be traded
	exchange public exchangeContract;
	//options contract for inverse trading pair
	options public optionsContract2;
	//exchange contract for inverse trading pair
	exchange public exchangeContract2;
	//smart contract of the asset in the numerator of oracle price
	ERC20 public Asset1Contract;
	//smart contract of the asset in the denominator of oracle price
	ERC20 public Asset2Contract;
    //address of the FeldmexERC20Helper contract that is responsible for providing ERC20 interfaces for options
    address feldmexERC20HelperAddress;

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
	uint public totalSupply = 10 ** uint(10);
	//10 ** decimals == the amount of sub units in a whole coin
	uint8 public decimals = 4;
	//each user's balance of coins
	mapping(address => uint) public balanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) public allowance;

	//---------------contract setup-----------------
	/*
		@Description: Assigns inital values and credits the owner of this contract with all coins

		@param address _asset1Address: the address of the ERC0 contract of asset1
		@param address _asset2Address: the address of the ERC20 contract of asset2
		@param address _oHelperAddress: the address of the oHelper contract that helps with deployment of the options contract
		@param address _eHelperAddress: the address of the eHelper contract that helps with deployment of the exchange contract
	*/
	constructor (address _asset1Address, address _asset2Address, address _oHelperAddress, address _eHelperAddress, address _orcHelperAddress) public {
		balanceOf[owner] = totalSupply;
		yieldDistribution[msg.sender][msg.sender] = totalSupply;
		totalYield[msg.sender] = totalSupply;
		Asset1Contract = ERC20(_asset1Address);
		Asset2Contract = ERC20(_asset2Address);
		address _oracleAddress = orcHelper(_orcHelperAddress).oracleAddresses(_asset1Address, _asset2Address);
		if (_oracleAddress == address(0)) {
			(bool success, ) = _orcHelperAddress.call(abi.encodeWithSignature("deploy(address,address)", _asset1Address, _asset2Address));
			assert(success);
			_oracleAddress = orcHelper(_orcHelperAddress).oracleAddresses(_asset1Address, _asset2Address);
		}
		oracleContract = ITimeSeriesOracle(_oracleAddress);
		oHelperAddress = _oHelperAddress;
		eHelperAddress = _eHelperAddress;
		contractBalanceAsset1.push(0);
		contractBalanceAsset2.push(0);
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

	//----------------end contract setup------------

    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for asset1 and asset2 respectively

        @return uint asset1: the amount of asset1 that has been withdrawn
        @return uint asset2: the amount of asset2 that has been withdrawn
    */
    function withdrawFunds() public returns(uint asset1, uint asset2){
        asset1 = balanceAsset1[msg.sender];
        balanceAsset1[msg.sender] = 0;
        Asset1Contract.transfer(msg.sender, asset1);
        asset2 = balanceAsset2[msg.sender];
        balanceAsset2[msg.sender] = 0;
        Asset2Contract.transfer(msg.sender, asset2);
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
        success = transferTokenOwner(_to, _value, msg.sender);
    }

    /*
		@Description: approve another address to spend coins on the function caller's behalf

		@param address _spender: the address to approve
		@param uint256 _value: the amount of sub units of coins to allow to be spent

		@return bool success: true if function executes sucessfully
    */
    function approve(address _spender, uint256 _value) public returns (bool success) {
        success = approveYieldOwner(_spender, _value, msg.sender);
    }


    /*
		@Description: transfer funds from one address to another given that the from address has approved the caller of this function to spend a sufficient amount

		@param address _from: the address from which to send the funds
		@param address _to: the address to which to send the funds
		@param uint256 _value: the amount of sub units of coins to allow to be spent

		@return bool success: true if function executes sucessfully
    */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        success = transferTokenOwnerFrom(_from, _to, _value, _from);
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
    	success = true;
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
    	success = true;
    }

    function transferTokenOwner(address _to, uint256 _value, address _yieldOwner) public returns (bool success) {
    	require(yieldDistribution[msg.sender][_yieldOwner] >= _value);
    	yieldDistribution[msg.sender][_yieldOwner] -= _value;
		balanceOf[msg.sender] -= _value;
		
		yieldDistribution[_to][_yieldOwner] += _value;
		balanceOf[_to] += _value;

        if (!autoClaimYieldDisabled[_to]) claimYeildInternal(_to, _yieldOwner, _value);

		emit Transfer(msg.sender, _to, _value, _yieldOwner);

		success = true;
    }

    function approveYieldOwner(address _spender, uint256 _value, address _yieldOwner) public returns (bool success) {
    	allowance[msg.sender][_spender] -= specificAllowance[msg.sender][_spender][_yieldOwner];
    	specificAllowance[msg.sender][_spender][_yieldOwner] = _value;
    	allowance[msg.sender][_spender] += _value;

    	emit Approval(msg.sender, _spender, _value, _yieldOwner);

    	success = true;
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

		success = true;
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

		@return uint asset1: the amount of asset1 that has been credited to this contract
		@return uint asset2: the amount of asset2 that has been credited to this contract
	*/
	function contractClaimDividend() public returns (uint asset1, uint asset2) {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");
		uint8 _progress = progress; //gas savings
		require(_progress > 0, "optionsContract must be initialized before this function may be called");
		lastWithdraw = block.timestamp;
		(asset1, asset2) = optionsContract.withdrawFunds();
		uint temp1;
		uint temp2;
		if (progress > 2) (temp1, temp2) = optionsContract2.withdrawFunds();
		//reverse order of assets
		asset1+=temp2;
		asset2+=temp1;
		contractBalanceAsset1.push(contractBalanceAsset1[contractBalanceAsset1.length-1] + asset1);
		contractBalanceAsset2.push(contractBalanceAsset2[contractBalanceAsset2.length-1] + asset2);
	}

	/*
		@Description: claims an address's portion of cashflow

		@param address _addr: the address for which to claim cashflow
	*/
	function claimDividendInternal(address _addr) internal {
		uint mostRecent = lastClaim[_addr];
		uint lastIndex = contractBalanceAsset1.length-1;	//gas savings
		uint _totalSupply = totalSupply;	//gas savings
		uint _totalYield = totalYield[_addr];	//gas savings
		lastClaim[_addr] = lastIndex;
		uint totalIncreace = contractBalanceAsset1[lastIndex] - contractBalanceAsset1[mostRecent];
		balanceAsset1[_addr] += totalIncreace * _totalYield / _totalSupply;
		totalIncreace = contractBalanceAsset2[lastIndex] - contractBalanceAsset2[mostRecent];
		balanceAsset2[_addr] += totalIncreace * _totalYield / _totalSupply;
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
		every time lastWithdraw is updated another value is pushed to contractBalanceAsset1 as contractBalanceAsset2
		thus the length of contractBalanceAsset1 and contractBalanceAsset2 are always the same

		lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	*/
	//lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	mapping(address => uint) lastClaim;
	//holds the total amount of asset1 that this contract has generated in fees
	uint[] public contractBalanceAsset1;
	//holds the total amount of asset2 that this contract has genereated in fees
	uint[] public contractBalanceAsset2;
	//length of contractBalance arrays
	function length() public view returns (uint len) {len = contractBalanceAsset1.length;}
	//each address's balance of claimed asset1 funds that have yet to be withdrawn
	mapping(address => uint) balanceAsset1;
	//allows users to see their value in the mapping balanceAsset1
	function viewAsset1Balance() public view returns (uint ret) {ret = balanceAsset1[msg.sender];}
	//each address's balance of claimed asset2 funds that have yet to be withdrawn
	mapping(address => uint) balanceAsset2;
	//allows users to see their value in the mapping balanceAsset2	
	function viewAsset2Balance() public view returns (uint ret) {ret = balanceAsset2[msg.sender];}

}