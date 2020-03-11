pragma solidity ^0.5.12;
import "./oracle.sol";
import "./DappToken.sol";
import "./stablecoin.sol";

contract options {
    //address of the contract of the price oracle for the underlying asset in terms of the stablecoin such as a price oracle for WBTC/DAI
    address oracleAddress;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address dappAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address stablecoinAddress;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
    //variable occasionally used for testing purposes should not be present in production
    uint public testing;
    
    /*
        @Description: assigns the addesses of external contracts

        @param address _oracleAddress: address that shall be assigned to oracleAddress
        @param address _dappAddress: address that shall be assigned to dappAddress
        @param address _stablecoinAddress: address that shall be assigned to stablecoinAddress
    */
    constructor (address _oracleAddress, address _dappAddress, address _stablecoinAddress) public {
        oracleAddress = _oracleAddress;
        dappAddress = _dappAddress;
        stablecoinAddress = _stablecoinAddress;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
        stablecoin sc = stablecoin(stablecoinAddress);
        scUnits = sc.scUnits();
    }
    
    /*
        callAmounts and putAmounts store the net position of each type of calls and puts respectively for each user at each matirity and strike
    */
    //address => maturity => strike => amount of calls
    mapping(address => mapping(uint => mapping(uint => int))) public callAmounts;
    
    //address => maturity => strike => amount of puts
    mapping(address => mapping(uint => mapping(uint => int))) public putAmounts;

    /*
        claimedTokens and claimedStable refers to the amount of the underlying and stablecoin respectively that each user may withdraw
    */
    //denominated in satUnits
    mapping(address => uint) public claimedTokens;
    //denominated in scUnits
    mapping(address => uint) public claimedStable;

    /*
        satCollateral maps each user to the amount of collateral in the underlying that they have locked at each maturuty for calls
        scCollateral maps each user to the amount of collateral in stablecoin that they have locked at each maturity for puts
    */
    //address => maturity => amount (denominated in satUnits)
    mapping(address => mapping(uint => uint)) public satCollateral;
    //address => maturity => amount (denominated in scUnits)
    mapping(address => mapping(uint => uint)) public scCollateral;


    /*
        strikes maps each user to the strikes that they have traded calls or puts on for each maturity
    */
    //address => maturity => array of strikes
    mapping(address => mapping(uint => uint[])) public strikes;

    /*
        satDeduction is the amount of underlying asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for calls
        scDeduction is the amount of stablecoin collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for puts
    */
    //address => maturity => amount of collateral not required //denominated in satUnits
    mapping(address => mapping(uint => uint)) public satDeduction;
    //address => maturity => amount of collateral not required //denominated in scUnits
    mapping(address => mapping(uint => uint)) public scDeduction;
    

    /*
        @Description: handles the logistics of creating a long call position for the holder and short call position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address payable _debtor: the address that collateral posted here will be associated with and the for which the call will be considered a liability
        @param address payable _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the call contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the stablecoin at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of calls that the debtor is adding as short and the holder is adding as long
        @param uint _maxTransfer: the maximum amount of collateral that this function can take on behalf of the debtor from the message sender denominated in satUnits
            if this limit needs to be broken to mint the call the transaction will return (true, 0)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmount: returns the amount of the underlying that was transfered from the message sender to act as collateral for the debtor
    */
    function mintCall(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(bool success, uint transferAmount){
        require(_debtor != _holder);
        DappToken dt = DappToken(dappAddress);
        //satDeduction == liabilities - minSats
        //minSats == liabilities - satDeduction
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*satUnits)
        (uint debtorMinSats, uint debtorLiabilities) = minSats(_debtor, _maturity, -int(_amount), _strike);
        (uint holderMinSats, uint holderLiabilities) = minSats(_holder, _maturity, int(_amount), _strike);

        transferAmount = debtorMinSats - satCollateral[_debtor][_maturity];
        if (transferAmount > _maxTransfer) return(false, 0);
        require(dt.transferFrom(msg.sender, address(this), transferAmount, false));
        satCollateral[_debtor][_maturity] += transferAmount; // == debtorMinSats
        claimedTokens[_holder] += satCollateral[_holder][_maturity] - holderMinSats;
        satCollateral[_holder][_maturity] = holderMinSats;

        satDeduction[_debtor][_maturity] = debtorLiabilities-debtorMinSats;
        satDeduction[_holder][_maturity] = holderLiabilities-holderMinSats;

        callAmounts[_debtor][_maturity][_strike] -= int(_amount);
        callAmounts[_holder][_maturity][_strike] += int(_amount);
        if (!contains(_debtor, _maturity, _strike)) strikes[_debtor][_maturity].push(_strike);
        if (!contains(_holder, _maturity, _strike)) strikes[_holder][_maturity].push(_strike);
        return (true, transferAmount);
    }


    /*
        @Description: handles the logistics of creating a long put position for the holder and short put position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address payable _debtor: the address that collateral posted here will be associated with and the for which the put will be considered a liability
        @param address payable _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the put contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the stablecoin at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of puts that the debtor is adding as short and the holder is adding as long
        @param uint _maxTransfer: the maximum amount of collateral that this function can take on behalf of the debtor from the message sender denominated in scUnits
            if this limit needs to be broken to mint the put the transaction will return (false, 0)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmount: returns the amount of stablecoin that was transfered from the message sender to act as collateral for the debtor
    */
    function mintPut(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) public returns(bool success, uint transferAmount){
        require(_debtor != _holder);
        stablecoin sc = stablecoin(stablecoinAddress);
        //scDeduction == liabilities - minSc
        //minSc == liabilities - ssDeductionuint debtorMinSc = minSc(_debtor, _maturity, -int(_amount), _strike);
        //the previous liabilities amount for the debtor is debtorLiabilities-(_amount*scUnits)
        (uint debtorMinSc, uint debtorLiabilities) = minSc(_debtor, _maturity, -int(_amount), _strike);
        (uint holderMinSc, uint holderLiabilities) = minSc(_holder, _maturity, int(_amount), _strike);

        transferAmount = debtorMinSc - scCollateral[_debtor][_maturity];
        if (transferAmount > _maxTransfer) return (false, 0);
        require(sc.transferFrom(msg.sender,  address(this), transferAmount, false));
        scCollateral[_debtor][_maturity] += transferAmount; // == debtorMinSc
        claimedStable[_holder] += scCollateral[_holder][_maturity] - holderMinSc;
        scCollateral[_holder][_maturity] = holderMinSc;

        scDeduction[_debtor][_maturity] = debtorLiabilities-debtorMinSc;
        scDeduction[_holder][_maturity] = holderLiabilities-holderMinSc;

        putAmounts[_debtor][_maturity][_strike] -= int(_amount);
        putAmounts[_holder][_maturity][_strike] += int(_amount);
        if (!contains(_debtor, _maturity, _strike)) strikes[_debtor][_maturity].push(_strike);
        if (!contains(_holder, _maturity, _strike)) strikes[_holder][_maturity].push(_strike);
        return (true, transferAmount);
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
        delete strikes[msg.sender][_maturity];
        if (callValue > satDeduction[msg.sender][_maturity]){
            callValue -= satDeduction[msg.sender][_maturity];
            claimedTokens[msg.sender] += callValue;
        }
        if (putValue > scDeduction[msg.sender][_maturity]){
            putValue -= scDeduction[msg.sender][_maturity];
            claimedStable[msg.sender] += putValue;
        }
        return true;
    }

    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and stablecoins respectively
    */
    function withdrawFunds() public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        uint funds = claimedTokens[msg.sender];
        claimedTokens[msg.sender] = 0;
        assert(dt.transfer(msg.sender, funds, false));
        stablecoin sc = stablecoin(stablecoinAddress);
        funds = claimedStable[msg.sender];
        claimedStable[msg.sender] = 0;
        assert(sc.transfer(msg.sender, funds, false));
        return true;
    }

    /*
        @Description: allows for users to deposit funds that are not tided up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and stablecoins respectively
    */
    function depositFunds(uint _sats, bool _fullToken, uint _sc, bool _fullSc) public returns(bool success){
        if (_sats > 0){
            DappToken dt = DappToken(dappAddress);
            require(dt.transferFrom(msg.sender, address(this), _sats, _fullToken));
            claimedTokens[msg.sender] += _sats;
        }
        if (_sc > 0){
            stablecoin sc = stablecoin(stablecoinAddress);
            require(sc.transferFrom(msg.sender, address(this), _sc, _fullSc));
            claimedStable[msg.sender] += _sc;
        }
        return true;
    }

    /*
        @Description: returns the total amount of the underlying that is held by this smart contract
    */
    function contractTokenBalance() public view returns(uint){
        DappToken dt = DappToken(dappAddress);
        return dt.addrBalance(address(this), false);
    }
    

    /*
        @Description: returns the total amount of stablecoin that is held by this smart contract
    */
    function contractStableBalance() public view returns(uint){
        stablecoin sc = stablecoin(stablecoinAddress);
        return sc.addrBalance(address(this), false);
    }

    /*
        @Description: used to tell if strikes[givenAddress][givenMaturity] contains a given strike

        @param address _addr: the address is question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike price in question

        @return bool: returns true if strike[_addr][_maturity] contains _strike otherwise returns false
    */    
    function contains(address _addr, uint _maturity, uint _strike)internal view returns(bool){
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
        @param uint _prive: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint: the value of the position in terms of the underlying
    */
    function satValueOf(int _amount, uint _strike, uint _price)internal view returns(uint){
        uint payout = 0;
        if (_amount != 0){
            if (_price > _strike){
                payout = (uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - (_strike)))/_price;
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*satUnits - (payout + 1);
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

        @return uint: the value of the position in terms of the stablecoin
    */
    function scValueOf(int _amount, uint _strike, uint _price)internal view returns(uint){
        uint payout = 0;
        if (_amount != 0){
            if (_price < _strike){
                payout = (_strike - _price)*scUnits*uint(_amount > 0 ? _amount : -_amount);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*scUnits*_strike - payout;
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
        return value;
    }

    /*
        @Description: used to find the value of an addresses put positions at a given maturity
            also alows for input of another position to find the value of and add to the total value

        @param address _addr: address of which to check the value of put positons
        @param uint _maturity: the maturity in question
        @param uint _price: the spot price at which to find the value of positions
        @param int _amount: the amount of the extra position that is to be calculated alongside the positions of the address
        @param uint _strike: the strike price of the position that is to be calculated alongside the positions of the address

        @return uint: the total value of all positons at the spot price combined as well as the value of the added position denominated in stablecoin
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
            if (strike == _strike) continue;
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

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in stablecoin
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
            if (strike == _strike) continue;
            sum += putAmounts[_addr][_maturity][strike];
            liabilities += strike * ((putAmounts[_addr][_maturity][strike] < 0)? uint(-putAmounts[_addr][_maturity][strike]) : 0);
            cValue = totalScValueOf(_addr, _maturity, strike, _amount, _strike);
            if (minValue > cValue) minValue = cValue;
        }
        liabilities*=scUnits;
        if (minValue > liabilities) return (0, liabilities);
        return ((liabilities) - minValue, liabilities);
    }


    /*
    -----------ToDo Function description-----------------
    */
    function transferAmount(bool _token, address _addr, uint _maturity, int _amount, uint _strike) public view returns (uint){
        if (_amount >= 0) return 0;
        if (_token){
            (uint minCollateral, ) = minSats(_addr, _maturity, _amount, _strike);
            return minCollateral-satCollateral[_addr][_maturity];
        }
        (uint minCollateral, ) = minSc(_addr, _maturity, _amount, _strike);
        return minCollateral-scCollateral[_addr][_maturity];
    }
}