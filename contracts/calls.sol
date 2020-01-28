pragma solidity ^0.5.12;
import "./oracle.sol";
import "./DappToken.sol";
import "./stablecoin.sol";

contract calls {
    address oracleAddress;
    address dappAddress;
    address stablecoinAddress;
    uint satUnits;
    uint scUnits;
    uint public testing;
    constructor (address _oracleAddress, address _dappAddress, address _stablecoinAddress) public {
        oracleAddress = _oracleAddress;
        dappAddress = _dappAddress;
        stablecoinAddress = _stablecoinAddress;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
        stablecoin sc = stablecoin(stablecoinAddress);
        scUnits = sc.scUnits();
    }
    
    //address => maturity => strike => amount of calls
    mapping(address => mapping(uint => mapping(uint => int))) public callAmounts;
    
    //address => maturity => strike => amount of puts
    mapping(address => mapping(uint => mapping(uint => int))) public putAmounts;

    //denominated in satUnits
    mapping(address => uint) public claimedTokens;
    //denominated in scUnits
    mapping(address => uint) public claimedStable;

    //address => maturity => array of strikes
    mapping(address => mapping(uint => uint[])) public strikes;
    //address => maturity => amount of collateral not required //denominated in satUnits
    mapping(address => mapping(uint => uint)) public satDeduction;
    //address => maturity => amount of collateral not required //denominated in scUnits
    mapping(address => mapping(uint => uint)) public scDeduction;
    
    function mintCall(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        DappToken dt = DappToken(dappAddress);
        require(dt.transferFrom(msg.sender, address(this), satUnits*_amount, false));
        callAmounts[_debtor][_maturity][_strike] -= int(_amount);
        callAmounts[_holder][_maturity][_strike] += int(_amount);
        if (!contains(_debtor, _maturity, _strike)) strikes[_debtor][_maturity].push(_strike);
        if (!contains(_holder, _maturity, _strike)) strikes[_holder][_maturity].push(_strike);
        return true;
    }

    function mintPut(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        stablecoin sc = stablecoin(stablecoinAddress);
        require(sc.transferFrom(msg.sender, address(this), scUnits*_amount*_strike, false));
        putAmounts[_debtor][_maturity][_strike] -= int(_amount);
        putAmounts[_holder][_maturity][_strike] += int(_amount);
        if (!contains(_debtor, _maturity, _strike)) strikes[_debtor][_maturity].push(_strike);
        if (!contains(_holder, _maturity, _strike)) strikes[_holder][_maturity].push(_strike);
        return true;
    }
    
    function claim(uint _maturity) public returns(bool success){
        require(_maturity < block.number);
        //get info from the oracle
        oracle orc = oracle(oracleAddress);
        uint spot = orc.getUint(_maturity);
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

    function contractTokenBalance() public view returns(uint){
        DappToken dt = DappToken(dappAddress);
        return dt.addrBalance(address(this), false);
    }
    
    function contractStableBalance() public view returns(uint){
        stablecoin sc = stablecoin(stablecoinAddress);
        return sc.addrBalance(address(this), false);
    }
    
    //---------functioins added in the mimimise branch-----------------------
    function contains(address _addr, uint _maturity, uint _strike)internal view returns(bool){
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            if (strikes[_addr][_maturity][i] == _strike) return true;
        }
        return false;
    }

    function satValueOf(int _amount, uint _strike, uint _price)public view returns(uint){
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

    function scValueOf(int _amount, uint _strike, uint _price)public view returns(uint){
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

    //the last two paramaters allow for a check on the amount of collateral required if another position were to be taken on
    function totalSatValueOf(address _addr, uint _maturity, uint _price, int _amount, uint _strike)internal view returns(uint){
        uint value = satValueOf(_amount, _strike, _price);
        for(uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=satValueOf(callAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value;
    }

    //the last two paramaters allow for a check on the amount of collateral required if another position were to be taken on
    function totalScValueOf(address _addr, uint _maturity, uint _price, int _amount, uint _strike)internal view returns(uint){
        uint value = scValueOf(_amount, _strike, _price);
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=scValueOf(putAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value;
    }

    //note that usually one fullUnit of the spot underlying is required for collateral on each sold contract
    //returns the minimum amount of collateral that must be locked at the maturity
    //the last two paramaters allow for a check on the amount of collateral required if another position were to be taken on
    function minSats(address _addr, uint _maturity, int _amount, uint _strike) internal view returns(uint){
        if(strikes[_addr][_maturity].length == 0) return 0;
        uint strike = _strike;
        //total number of bought calls minus total number of sold calls
        int sum = _amount;
        uint liabilities = (_amount < 0) ? uint(-_amount) : 0;
        uint value = totalSatValueOf(_addr, _maturity, strike, _amount, _strike);
        uint cValue = 0;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            strike = strikes[_addr][_maturity][i];
            sum += callAmounts[_addr][_maturity][strike];
            liabilities += (callAmounts[_addr][_maturity][strike] < 0)? uint(-callAmounts[_addr][_maturity][strike]) : 0;
            cValue = totalSatValueOf(_addr, _maturity, strike, _amount, _strike);
            if (value > cValue) value = cValue;
        }
        //liabilities has been subtrcted from sum priviously so this is equal to # of bought contracts at infinite spot
        uint valAtInf = uint(sum+int(liabilities))*satUnits; //assets
        return (liabilities*satUnits) - (valAtInf < value ? valAtInf : value);
    }

    //the last two paramaters allow for a check on the amount of collateral required if another position were to be taken on
    function minSc(address _addr, uint _maturity, int _amount, uint _strike) internal view returns(uint){
        if (strikes[_addr][_maturity].length == 0) return 0;
        //account for spot price of 0
        uint strike = 0;
        uint value = totalScValueOf(_addr, _maturity, strike, _amount, _strike);
        int sum = _amount;
        uint liabilities = (_amount < 0) ? uint(-_amount) : 0;
        uint cValue = totalScValueOf(_addr, _maturity, _strike, _amount, _strike);
        if (value > cValue) value = cValue;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            strike = strikes[_addr][_maturity][i];
            sum += putAmounts[_addr][_maturity][strike];
            liabilities += (putAmounts[_addr][_maturity][strike] < 0)? uint(-putAmounts[_addr][_maturity][strike]) : 0;
            cValue = totalScValueOf(_addr, _maturity, strike, _amount, _strike);
            if (value > cValue) value = cValue;
        }
        return (liabilities*scUnits) - value;
    }
}