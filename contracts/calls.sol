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
    //
    mapping(address => uint) public claimedStable;

    function mintCall(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        DappToken dt = DappToken(dappAddress);
        require(dt.transferFrom(msg.sender, address(this), satUnits*_amount, false));
        callAmounts[_debtor][_maturity][_strike] -= int(_amount);
        callAmounts[_holder][_maturity][_strike] += int(_amount);
        return true;
    }

    function mintPut(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        stablecoin sc = stablecoin(stablecoinAddress);
        require(sc.transferFrom(msg.sender, address(this), scUnits*_amount*_strike, false));
        putAmounts[_debtor][_maturity][_strike] -= int(_amount);
        putAmounts[_holder][_maturity][_strike] += int(_amount);
        return true;
    }

    function claim(uint _maturity, uint _strike) public returns(bool success){
        require(_maturity < block.number);
        //calls payout is denoinated in the underlying token
        int amount = callAmounts[msg.sender][_maturity][_strike];
        callAmounts[msg.sender][_maturity][_strike] = 0;
        oracle orc = oracle(oracleAddress);
        uint spot = orc.getUint(_maturity);
        uint payout = 0;
        if (amount != 0){
            if (spot > _strike){
                payout = (uint(amount > 0 ? amount : -amount) * satUnits * (spot - (_strike)))/spot;
            }
            if (amount > 0){
                claimedTokens[msg.sender] += payout;
            }
            else {
                claimedTokens[msg.sender] += uint(-amount)*satUnits - (payout + 1);
            }
        }
        //puts payout is denominated in stablecoins
        amount = putAmounts[msg.sender][_maturity][_strike];
        payout = 0;
        if (amount != 0){
            if (spot < _strike){
                payout = (_strike - spot)*scUnits*uint(amount > 0 ? amount : -amount);
            }
            if (amount > 0){
                claimedStable[msg.sender] += payout;
            }
            else {
                claimedStable[msg.sender] += uint(-amount)*scUnits*_strike - payout;
            }
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

    function oracleVal() public view returns(uint){
        oracle orc = oracle(oracleAddress);
        return orc.get();
    }
    
}