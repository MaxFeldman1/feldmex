pragma solidity ^0.5.12;
import "./oracle.sol";
import "./ERC20.sol";

contract options {
    //address of the contract of the price oracle for the underlying asset in terms of the strike asset such as a price oracle for WBTC/DAI
    address oracleAddress;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the exchange is allowed to see collateral requirements for all users
    address exchangeAddress;
    //deployer can set the exchange address once
    address deployerAddress;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
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
        deployerAddress = msg.sender;
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
    function setExchangeAddress(address _exchangeAddress) public {
        require(exchangeAddress == deployerAddress && msg.sender == deployerAddress);
        exchangeAddress = _exchangeAddress;
    }

    /*
        @Description: allows the deployer to set a new fee

        @param uint _feeDenominator: the value which will be the denominator in the fee on all transactions
            fee == (amount*priceOfOption)/feeDenominator
    */
    function setFee(uint _feeDeonominator) public {
        require(msg.sender == deployerAddress && _feeDeonominator >= 500);
        feeDenominator = _feeDeonominator;
    }

    function setOwner(address _addr) public {
        require(msg.sender == deployerAddress);
        if (deployerAddress == exchangeAddress) exchangeAddress = _addr;
        deployerAddress = _addr;
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
    function mintCall(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(bool success, uint transferAmt){
        if (_debtor == _holder) return (true, 0);
        require(_strike != 0 && contains(_debtor, _maturity, _strike) && contains(_holder, _maturity, _strike));
        ERC20 ua = ERC20(underlyingAssetAddress);
        //satDeduction == liabilities - minSats
        //minSats == liabilities - satDeduction
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*satUnits)
        (uint debtorMinSats, uint debtorLiabilities) = minSats(_debtor, _maturity, -int(_amount), _strike);
        (uint holderMinSats, uint holderLiabilities) = minSats(_holder, _maturity, int(_amount), _strike);

        transferAmt = debtorMinSats - satCollateral[_debtor][_maturity];
        if (transferAmt > _maxTransfer) return(false, 0);
        require(ua.transferFrom(msg.sender, address(this), transferAmt));
        satCollateral[_debtor][_maturity] += transferAmt; // == debtorMinSats
        claimedTokens[_holder] += satCollateral[_holder][_maturity] - holderMinSats;
        satCollateral[_holder][_maturity] = holderMinSats;

        satDeduction[_debtor][_maturity] = debtorLiabilities-debtorMinSats;
        satDeduction[_holder][_maturity] = holderLiabilities-holderMinSats;

        callAmounts[_debtor][_maturity][_strike] -= int(_amount);
        callAmounts[_holder][_maturity][_strike] += int(_amount);
        return (true, transferAmt);
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
    function mintPut(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(bool success, uint transferAmt){
        if (_debtor == _holder) return (true, 0);
        require(_strike != 0 && contains(_debtor, _maturity, _strike) && contains(_holder, _maturity, _strike));
        ERC20 sa = ERC20(strikeAssetAddress);
        //scDeduction == liabilities - minSc
        //minSc == liabilities - ssDeductionuint debtorMinSc = minSc(_debtor, _maturity, -int(_amount), _strike);
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*scUnits)
        (uint debtorMinSc, uint debtorLiabilities) = minSc(_debtor, _maturity, -int(_amount), _strike);
        (uint holderMinSc, uint holderLiabilities) = minSc(_holder, _maturity, int(_amount), _strike);

        transferAmt = debtorMinSc - scCollateral[_debtor][_maturity];
        if (transferAmt > _maxTransfer) return (false, 0);
        require(sa.transferFrom(msg.sender,  address(this), transferAmt));
        scCollateral[_debtor][_maturity] += transferAmt; // == debtorMinSc
        claimedStable[_holder] += scCollateral[_holder][_maturity] - holderMinSc;
        scCollateral[_holder][_maturity] = holderMinSc;

        scDeduction[_debtor][_maturity] = debtorLiabilities-debtorMinSc;
        scDeduction[_holder][_maturity] = holderLiabilities-holderMinSc;

        putAmounts[_debtor][_maturity][_strike] -= int(_amount);
        putAmounts[_holder][_maturity][_strike] += int(_amount);
        return (true, transferAmt);
    }
    
    /*
        @Description: after the maturity holders of contracts to claim the value of the contracts and allows debtors to claim the unused collateral

        @pram uint _maturity: the maturity that the sender of this transaction is attempting to claim rewards from

        @return bool success: if an error occurs returns false if no error return true
    */
    function claim(uint _maturity) public returns(bool success){
        require(_maturity < block.timestamp);
        //get info from the oracle
        oracle orc = oracle(oracleAddress);
        uint spot = orc.getAtTime(_maturity);
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
            uint fee = callValue/feeDenominator;
            claimedTokens[deployerAddress] += fee;
            claimedTokens[msg.sender] += callValue - fee;
        }
        if (putValue > scDeduction[msg.sender][_maturity]){
            putValue -= scDeduction[msg.sender][_maturity];
            uint fee = putValue/feeDenominator;
            claimedStable[deployerAddress] += fee;
            claimedStable[msg.sender] += putValue - fee;
        }
        return true;
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
        assert(ua.transfer(msg.sender, underlyingAsset));
        ERC20 sa = ERC20(strikeAssetAddress);
        strikeAsset = claimedStable[msg.sender];
        claimedStable[msg.sender] = 0;
        assert(sa.transfer(msg.sender, strikeAsset));
        return (underlyingAsset, strikeAsset);
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
        return true;
    }

    /*
        @Description: used to tell if strikes[givenAddress][givenMaturity] contains a given strike

        @param address _addr: the address is question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike price in question

        @return bool: returns true if strike[_addr][_maturity] contains _strike otherwise returns false
    */
    function contains(address _addr, uint _maturity, uint _strike)public view returns(bool){
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            if (strikes[_addr][_maturity][i] == _strike) return true;
        }
        return false;
    }


    /*
        @Description: used to find the value of a given call postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the call contract in terms of the underlying versus stablecoie
        @param uint _price: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint: the value of the position in terms of the underlying multiplied by the price
            inflate value by multiplying by price and divide out after doing calculations with the returned value to maintain accuracy
    */
    function satValueOf(int _amount, uint _strike, uint _price)internal view returns(uint){
        uint payout = 0;
        if (_amount != 0){
            if (_price > _strike){
                //inflator is canceld out of numerator and denominator
                payout = (uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - (_strike)));
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*satUnits*_price - payout;
            }
        } 
        return 0;
    }

    /*
        @Description: used to find the value of a given put postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the put contract in terms of the underlying versus stablecoie
        @param uint _prive: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint: the value of the position in terms of the strike asset
    */
    function scValueOf(int _amount, uint _strike, uint _price)internal pure returns(uint){
        uint payout = 0;
        if (_amount != 0){
            if (_price < _strike){
                //inflator must be divided out thus remove *satUnits
                payout = (_strike - _price)*uint(_amount > 0 ? _amount : -_amount);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                //inflator must be divided out thus remove *satUnits
                return uint(-_amount)*_strike - payout;
            }
        }
        return 0;
    }

    /*
        @Description: used to find the value of an addresses call positions at a given maturity
            also alows for input of another position to find the value of and add to the total value

        @param address _addr: address of which to check the value of call positons
        @param uint _maturity: the maturity in question
        @param uint _price: the spot price at which to find the value of positions
        @param int _amount: the amount of the extra position that is to be calculated alongside the positions of the address
        @param uint _strike: the strike price of the position that is to be calculated alongside the positions of the address

        @return uint: the total value of all positons at the spot price combined as well as the value of the added position denominated in the underlying
    */
    function totalSatValueOf(address _addr, uint _maturity, uint _price, int _amount, uint _strike)internal view returns(uint){
        uint value = satValueOf(_amount, _strike, _price);
        for(uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=satValueOf(callAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value/_price;
    }

    /*
        @Description: used to find the value of an addresses put positions at a given maturity
            also alows for input of another position to find the value of and add to the total value

        @param address _addr: address of which to check the value of put positons
        @param uint _maturity: the maturity in question
        @param uint _price: the spot price at which to find the value of positions
        @param int _amount: the amount of the extra position that is to be calculated alongside the positions of the address
        @param uint _strike: the strike price of the position that is to be calculated alongside the positions of the address

        @return uint: the total value of all positons at the spot price combined as well as the value of the added position denominated in strike asset
    */
    function totalScValueOf(address _addr, uint _maturity, uint _price, int _amount, uint _strike)internal view returns(uint){
        uint value = scValueOf(_amount, _strike, _price);
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=scValueOf(putAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value;
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
    function minSats(address _addr, uint _maturity, int _amount, uint _strike) internal view returns(uint minCollateral, uint liabilities){
        uint strike = _strike;
        //total number of bought calls minus total number of sold calls
        _amount += callAmounts[_addr][_maturity][_strike];
        int sum = _amount;
        liabilities = (_amount < 0) ? uint(-_amount) : 0;
        uint minValue = totalSatValueOf(_addr, _maturity, strike, _amount, _strike);
        uint cValue = 0;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            strike = strikes[_addr][_maturity][i];
            if (strike == _strike || callAmounts[_addr][_maturity][strike] == 0) continue;
            sum += callAmounts[_addr][_maturity][strike];
            liabilities += (callAmounts[_addr][_maturity][strike] < 0)? uint(-callAmounts[_addr][_maturity][strike]) : 0;
            cValue = totalSatValueOf(_addr, _maturity, strike, _amount, _strike);
            if (minValue > cValue) minValue = cValue;
        }
        //liabilities has been subtrcted from sum priviously so this is equal to # of bought contracts at infinite spot
        uint valAtInf = uint(sum+int(liabilities))*satUnits; //assets
        minValue = (valAtInf < minValue ? valAtInf : minValue);
        liabilities*=satUnits;
        if (minValue > liabilities) return (0, liabilities);
        return ((liabilities) - minValue, liabilities);
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
        //account for spot price of 0
        uint strike = 0;
        _amount += putAmounts[_addr][_maturity][_strike];
        uint minValue = totalScValueOf(_addr, _maturity, strike, _amount, _strike);
        int sum = _amount;
        liabilities = _strike * ((_amount < 0) ? uint(-_amount) : 0);
        uint cValue = totalScValueOf(_addr, _maturity, _strike, _amount, _strike);
        if (minValue > cValue) minValue = cValue;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            strike = strikes[_addr][_maturity][i];
            if (strike == _strike || putAmounts[_addr][_maturity][strike] == 0) continue;
            sum += putAmounts[_addr][_maturity][strike];
            liabilities += strike * ((putAmounts[_addr][_maturity][strike] < 0)? uint(-putAmounts[_addr][_maturity][strike]) : 0);
            cValue = totalScValueOf(_addr, _maturity, strike, _amount, _strike);
            if (minValue > cValue) minValue = cValue;
        }
        //note that every time we add another liability we multiply by the strike thus the inflator must be divided out when we are done
        //liabilities*=scUnits;
        if (minValue > liabilities) return (0, liabilities);
        return ((liabilities) - minValue, liabilities);
    }


    /*
        @Description: used to find the amount by which a user's account would need to be funded for a user to make an order

        @param bool _token: _token => call also !_token => put
        @param address _addr: the user in question
        @param uint _maturity: the maturity timestamp in question
        @param int _amount: the amount of calls or puts in the order, positive amount means buy, negative amount means sell
        @param uint _strike: the strike price in question

        @return uint: the amount of satUnits or scUnits that must be sent as collateral for the order described to go through
    */
    function transferAmount(bool _token, address _addr, uint _maturity, int _amount, uint _strike) public view returns (uint){
        require(msg.sender == _addr || msg.sender == exchangeAddress);
        if (_amount >= 0) return 0;
        if (_token){
            (uint minCollateral, ) = minSats(_addr, _maturity, _amount, _strike);
            return minCollateral-satCollateral[_addr][_maturity];
        }
        (uint minCollateral, ) = minSc(_addr, _maturity, _amount, _strike);
        return minCollateral-scCollateral[_addr][_maturity];
    }

    /*
        @Description: The function was created for positions at a strike to be inclueded in calculation of collateral requirements for a user
            User calls this instead of smart contract adding strikes automatically when funds are transfered to an address by the transfer or transferFrom functions
            because it prevents a malicious actor from overloading a user with many different strikes thus making it impossible to claim funds because of the gas limit

        @param uint _maturity: this is the maturity at which the strike will be added if it is not already recorded at this maturity
        @param uint _strike: this is the strike that will be added.

        @return bool: returns true if the strike is sucessfully added and false if the strike was already recorded at the maturity
    */
    function addStrike(uint _maturity, uint _strike) public returns(bool contained){
        (contained,) = containsStrike(msg.sender, _maturity, _strike, true, false);
    }

    /*
    function removeStrike(uint _maturity, uint _index) public returns(bool success){
        require(strikes[msg.sender][_maturity].length > _index);
        uint temp = strikes[msg.sender][_maturity][strikes[_addr][_maturity].length-1];
        strikes[msg.sender][_maturity][_index] = temp;
        delete strikes[msg.sender][_maturity][strikes[_addr][_maturity].length-1];
    }
    */

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
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            if (strikes[_addr][_maturity][i] == _strike){
                if (_remove){
                    uint temp = strikes[_addr][_maturity][strikes[_addr][_maturity].length-1];
                    strikes[_addr][_maturity][i] = temp;
                    delete strikes[_addr][_maturity][strikes[_addr][_maturity].length-1];
                }
                return (true, i);
            }
        }
        if (_push) strikes[_addr][_maturity].push(_strike);
        return (false, 0);
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
    
    string public name = "Feldmex";

    /*
        the total supply will always be zero as all long positions(positive values) are canceled out by all short positions(negative values)
        this applys for both calls and puts at all maturities and strikes
    */

    uint256 public totalSupply = 0;
    
    /*
        @Description: this function takes from claimedTokens[msg.sender] as the source of needed collateral instead of calling transferFrom
            which would take the funds from msg.sender directly
            msg.sender needs to have sufficent funds deposited in this contract before calling this function

    */
    function transferCall(address _from, address _to, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) internal returns(bool success, uint transferAmt){
        if (_from == _to || _amount == 0) return (true, 0);
        //satDeduction == liabilities - minSats
        //minSats == liabilities - satDeduction
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*satUnits)
        (uint debtorMinSats, uint debtorLiabilities) = minSats(_from, _maturity, -int(_amount), _strike);
        (uint toMinSats, uint toLiabilities) = minSats(_to, _maturity, int(_amount), _strike);

        transferAmt = debtorMinSats - satCollateral[_from][_maturity];
        if (transferAmt > _maxTransfer || claimedTokens[_from] < transferAmt) return(false, 0);
        claimedTokens[_from] -= transferAmt;
        satCollateral[_from][_maturity] += transferAmt; // == debtorMinSats
        
        claimedTokens[_to] += satCollateral[_to][_maturity] - toMinSats;
        satCollateral[_to][_maturity] = toMinSats;

        satDeduction[_from][_maturity] = debtorLiabilities-debtorMinSats;
        satDeduction[_to][_maturity] = toLiabilities-toMinSats;

        callAmounts[_from][_maturity][_strike] -= int(_amount);
        callAmounts[_to][_maturity][_strike] += int(_amount);
        
        containsStrike(_from, _maturity, _strike, true, false);
        return (true, transferAmt);
    }

    function transferPut(address _from, address _to, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) internal returns(bool success, uint transferAmt){
        if (_from == _to || _amount == 0) return (true, 0);
        //scDeduction == liabilities - minSc
        //minSc == liabilities - ssDeductionuint debtorMinSc = minSc(_debtor, _maturity, -int(_amount), _strike);
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*scUnits)
        (uint debtorMinSc, uint debtorLiabilities) = minSc(_from, _maturity, -int(_amount), _strike);
        (uint toMinSc, uint toLiabilities) = minSc(_to, _maturity, int(_amount), _strike);

        transferAmt = debtorMinSc - scCollateral[_from][_maturity];
        if (transferAmt > _maxTransfer || claimedStable[_from] < transferAmt) return (false, 0);
        claimedStable[_from] -= transferAmt;
        scCollateral[_from][_maturity] += transferAmt; // == debtorMinSc

        claimedStable[_to] += scCollateral[_to][_maturity] - toMinSc;
        scCollateral[_to][_maturity] = toMinSc;

        scDeduction[_from][_maturity] = debtorLiabilities-debtorMinSc;
        scDeduction[_to][_maturity] = toLiabilities-toMinSc;

        putAmounts[_from][_maturity][_strike] -= int(_amount);
        putAmounts[_to][_maturity][_strike] += int(_amount);
        
        containsStrike(_from, _maturity, _strike, true, false);
        return (true, transferAmt);
    }

    function transfer(address _to, uint256 _value, uint _maturity, uint _strike, uint _maxTransfer, bool _call) public returns(bool success, uint transferAmt){
        (bool contained,) = containsStrike(_to, _maturity, _strike, false, false);
        require(_strike != 0 && contained);
        emit Transfer(msg.sender, _to, _value, _maturity, _strike, _call);
        if (_call) return transferCall(msg.sender, _to, _maturity, _strike, _value, _maxTransfer);
        return transferPut(msg.sender, _to, _maturity, _strike, _value, _maxTransfer);
    }

    function approve(address _spender, uint256 _value, uint _maturity, uint _strike, bool _call) public returns(bool success){
        require(_strike != 0);
        emit Approval(msg.sender, _spender, _value, _maturity, _strike, _call);
        if (_call) callAllowance[msg.sender][_spender][_maturity][_strike] = _value;
        else putAllowance[msg.sender][_spender][_maturity][_strike] = _value;
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value, uint _maturity, uint _strike, uint _maxTransfer, bool _call) public returns(bool success, uint transferAmt){
        (bool contained,) = containsStrike(_to, _maturity, _strike, false, false);
        require(_strike != 0 && contained);
        require(_value <= (_call ? callAllowance[_from][msg.sender][_maturity][_strike]: putAllowance[_from][msg.sender][_maturity][_strike]));
        emit Transfer(_from, _to, _value, _maturity, _strike, _call);
        if (_call) {
            callAllowance[_from][msg.sender][_maturity][_strike] -= _value;
            return transferCall(_from, _to, _maturity, _strike, _value, _maxTransfer);
        }
        putAllowance[_from][msg.sender][_maturity][_strike] -= _value;
        return transferPut(_from, _to, _maturity, _strike, _value, _maxTransfer);
    }

    function allowance(address _owner, address _spender, uint _maturity, uint _strike, bool _call) public view returns(uint256 remaining){
        if (_call) return callAllowance[_owner][_spender][_maturity][_strike];
        return putAllowance[_owner][_spender][_maturity][_strike];
    }

    function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) public view returns(int256 balance){
        if (_call) return callAmounts[_owner][_maturity][_strike];
        return putAmounts[_owner][_maturity][_strike];
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