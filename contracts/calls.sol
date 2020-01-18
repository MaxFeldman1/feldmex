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

    /*function claim(uint _maturity, uint _strike) public returns(bool success){
        require(_maturity < block.number);
        //calls payout is denoinated in the underlying token
        int callAmount = callAmounts[msg.sender][_maturity][_strike];
        int putAmount = putAmounts[msg.sender][_maturity][_strike];
        //set to zero to avoid multi send attack
        callAmounts[msg.sender][_maturity][_strike] = 0;
        putAmounts[msg.sender][_maturity][_strike] = 0;
        //interact with oracle
        oracle orc = oracle(oracleAddress);
        uint spot = orc.getUint(_maturity);
        //now credit amount due
        claimedTokens[msg.sender] += satValueOf(callAmount, _strike, spot);
        claimedStable[msg.sender] += scValueOf(putAmount, _strike, spot);
        return true;
    }*/
    
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
        claimedTokens[msg.sender] += callValue;
        claimedStable[msg.sender] += putValue;
        delete strikes[msg.sender][_maturity];
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

    function oracleVal() public view returns(uint){
        oracle orc = oracle(oracleAddress);
        return orc.get();
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
    /*
    //this should only be called when we are distributing tokens because it sets all balances to 0
    function totalSatValueOfModify(address _addr, uint _maturity, uint _price)internal returns(uint){
        uint value = 0;
        int amount;
        for(uint i = 0; i < strikes[_addr][_maturity].length; i++){
            uint strike = strikes[_addr][_maturity][i];
            amount = callAmounts[_addr][_maturity][strike];
            callAmounts[_addr][_maturity][strike] = 0;
            value+=satValueOf(amount, strikes[_addr][_maturity][i], _price);
        }
        return value;
    }

    //this should only be called when we are distributing tokens because it sets all balances to 0
    function totalScValueOfModify(address _addr, uint _maturity, uint _price)internal returns(uint){
        uint value = 0;
        int amount;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            uint strike = strikes[_addr][_maturity][i];
            amount = putAmounts[_addr][_maturity][strike];
            putAmounts[_addr][_maturity][strike] = 0;
            value+=scValueOf(amount, strikes[_addr][_maturity][i], _price);
        }
        return value;
    }//*/

    function totalSatValueOf(address _addr, uint _maturity, uint _price)internal view returns(uint){
        uint value = 0;
        for(uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=satValueOf(callAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value;
    }

    function totalScValueOf(address _addr, uint _maturity, uint _price)internal view returns(uint){
        uint value = 0;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            value+=scValueOf(putAmounts[_addr][_maturity][strikes[_addr][_maturity][i]], strikes[_addr][_maturity][i], _price);
        }
        return value;
    }

}