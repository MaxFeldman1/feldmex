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

    /*
        satDeduction is the amount of underlying asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for calls
        scDeduction is the amount of strike asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for puts
    */
    //address => maturity => amount of collateral not required //denominated in satUnits
    mapping(address => mapping(uint => uint)) satDeduction;
    //address => maturity => amount of collateral not required //denominated in scUnits
    mapping(address => mapping(uint => uint)) scDeduction;

    /*
        @Description: handles the logistics of creating a long call position for the holder and short call position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address _debtor: the address that collateral posted here will be associated with and the for which the call will be considered a liability
        @param address _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the call contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the strike asset at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of calls that the debtor is adding as short and the holder is adding as long
        @param uint _maxTransfer: the maximum amount of collateral that this function can take on behalf of the debtor from the message sender denominated in satUnits
            if this limit needs to be broken to mint the call the transaction will return (true, 0)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmt: returns the amount of the underlying that was transfered from the message sender to act as collateral for the debtor
    */
    function mintCall(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(uint transferAmt){
        if (_debtor == _holder) return 0;
        clearPositions();
        addPosition(_strike, int(_amount), 0, true);
        useDeposits[msg.sender] = false;
        //setUseDeposits(false);
        (transferAmt, ) = assignCallPosition(_debtor, _holder, _maturity);
        assert(transferAmt <= _maxTransfer);
    }


    /*
        @Description: handles the logistics of creating a long put position for the holder and short put position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address _debtor: the address that collateral posted here will be associated with and the for which the put will be considered a liability
        @param address _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the put contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the strike asset at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of puts that the debtor is adding as short and the holder is adding as long
        @param uint _maxTransfer: the maximum amount of collateral that this function can take on behalf of the debtor from the message sender denominated in scUnits
            if this limit needs to be broken to mint the put the transaction will return (false, 0)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmt: returns the amount of strike asset that was transfered from the message sender to act as collateral for the debtor
    */
    function mintPut(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(uint transferAmt){
        if (_debtor == _holder) return 0;
        clearPositions();
        addPosition(_strike, int(_amount), 0, false);
        useDeposits[msg.sender] = false;
        //setUseDeposits(false);
        (transferAmt, ) = assignPutPosition(_debtor, _holder, _maturity);
        assert(transferAmt <= _maxTransfer);
    }
    
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
        for (uint i = 0; i < strikes[msg.sender][_maturity].length; i++){
            uint strike = strikes[msg.sender][_maturity][i];
            int callAmount = callAmounts[msg.sender][_maturity][strike];
            int putAmount = putAmounts[msg.sender][_maturity][strike];
            callAmounts[msg.sender][_maturity][strike] = 0;
            putAmounts[msg.sender][_maturity][strike] = 0;
            callValue += satValueOf(callAmount, strike, spot);
            putValue += scValueOf(putAmount, strike, spot);
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
    }

    /*
        @Description: allows for users to deposit funds that are not tided up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively
    */
    function depositFunds(uint _sats, uint _sc) public returns(bool success){
        if (_sats > 0){
            ERC20 ua = ERC20(underlyingAssetAddress);
            require(ua.transferFrom(msg.sender, address(this), _sats));
            claimedTokens[msg.sender] += _sats;
        }
        if (_sc > 0){
            ERC20 sa = ERC20(strikeAssetAddress);
            require(sa.transferFrom(msg.sender, address(this), _sc));
            claimedStable[msg.sender] += _sc;
        }
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
    function minSats(address _addr, uint _maturity, int _amount, uint _strike) internal view returns (uint minCollateral, uint liabilities) {
        uint _satUnits = satUnits; //gas savings
        int delta = 0;
        int value = 0;
        uint prevStrike;
        bool hit = false;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            uint strike = strikes[_addr][_maturity][i];
            int amt = callAmounts[_addr][_maturity][strike];
            if (!hit && _strike <= strike) {
                if (_strike < strike){
                    strike = _strike;
                    amt = _amount;
                    i--;
                } else
                    amt += _amount;
                hit = true;
            }
            //placeHolder for numerator 
            prevStrike = uint(delta * int(_satUnits * (strike-prevStrike)));
            value += int(prevStrike) / int(strike);
            //in solidity integer division rounds up when result is negative, counteract this
            if (delta < 0 && uint(-int(prevStrike))%strike != 0) value--;
            delta += amt;
            prevStrike = strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (amt < 0) liabilities+=uint(-amt);
        }
        if (!hit) {
            prevStrike = uint(delta * int(_satUnits * (_strike-prevStrike)));
            value += int(prevStrike) / int(_strike);
            //in solidity integer division rounds up when result is negative, counteract this
            if (delta < 0 && uint(-int(prevStrike))%_strike != 0) value--;
            delta += _amount;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (_amount < 0) liabilities+=uint(-_amount);
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
    function minSc(address _addr, uint _maturity, int _amount, uint _strike) internal view returns(uint minCollateral, uint liabilities){
        int delta = 0;
        int value = 0;
        uint prevStrike;
        bool hit = false;
        uint lastIndex = strikes[_addr][_maturity].length-1;
        for(uint i = lastIndex; i != uint(-1); i--) {
            uint strike = strikes[_addr][_maturity][i];
            int amt = putAmounts[_addr][_maturity][strike];
            if (!hit && _strike >= strike) {
                if (_strike > strike){
                    strike = _strike;
                    amt = _amount;
                    i++;                    
                } else
                    amt += _amount;
                hit = true;
            }
            value += delta * int(prevStrike-strike);
            delta += amt;
            prevStrike = strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (amt < 0) liabilities+=uint(-amt)*strike;
        }
        if (!hit) {
            value += delta * int(prevStrike-_strike);
            delta += _amount;
            prevStrike = _strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (_amount < 0) liabilities+=uint(-_amount)*_strike;
        }
        //value at 0
        value += delta * int(prevStrike);
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
    }


    /*
        @Description: used to find the amount by which a user's account would need to be funded for a user to make an order

        @param bool _call: true if inquiry regards calls false if pretaining to puts
        @param address _addr: the user in question
        @param uint _maturity: the maturity timestamp in question
        @param int _amount: the amount of calls or puts in the order, positive amount means buy, negative amount means sell
        @param uint _strike: the strike price in question

        @return uint: the amount of satUnits or scUnits that must be sent as collateral for the order described to go through
    */
    function transferAmount(bool _call, address _addr, uint _maturity, int _amount, uint _strike) public view returns (uint value){
        require(msg.sender == _addr || msg.sender == exchangeAddress);
        if (_amount >= 0) return 0;
        if (_call){
            (uint minCollateral, ) = minSats(_addr, _maturity, _amount, _strike);
            value = minCollateral-satCollateral[_addr][_maturity];
        }
        else {
            (uint minCollateral, ) = minSc(_addr, _maturity, _amount, _strike);
            value = minCollateral-scCollateral[_addr][_maturity];
        }
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
    }


    /*
        @Description: used to tell if strikes[givenAddress][givenMaturiy] contains a given strike

        @param address _addr: the address in question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike in question
        @param bool _push: if the strike is not contained then it will be added to strikes
        @param bool _remove: if the strike is contained then it will be removed

        @return bool: returns true if _maturity is contained in maturities
        @return uint: if bool returns true this is set to the index at which the maturitiy is contained
    */
    function containsStrike(address _addr, uint _maturity, uint _strike, bool _push, bool _remove) internal returns(bool contained, uint index){
        uint length = strikes[_addr][_maturity].length; //gas savings
        for (index = 0; index < length; index++){
            if (strikes[_addr][_maturity][index] == _strike){
                if (_remove){
                    uint temp = strikes[_addr][_maturity][length-1];
                    strikes[_addr][_maturity][index] = temp;
                    delete strikes[_addr][_maturity][length-1];
                }
                return (true, index);
            }
        }
        if (_push) strikes[_addr][_maturity].push(_strike);
        index = 0;
    }


    //------------------------------------------------------------------------------------E-R-C---2-0---I-m-p-l-e-m-e-n-t-a-t-i-o-n---------------------------
    
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value,
        uint256 _maturity,
        uint256 _strike,
        bool _call
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value,
        uint256 _maturity,
        uint256 _strike,
        bool _call
    );

    //approver => spender => maturity => strike => amount of calls
    mapping(address => mapping(address => mapping(uint => mapping(uint => uint)))) callAllowance;
    
    //approver => spender => strike => amount of puts
    mapping(address => mapping(address => mapping(uint => mapping(uint => uint)))) putAllowance;

    function transfer(address _to, uint256 _value, uint _maturity, uint _strike, uint _maxTransfer, bool _call) public returns(uint transferAmt){
        clearPositions();
        addPosition(_strike, int(_value), 0, _call);
        useDeposits[msg.sender] = true;
        if (_call)
            (transferAmt, ) = assignCallPosition(msg.sender, _to, _maturity);
        else
            (transferAmt, ) = assignPutPosition(msg.sender, _to, _maturity); 
        assert(transferAmt <= _maxTransfer);
        emit Transfer(msg.sender, _to, _value, _maturity, _strike, _call);
    }

    function approve(address _spender, uint256 _value, uint _maturity, uint _strike, bool _call) public returns(bool success){
        require(_strike != 0, "ensure strike != 0");
        emit Approval(msg.sender, _spender, _value, _maturity, _strike, _call);
        if (_call) callAllowance[msg.sender][_spender][_maturity][_strike] = _value;
        else putAllowance[msg.sender][_spender][_maturity][_strike] = _value;
        success = true;
    }

    function transferFrom(address _from, address _to, uint256 _value, uint _maturity, uint _strike, uint _maxTransfer, bool _call) public returns(uint transferAmt){
        require(_value <= (_call ? callAllowance[_from][msg.sender][_maturity][_strike]: putAllowance[_from][msg.sender][_maturity][_strike]));
        clearPositions();
        addPosition(_strike, int(_value), 0, _call);
        useDeposits[msg.sender] = true;
        if (_call) {
            callAllowance[_from][msg.sender][_maturity][_strike] -= _value;
            (transferAmt, ) = assignCallPosition(_from, _to, _maturity);
        }
        else {
            putAllowance[_from][msg.sender][_maturity][_strike] -= _value;
            (transferAmt, ) = assignPutPosition(_from, _to, _maturity);
        }
        assert(transferAmt <= _maxTransfer);
        emit Transfer(_from, _to, _value, _maturity, _strike, _call);
    }

    function allowance(address _owner, address _spender, uint _maturity, uint _strike, bool _call) public view returns(uint256 remaining){
        remaining = _call ? callAllowance[_owner][_spender][_maturity][_strike] : putAllowance[_owner][_spender][_maturity][_strike];
    }

    function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) public view returns(int256 balance){
        balance = _call ? callAmounts[_owner][_maturity][_strike] : putAmounts[_owner][_maturity][_strike];
    }

    //---------------------allow for complex positions to have limit orders-----------------
    //store positions in call/putAmounts[helperAddress][helperMaturity] to allow us to calculate collateral requirements

    //make helper maturities extremely far out, Dec 4th, 292277026596 A.D
    /*
        first helper maturity is where positions are added
        second helper maturity is where positions are combined with user positions to calculate collateral requirements
    */
    uint helperMaturity = 10**20;
    uint helperMaturity2 = 10**20 + 1;

    address helperAddress = address(0);

    function addPosition(uint _strike, int _amount, uint8 _index, bool _call) public {
        require(_strike > 0);
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint size = strikes[_helperAddress][_helperMaturity].length;
        require(_index <= size);
        if (_index > 0) require(_strike > strikes[_helperAddress][_helperMaturity][_index-1]);
        if (_index < size) require(_strike < strikes[_helperAddress][_helperMaturity][_index]);
        strikes[_helperAddress][_helperMaturity].push(_strike);
        for (uint i = size-1; i >= _index && i != uint(-1); i--)
            strikes[_helperAddress][_helperMaturity][i+1] = strikes[_helperAddress][_helperMaturity][i];
        strikes[_helperAddress][_helperMaturity][_index] = _strike;
        if (_call)
            callAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
        else
            putAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
    }

    function clearPositions() public {
        delete strikes[helperAddress][helperMaturity];
    }


    function combinePosition(address _addr, uint _maturity, bool _call) internal {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint _helperMaturity2 = helperMaturity2; //gas savings
        uint size = strikes[_addr][_maturity].length;
        uint size2 = strikes[_helperAddress][_helperMaturity].length;
        delete strikes[_helperAddress][_helperMaturity2];
        //merge sort
        uint counter1; //counter for strikes[_addr][_maturity]
        uint counter2; //counter for strikes[_helperAddress][_helperMaturity]
        while (counter1+counter2< size+size2){
            if (counter2 == size2 || strikes[_addr][_maturity][counter1] < strikes[_helperAddress][_helperMaturity][counter2]) {
                uint strike = strikes[_addr][_maturity][counter1];
                strikes[_helperAddress][_helperMaturity2].push(strike);
                if (_call)
                    callAmounts[_helperAddress][_helperMaturity2][strike] = callAmounts[_addr][_maturity][strike];
                else
                    putAmounts[_helperAddress][_helperMaturity2][strike] = putAmounts[_addr][_maturity][strike];
                counter1++;
            }
            else if (strikes[_addr][_maturity][counter1] == strikes[_helperAddress][_helperMaturity][counter2]){
                uint strike = strikes[_helperAddress][_helperMaturity][counter2];
                strikes[_helperAddress][_helperMaturity2].push(strike);
                if (_call)
                   callAmounts[_helperAddress][_helperMaturity2][strike] = callAmounts[_addr][_maturity][strike] + callAmounts[_helperAddress][_helperMaturity][strike];
                else
                    putAmounts[_helperAddress][_helperMaturity2][strike] = putAmounts[_addr][_maturity][strike] + putAmounts[_helperAddress][_helperMaturity][strike];
                counter1++;
                counter2++;
            } else {
                //this block will not be hit unless a strike in strikes[_helperAddress][_helperMaturity] has not been added to strikes[_addr][_maturity]
                revert();
            }
        }
    }

    /*
        when true funds are taken from claimedToken and claimedSc reserves to meet collateral requirements
        when false funds are transfered from the address to this contract to meet collateral requirements
    */
    mapping(address => bool) public useDeposits;
    function setUseDeposits(bool _set) public {useDeposits[msg.sender] = _set;}


    function assignCallPosition(address _debtor, address _holder, uint _maturity) internal returns (uint transferAmtDebtor, uint transferAmtHolder) {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint _helperMaturity2 = helperMaturity2; //gas savings

        combinePosition(_holder, _maturity, true);
        (uint minCollateral, uint liabilities) = minSats(_helperAddress, _helperMaturity2, 0,1);
        strikes[_holder][_maturity] = strikes[_helperAddress][_helperMaturity2];
        uint size = strikes[_holder][_maturity].length;
        for (uint i = 0; i < size; i++){
            uint strike = strikes[_holder][_maturity][i];
            callAmounts[_holder][_maturity][strike] = callAmounts[_helperAddress][_helperMaturity2][strike];
        }

        if (minCollateral > satCollateral[_holder][_maturity])
            transferAmtHolder = minCollateral - satCollateral[_holder][_maturity];
        else 
            claimedTokens[_holder] += satCollateral[_holder][_maturity] - minCollateral;
        satCollateral[_holder][_maturity] = minCollateral;
        satDeduction[_holder][_maturity] = liabilities - minCollateral;
        
        //inverse positions for debtor
        size = strikes[_helperAddress][_helperMaturity].length;
        for (uint i = 0; i < size; i++)
            callAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;

        combinePosition(_debtor, _maturity, true);        
        (minCollateral, liabilities) = minSats(_helperAddress, _helperMaturity2, 0,1);
        size = strikes[_debtor][_maturity].length;
        for (uint i = 0; i < size; i++){
            uint strike = strikes[_debtor][_maturity][i];
            callAmounts[_debtor][_maturity][strike] = callAmounts[_helperAddress][_helperMaturity2][strike];
        }

        if (minCollateral > satCollateral[_debtor][_maturity])
            transferAmtDebtor = minCollateral - satCollateral[_debtor][_maturity];
        else
            claimedTokens[_debtor] += satCollateral[_debtor][_maturity] - minCollateral;
        satCollateral[_debtor][_maturity] = minCollateral;
        satDeduction[_debtor][_maturity] = liabilities - minCollateral;
        if (useDeposits[msg.sender]){
            assert(claimedTokens[msg.sender] > transferAmtHolder+transferAmtDebtor);
            claimedTokens[msg.sender] -= transferAmtHolder+transferAmtDebtor;
        }
        else
            ERC20(underlyingAssetAddress).transferFrom(msg.sender, address(this), transferAmtHolder+transferAmtDebtor);
    }


    function assignPutPosition(address _debtor, address _holder, uint _maturity) internal returns (uint transferAmtDebtor, uint transferAmtHolder) {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint _helperMaturity2 = helperMaturity2; //gas savings
        
        combinePosition(_holder, _maturity, false);
        (uint minCollateral, uint liabilities) = minSc(_helperAddress, _helperMaturity2, 0,1);
        strikes[_holder][_maturity] = strikes[_helperAddress][_helperMaturity2];
        uint size = strikes[_holder][_maturity].length;
        for (uint i = 0; i < size; i++){
            uint strike = strikes[_holder][_maturity][i];
            putAmounts[_holder][_maturity][strike] = putAmounts[_helperAddress][_helperMaturity2][strike];
        }
        
        if (minCollateral > scCollateral[_holder][_maturity])
            transferAmtHolder = minCollateral - scCollateral[_holder][_maturity];
        else
            claimedStable[_holder] += scCollateral[_holder][_maturity] - minCollateral;
        scCollateral[_holder][_maturity] = minCollateral;
        scDeduction[_holder][_maturity] = liabilities - minCollateral;


        //inverse positions for debtor
        size = strikes[_helperAddress][_helperMaturity].length;
        for (uint i = 0; i < size; i++)
            putAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;

        combinePosition(_debtor, _maturity, false);        
        (minCollateral, liabilities) = minSc(_helperAddress, _helperMaturity2, 0,1);
        size = strikes[_debtor][_maturity].length;
        for (uint i = 0; i < size; i++){
            uint strike = strikes[_debtor][_maturity][i];
            putAmounts[_debtor][_maturity][strike] = putAmounts[_helperAddress][_helperMaturity2][strike];
        }

        if (minCollateral > scCollateral[_debtor][_maturity])
            transferAmtDebtor = minCollateral - scCollateral[_debtor][_maturity];
        else
            claimedStable[_debtor] += scCollateral[_debtor][_maturity] - minCollateral;
        scCollateral[_debtor][_maturity] = minCollateral;
        scDeduction[_debtor][_maturity] = liabilities - minCollateral;
        if (useDeposits[msg.sender]){
            assert(claimedStable[msg.sender] > transferAmtHolder+transferAmtDebtor);
            claimedStable[msg.sender] -= transferAmtHolder+transferAmtDebtor;
        }
        else 
            ERC20(strikeAssetAddress).transferFrom(msg.sender, address(this), transferAmtHolder+transferAmtDebtor);
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