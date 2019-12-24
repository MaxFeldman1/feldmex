pragma solidity ^0.5.12;
import "./oracle.sol";
import "./DappToken.sol";
import "./stablecoin.sol";

contract calls {
    address oracleAddress;
    address dappAddress;
    uint satUnits;
    
    constructor (address _oracleAddress, address _dappAddress) public {
        oracleAddress = _oracleAddress;
        dappAddress = _dappAddress;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
    }
    
    //address => maturity => strike => amount of calls
    mapping(address => mapping(uint => mapping(uint => int))) public callAmounts;
    
    //address => maturity => strike => amount of puts
    //mapping(address => mapping(uint => mapping(uint => int))) public puts;

    //collateral is denominated in satUnits
    mapping(address => uint) public collateral;

    function mintCall(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        DappToken dt = DappToken(dappAddress);
        require(dt.transferFrom(msg.sender, address(this), satUnits*_amount, false));
        callAmounts[_debtor][_maturity][_strike] -= int(_amount);
        callAmounts[_holder][_maturity][_strike] += int(_amount);
        return true;
    }

    function claim(uint _maturity, uint _strike) public returns(bool success){
        int amount = callAmounts[msg.sender][_maturity][_strike];
        require(_maturity < block.number && amount != 0);
        callAmounts[msg.sender][_maturity][_strike] = 0;
        oracle orc = oracle(oracleAddress);
        uint spot = orc.getUint(_maturity);
        uint payout = 0;
        if (spot > _strike){
            payout = (uint(amount > 0 ? amount : -amount) * satUnits * (spot - (_strike)))/spot;
        }
        if (amount > 0){
            collateral[msg.sender] += payout;
        }
        else {
            collateral[msg.sender] += uint(-amount)*satUnits - (payout + 1);
        }
        return true;
    }
    
    function withdrawFunds() public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        uint funds = collateral[msg.sender];
        collateral[msg.sender] = 0;
        assert(dt.transfer(msg.sender, funds, false));
        return true;
    }

    function contractBalance() public view returns(uint){
        DappToken dt = DappToken(dappAddress);
        return dt.addrBalance(address(this), false);
    }
    
    function oracleVal() public view returns(uint){
        oracle orc = oracle(oracleAddress);
        return orc.get();
    }
    
}