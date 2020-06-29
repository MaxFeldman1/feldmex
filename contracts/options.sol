pragma solidity ^0.5.12;
import "./interfaces/ITimeSeriesOracle.sol";
import "./oracle.sol";
import "./interfaces/ERC20.sol";
import "./interfaces/Ownable.sol";

contract options is Ownable {
    //address of the contract of the price oracle for the underlying asset in terms of the strike asset such as a price oracle for WBTC/DAI
    address oracleAddress;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address public underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address public strikeAssetAddress;
    //address of the exchange is allowed to see collateral requirements for all users
    address exchangeAddress;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
    //previously recorded balances
    uint satReserves;
    uint scReserves;
    /*
        addresses that are approved do not have to pay fees
        addresses that are approved are usually market makers/liquidity providers
        addresses are approved by the owner
    */
    mapping(address => bool) public feeImmunity;
    /*
        number by which the oracle multiplies all spot prices
        also used to inflate strike prices here
    */
    uint public inflator;
    //fee == (pricePaid)/feeDenominator
    uint public feeDenominator = 2**255;
    //variable occasionally used for testing purposes should not be present in production
    //uint public testing;
    
    /*
        @Description: assigns the addesses of external contracts

        @param address _oracleAddress: address that shall be assigned to oracleAddress
        @param address _underlyingAssetAddress: address that shall be assigned to underlyingAssetAddress
        @param address _strikeAssetAddress: address that shall be assigned to strikeAssetAddress
    */
    constructor (address _oracleAddress, address _underlyingAssetAddress, address _strikeAssetAddress) public {
        oracleAddress = _oracleAddress;
        underlyingAssetAddress = _underlyingAssetAddress;
        strikeAssetAddress = _strikeAssetAddress;
        exchangeAddress = msg.sender;
        //ITimeSeriesOracle orc = ITimeSeriesOracle(oracleAddress);
        oracle orc = oracle(oracleAddress);
        inflator = orc.inflator();
        ERC20 ua = ERC20(underlyingAssetAddress);
        satUnits = 10 ** uint(ua.decimals());
        ERC20 sa = ERC20(strikeAssetAddress);
        scUnits = 10 ** uint(sa.decimals());
    }
    
    /*
        @Descripton: Sets the address of the smart contract that is trusted to see all users collateral requirements

        @param address _exchangeAddress: this is the address that will be assigned to this contracts exchangeAddress variable
    */
    function setExchangeAddress(address _exchangeAddress) onlyOwner public {
        require(exchangeAddress == owner);
        exchangeAddress = _exchangeAddress;
    }

    /*
        @Description: allows the deployer to set a new fee

        @param uint _feeDenominator: the value which will be the denominator in the fee on all transactions
            fee == (amount*priceOfOption)/feeDenominator
    */
    function setFee(uint _feeDeonominator) onlyOwner public {
        require(_feeDeonominator >= 500);
        feeDenominator = _feeDeonominator;
    }

    /*
        @Description: allows the owner of this contract to give and take approval from accounts that are providing liquidity
            If an address is already approved approval will be removed if not approval will be awarded

        @address _addr: the address to give or retract fee immunity from
    */
    function changeFeeStatus(address _addr) onlyOwner public {
        if (feeImmunity[_addr]) delete feeImmunity[_addr];
        else feeImmunity[_addr] = true;
    }

    /*
        @Description: transfers ownership of contract
            if exchangeAddress has not been set it is also set to _addr such that it is known that the exchange address has not been set when it == owner
    */
    function transferOwnership(address _newOwner) onlyOwner public {
        if (owner == exchangeAddress) exchangeAddress = _newOwner;
        super.transferOwnership(_newOwner);
    }

    /*
        callAmounts and putAmounts store the net position of each type of calls and puts respectively for each user at each matirity and strike
    */
    //address => maturity => strike => amount of calls
    mapping(address => mapping(uint => mapping(uint => int))) callAmounts;
    
    //address => maturity => strike => amount of puts
    mapping(address => mapping(uint => mapping(uint => int))) putAmounts;

    /*
        claimedTokens and claimedStable refers to the amount of the underlying and strike asset respectively that each user may withdraw
    */
    //denominated in satUnits
    mapping(address => uint) claimedTokens;
    //denominated in scUnits
    mapping(address => uint) claimedStable;

    /*
        satCollateral maps each user to the amount of collateral in the underlying that they have locked at each maturuty for calls
        scCollateral maps each user to the amount of collateral in strike asset that they have locked at each maturity for puts
    */
    //address => maturity => amount (denominated in satUnits)
    mapping(address => mapping(uint => uint)) satCollateral;
    //address => maturity => amount (denominated in scUnits)
    mapping(address => mapping(uint => uint)) scCollateral;


    /*
        strikes maps each user to the strikes that they have traded calls or puts on for each maturity
    */
    //address => maturity => array of strikes
    mapping(address => mapping(uint => uint[])) strikes;
    //address => maturity => strike => contained
    mapping(address => mapping(uint => mapping(uint => bool))) public containedStrikes;

    /*
        satDeduction is the amount of underlying asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for calls
        scDeduction is the amount of strike asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for puts
    */
    //address => maturity => amount of collateral not required //denominated in satUnits
    mapping(address => mapping(uint => uint)) satDeduction;
    //address => maturity => amount of collateral not required //denominated in scUnits
    mapping(address => mapping(uint => uint)) scDeduction;

    /*
        @Description: after the maturity holders of contracts to claim the value of the contracts and allows debtors to claim the unused collateral

        @pram uint _maturity: the maturity that the sender of this transaction is attempting to claim rewards from

        @return bool success: if an error occurs returns false if no error return true
    */
    function claim(uint _maturity) public returns(bool success){
        require(_maturity < block.timestamp);
        //get info from the oracle
        ITimeSeriesOracle orc = ITimeSeriesOracle(oracleAddress);
        //oracle orc = oracle(oracleAddress);
        uint spot = orc.fetchSpotAtTime(_maturity);
        uint callValue = 0;
        uint putValue = 0;
        //calls & puts
        for (uint i = strikes[msg.sender][_maturity].length-1; i != uint(-1); i--){
            uint strike = strikes[msg.sender][_maturity][i];
            int callAmount = callAmounts[msg.sender][_maturity][strike];
            int putAmount = putAmounts[msg.sender][_maturity][strike];
            delete callAmounts[msg.sender][_maturity][strike];
            delete putAmounts[msg.sender][_maturity][strike];
            callValue += satValueOf(callAmount, strike, spot);
            putValue += scValueOf(putAmount, strike, spot);
            delete containedStrikes[msg.sender][_maturity][strike];
        }
        //satValueOf is inflated by _price parameter and scValueOf thus only divide out spot from callValue not putValue
        callValue /= spot;
        delete strikes[msg.sender][_maturity];
        if (callValue > satDeduction[msg.sender][_maturity]){
            callValue -= satDeduction[msg.sender][_maturity];
            uint fee = feeImmunity[msg.sender] ? 0 : callValue/feeDenominator;
            claimedTokens[owner] += fee;
            claimedTokens[msg.sender] += callValue - fee;
        }
        if (putValue > scDeduction[msg.sender][_maturity]){
            putValue -= scDeduction[msg.sender][_maturity];
            uint fee = feeImmunity[msg.sender] ? 0 : putValue/feeDenominator;
            claimedStable[owner] += fee;
            claimedStable[msg.sender] += putValue - fee;
        }
        success = true;
    }

    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively

        @return uint underlyingAsset: the amount of the underlying asset that has been withdrawn
        @return uint strikeAsset: the amount of the strike asset that has been withdrawn
    */
    function withdrawFunds() public returns(uint underlyingAsset, uint strikeAsset){
        ERC20 ua = ERC20(underlyingAssetAddress);
        underlyingAsset = claimedTokens[msg.sender];
        claimedTokens[msg.sender] = 0;
        ua.transfer(msg.sender, underlyingAsset);
        ERC20 sa = ERC20(strikeAssetAddress);
        strikeAsset = claimedStable[msg.sender];
        claimedStable[msg.sender] = 0;
        sa.transfer(msg.sender, strikeAsset);
        satReserves -= underlyingAsset;
        scReserves -= strikeAsset;
    }

    /*
        @Description: allows for users to deposit funds that are not tided up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively
    */
    function depositFunds(address _to) public returns(bool success){
    	uint balance = ERC20(underlyingAssetAddress).balanceOf(address(this));
    	uint sats = balance - satReserves;
    	satReserves = balance;
    	balance = ERC20(strikeAssetAddress).balanceOf(address(this));
    	uint sc = balance - scReserves;
    	scReserves = balance;
    	claimedTokens[_to] += sats;
    	claimedStable[_to] += sc;
        success = true;
    }

    /*
        @Description: used to tell if strikes[givenAddress][givenMaturity] contains a given strike

        @param address _addr: the address is question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike price in question

        @return bool _contains: returns true if strike[_addr][_maturity] contains _strike otherwise returns false
    */
    function contains(address _addr, uint _maturity, uint _strike)public view returns(bool _contains){
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            if (strikes[_addr][_maturity][i] == _strike) return true;
        }
        _contains = false;
    }


    /*
        @Description: used to find the value of a given call postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the call contract in terms of the underlying versus stablecoie
        @param uint _price: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint value: the value of the position in terms of the underlying multiplied by the price
            inflate value by multiplying by price and divide out after doing calculations with the returned value to maintain accuracy
    */
    function satValueOf(int _amount, uint _strike, uint _price)internal view returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price > _strike){
                //inflator is canceld when it is divided by out
                //payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price * inflator - (_strike * inflator))/inflator;
                //payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - _strike) * inflator/inflator;
                payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - _strike);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*satUnits*_price - payout;
            }
        } 
        value = 0;
    }

    /*
        @Description: used to find the value of a given put postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the put contract in terms of the underlying versus stablecoie
        @param uint _prive: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint value: the value of the position in terms of the strike asset
    */
    function scValueOf(int _amount, uint _strike, uint _price)internal pure returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price < _strike){
                //inflator must be divided out thus remove *scUnits
                payout = (_strike - _price)*uint(_amount > 0 ? _amount : -_amount);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                //inflator must be divided out thus remove *scUnits
                return uint(-_amount)*_strike - payout;
            }
        }
        value = 0;
    }

    /*
        @Description: used to find the minimum amount of collateral that is required to to support call positions for a certain user at a given maturity
            also takes into account an extra position that is entered in the last two parameters
            The purpose of adding having the extra position in the last two parameters is that it allows for 

        @param address _addr: address in question
        @param uint _maturity: maturity in question
        @param int _amount: the amount of the added position
        @param uint _strike: the strike price of the added position

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in the underlying
        @return uint: sum of all short call positions multiplied by satUnits
    */
    function minSats(address _addr, uint _maturity) internal view returns (uint minCollateral, uint liabilities) {
        uint _satUnits = satUnits; //gas savings
        int delta = 0;
        int value = 0;
        int cumulativeStrike;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            int strike = int(strikes[_addr][_maturity][i]);
            int amt = callAmounts[_addr][_maturity][uint(strike)];
            /*
                value = satUnits * sigma((delta*strike-cumulativeStrike)/strike)
            */
            int numerator = int(satUnits) * (delta*strike-cumulativeStrike);
            value = numerator/strike;
            cumulativeStrike += amt*int(strike);
            delta += amt;
            if (value < 0 && uint(-value) >= minCollateral) {
                if (numerator%strike != 0) value--;
                minCollateral = uint(-value);
            }
            if (amt < 0) liabilities+=uint(-amt);
        }
        //value at inf
        value = int(_satUnits)*delta;
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
        liabilities *= _satUnits;
    }

    /*
        @Description: used to find the minimum amount of collateral that is required to to support put positions for a certain user at a given maturity
            also takes into account an extra position that is entered in the last two parameters

        @param address _addr: address in question
        @param uint _maturity: maturity in question
        @param int _amount: the amount of the added position
        @param uint _strike: the strike price of the added position

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in strike asset
        @return uint: negative value denominated in scUnits of all short put postions at a spot price of 0
    */
    function minSc(address _addr, uint _maturity) internal view returns(uint minCollateral, uint liabilities){
        int delta = 0;
        int value = 0;
        uint prevStrike;
        uint lastIndex = strikes[_addr][_maturity].length-1;
        for(uint i = lastIndex; i != uint(-1); i--) {
            uint strike = strikes[_addr][_maturity][i];
            int amt = putAmounts[_addr][_maturity][strike];
            value += delta * int(prevStrike-strike);
            delta += amt;
            prevStrike = strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (amt < 0) liabilities+=uint(-amt)*strike;
        }
        //value at 0
        value += delta * int(prevStrike);
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
    }


    /*
        @Description: The function was created for positions at a strike to be inclueded in calculation of collateral requirements for a user
            User calls this instead of smart contract adding strikes automatically when funds are transfered to an address by the transfer or transferFrom functions
            because it prevents a malicious actor from overloading a user with many different strikes thus making it impossible to claim funds because of the gas limit
            strikes array is sorted from smallest to largest

        @param uint _maturity: this is the maturity at which the strike will be added if it is not already recorded at this maturity
        @param uint _strike: this is the strike that will be added.
        @param uint _index: the index at which to insert the strike
    */
    function addStrike(uint _maturity, uint _strike, uint _index) public {
        require(_maturity > 0 && _strike > 0);
        uint size = strikes[msg.sender][_maturity].length;
        require(_index <= size);
        if (_index > 0) require(_strike > strikes[msg.sender][_maturity][_index-1]);
        if (_index < size) require(_strike < strikes[msg.sender][_maturity][_index]);
        strikes[msg.sender][_maturity].push(_strike);
        for (uint i = size-1; i >= _index && i != uint(-1); i--)
            strikes[msg.sender][_maturity][i+1] = strikes[msg.sender][_maturity][i];
        strikes[msg.sender][_maturity][_index] = _strike;
        containedStrikes[msg.sender][_maturity][_strike] = true;
    }


    /*
        @Description: view function for both callAmounts and putAmounts
    */
    function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) public view returns(int256 balance){
        balance = _call ? callAmounts[_owner][_maturity][_strike] : putAmounts[_owner][_maturity][_strike];
    }

    //store positions in call/putAmounts[helperAddress][helperMaturity] to allow us to calculate collateral requirements
    //make helper maturities extremely far out, Dec 4th, 292277026596 A.D
    uint helperMaturity = 10**20;
    address helperAddress = address(0);

    /*
        @Description: add a strike to strikes[helperAddress][helperMaturity] and an amount to either callAmounts or putAmounts

        @param uint _strike: the strike of the position in question
        @param int _amount: the amount of the position in question
        @param bool _call: true if the position is for calls false if it is for puts
    */
    function addPosition(uint _strike, int _amount, bool _call) public {
        require(_strike > 0);
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint size = strikes[_helperAddress][_helperMaturity].length;
        if (size > 0) require(_strike > strikes[_helperAddress][_helperMaturity][size-1]);
        strikes[_helperAddress][_helperMaturity].push(_strike);
        if (_call)
            callAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
        else
            putAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
    }

    /*
        @Description: deletes strikes[helperAddress][helperMaturity]
    */
    function clearPositions() public {
        delete strikes[helperAddress][helperMaturity];
    }

    /*
        @Description: multiplies all call/put Amounts by -1

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function inversePosition(bool _call) public {
        address _helperAddress = helperAddress;
        uint _helperMaturity = helperMaturity;
        uint size = strikes[_helperAddress][_helperMaturity].length;
        if (_call){
            for (uint i = 0; i < size; i++)
                callAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;
        } else {
            for (uint i = 0; i < size; i++)
                putAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;
        }
    }

    /*
        @Description:finds the maximum amount of collateral needed to take on a position

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function transferAmount(bool _call) public returns (uint _debtorTransfer, uint _holderTransfer) {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity;  //gas savings
        (_holderTransfer, ) = _call ? minSats(_helperAddress, _helperMaturity) : minSc(_helperAddress, _helperMaturity);
        inversePosition(_call);
        (_debtorTransfer, ) = _call ? minSats(_helperAddress, _helperMaturity) : minSc(_helperAddress, _helperMaturity);
    }

    /*
        @Description: combine position stored at helperAddress at helperMaturity with another address at a specified maturity

        @param address _addr: the address of the account for which to combine the position stored at helperAddress at helperMaturity
        @param uint _maturity: the maturity for which to combine the position stored at helperAddress at helperMaturity
        @param bool _call: true if the position is for calls false if it is for puts        
    */
    function combinePosition(address _addr, uint _maturity, bool _call) internal {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint size1 = strikes[_addr][_maturity].length;
        uint size2 = strikes[_helperAddress][_helperMaturity].length;
        uint counter1; //counter for strikes[_addr][_maturity]
        uint counter2; //counter for strikes[_helperAddress][_helperMaturity]
        for (; counter2 < size2; counter1++) {
            //positions at unadded strikes may only be of positive amount
            if (counter1 == size1 || strikes[_addr][_maturity][counter1] > strikes[_helperAddress][_helperMaturity][counter2]){
                uint strike = strikes[_helperAddress][_helperMaturity][counter2];
                int amount = _call ? callAmounts[_helperAddress][_helperMaturity][strike] : putAmounts[_helperAddress][_helperMaturity][strike];
                assert(amount > 0);
                if (_call)
                    callAmounts[_addr][_maturity][strike] += amount;
                else
                    putAmounts[_addr][_maturity][strike] += amount;
                counter2++;
                counter1--;
            }
            else if (strikes[_addr][_maturity][counter1] == strikes[_helperAddress][_helperMaturity][counter2]) {
                uint strike = strikes[_helperAddress][_helperMaturity][counter2];
                if (_call)
                    callAmounts[_addr][_maturity][strike] += callAmounts[_helperAddress][_helperMaturity][strike];
                else
                    putAmounts[_addr][_maturity][strike] += putAmounts[_helperAddress][_helperMaturity][strike];
                counter2++;
            }
        }
    }

    /*
        when true funds are taken from claimedToken and claimedSc reserves to meet collateral requirements
        when false funds are transfered from the address to this contract to meet collateral requirements
    */
    mapping(address => bool) public useDeposits;
    function setUseDeposits(bool _set) public {useDeposits[msg.sender] = _set;}

    /*
        store most recent transfer amounts
    */
    uint public transferAmountDebtor;
    uint public transferAmountHolder;

    /*
        @Description: assign the call position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address

        @param address _debtor: the address that will gain the opposite payoff profile of the position stored at helperAddress at helperMaturity
        @param address _holder: the address that will gain the payoff profile of the position stored at helperAddress at helperMaturity
        @param uint _maturity: the timestamp at which the calls may be exercised
    */
    function assignCallPosition() public returns (uint transferAmtDebtor, uint transferAmtHolder) {
        address _debtor = debtor;   //gas savings
        address _holder = holder;   //gas savings
        uint _maturity = maturity; //gas savings
        combinePosition(_holder, _maturity, true);
        (uint minCollateral, uint liabilities) = minSats(_holder, _maturity);

        if (minCollateral > satCollateral[_holder][_maturity]){
            transferAmtHolder = minCollateral - satCollateral[_holder][_maturity];
            assert(transferAmtHolder <= maxHolderTransfer);
        }
        else 
            claimedTokens[_holder] += satCollateral[_holder][_maturity] - minCollateral;
        satCollateral[_holder][_maturity] = minCollateral;
        satDeduction[_holder][_maturity] = liabilities - minCollateral;
        
        inversePosition(true);

        combinePosition(_debtor, _maturity, true);        
        (minCollateral, liabilities) = minSats(_debtor, _maturity);

        if (minCollateral > satCollateral[_debtor][_maturity]){
            transferAmtDebtor = minCollateral - satCollateral[_debtor][_maturity];
            assert(transferAmtDebtor <= maxDebtorTransfer);
        }
        else
            claimedTokens[_debtor] += satCollateral[_debtor][_maturity] - minCollateral;
        satCollateral[_debtor][_maturity] = minCollateral;
        satDeduction[_debtor][_maturity] = liabilities - minCollateral;
        if (useDeposits[msg.sender]){
            assert(claimedTokens[msg.sender] >= transferAmtHolder+transferAmtDebtor);
            claimedTokens[msg.sender] -= transferAmtHolder+transferAmtDebtor;
        }
        else{
            ERC20(underlyingAssetAddress).transferFrom(msg.sender, address(this), transferAmtHolder+transferAmtDebtor);
            satReserves += transferAmtHolder+transferAmtDebtor;
        }
        transferAmountDebtor = transferAmtDebtor;
        transferAmountHolder = transferAmtHolder;
    }


    /*
        @Description: assign the put position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address

        @param address _debtor: the address that will gain the opposite payoff profile of the position stored at helperAddress at helperMaturity
        @param address _holder: the address that will gain the payoff profile of the position stored at helperAddress at helperMaturity
        @param uint _maturity: the timestamp at which the puts may be exercised
    */
    function assignPutPosition() public returns (uint transferAmtDebtor, uint transferAmtHolder) {
        address _debtor = debtor;   //gas savings
        address _holder = holder;   //gas savings
        uint _maturity = maturity; //gas savings
        combinePosition(_holder, _maturity, false);
        (uint minCollateral, uint liabilities) = minSc(_holder, _maturity);
        
        if (minCollateral > scCollateral[_holder][_maturity]){
            transferAmtHolder = minCollateral - scCollateral[_holder][_maturity];
            assert(transferAmtHolder <= maxHolderTransfer);
        }
        else
            claimedStable[_holder] += scCollateral[_holder][_maturity] - minCollateral;
        scCollateral[_holder][_maturity] = minCollateral;
        scDeduction[_holder][_maturity] = liabilities - minCollateral;

        //inverse positions for debtor
        inversePosition(false);

        combinePosition(_debtor, _maturity, false);        
        (minCollateral, liabilities) = minSc(_debtor, _maturity);

        if (minCollateral > scCollateral[_debtor][_maturity]){
            transferAmtDebtor = minCollateral - scCollateral[_debtor][_maturity];
            assert(transferAmtDebtor <= maxDebtorTransfer);
        }
        else
            claimedStable[_debtor] += scCollateral[_debtor][_maturity] - minCollateral;
        scCollateral[_debtor][_maturity] = minCollateral;
        scDeduction[_debtor][_maturity] = liabilities - minCollateral;
        if (useDeposits[msg.sender]){
            assert(claimedStable[msg.sender] >= transferAmtHolder+transferAmtDebtor);
            claimedStable[msg.sender] -= transferAmtHolder+transferAmtDebtor;
        }
        else {
            ERC20(strikeAssetAddress).transferFrom(msg.sender, address(this), transferAmtHolder+transferAmtDebtor);
            scReserves += transferAmtHolder+transferAmtDebtor;
        }
        transferAmountDebtor = transferAmtDebtor;
        transferAmountHolder = transferAmtHolder;
    }

    //allow external contracts to use .call to mint ositions
    address debtor;
    address holder;
    uint maturity;
    uint maxDebtorTransfer;
    uint maxHolderTransfer;

    /*
        @Description: set the values of debtor, holder, and maturity before calling assignCallPosition or assignPutPosition

        @param address _debtor: the address that will gain the opposite payoff profile of the position stored at helperAddress at helperMaturity
        @param address _holder: the address that will gain the payoff profile of the position stored at helperAddress at helperMaturity
        @param uint _maturity: the timestamp at which the puts may be exercised 
    */
    function setParams(address _debtor, address _holder, uint _maturity) public {
        debtor = _debtor;
        holder = _holder;
        maturity = _maturity;
    }

    /*
        @Description: set the maximum values for the transfer amounts

        @param uint _maxDebtorTransfer: the maximum amount for transferAmountDebtor if this limit is breached assignPosition transactions will revert
        @param uint _maxHolderTransfer: the maximum amount for transferAmountHolder if this limit is breached assignPosition transactions will revert
    */
    function setLimits(uint _maxDebtorTransfer, uint _maxHolderTransfer) public {
        maxDebtorTransfer = _maxDebtorTransfer;
        maxHolderTransfer = _maxHolderTransfer;
    }

    //---------------------view functions---------------
    function viewClaimedTokens() public view returns(uint){return claimedTokens[msg.sender];}

    function viewClaimedStable() public view returns(uint){return claimedStable[msg.sender];}

    function viewSatCollateral(uint _maturity) public view returns(uint){return satCollateral[msg.sender][_maturity];}

    function viewScCollateral(uint _maturity) public view returns(uint){return scCollateral[msg.sender][_maturity];}

    function viewStrikes(uint _maturity) public view returns(uint[] memory){return strikes[msg.sender][_maturity];}

    function viewSatDeduction(uint _maturity) public view returns(uint){return satDeduction[msg.sender][_maturity];}

    function viewScDeduction(uint _maturity) public view returns(uint){return scDeduction[msg.sender][_maturity];}
    //---------------------end view functions-----------
}