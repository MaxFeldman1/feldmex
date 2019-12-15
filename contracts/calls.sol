pragma solidity ^0.5.12;
import "./oracle.sol";
import "./DappToken.sol";

contract calls {
    address oracleAddress;
    address dappAddress;
    uint satUnits;
    struct call{
        address payable debtor;
        address payable holder;
        //block by which option may be exercised
        uint maturity;
        //strike is denominated in satoshis
        uint strike;
        uint timestamp;
        uint amount;
    }
    
    constructor (address _oracleAddress, address _dappAddress) public {
        oracleAddress = _oracleAddress;
        dappAddress = _dappAddress;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
    }
    
    //use hash of 
    mapping (bytes32 => call) public allCalls;
    /*
        to-do
        change the array from below to a linked list
    */
    mapping (address => bytes32[]) contracts;
    
    function mint(address payable _debtor, address payable _holder, uint _maturity, uint _strike, uint _amount) public returns(bool success){
        require(_debtor != _holder);
        DappToken dt = DappToken(dappAddress);
        require(dt.transferFrom(msg.sender, address(this), satUnits*_amount, false));

        call memory cont = call(_debtor, _holder, _maturity, _strike * satUnits, now, _amount);
        bytes32 hash = hashCall(cont);
        allCalls[hash] = cont;
        contracts[_debtor].push(hash);
        contracts[_holder].push(hash);
        return true;
    }
    
    function hashCall(call memory c) internal pure returns(bytes32){
        bytes32 hash = keccak256(abi.encodePacked(c.debtor, c.holder, c.strike, c.maturity, c.timestamp));
        return hash;
    }
    
    function exercize(bytes32 _hash) public {
        DappToken dt = DappToken(dappAddress);
        uint spot = oracleVal() * satUnits;
        require(msg.sender == allCalls[_hash].holder && block.number <= allCalls[_hash].maturity && spot > allCalls[_hash].strike);
        
        //distribute funds
        uint payout = (allCalls[_hash].amount * satUnits*(spot - (allCalls[_hash].strike)))/spot;
        dt.transfer(allCalls[_hash].holder, payout ,false);
        //distribute excess collateral back to the seller
        dt.transfer(allCalls[_hash].debtor, allCalls[_hash].amount*satUnits - payout, false);
        
        //remove the option contract from the blockchian
        remove(allCalls[_hash].holder, locate(allCalls[_hash].holder, _hash));
        remove(allCalls[_hash].debtor, locate(allCalls[_hash].debtor, _hash));
        delete allCalls[_hash];
    }
    
    function exercizeIndex(uint _index) public {
        DappToken dt = DappToken(dappAddress);
        require(_index < contracts[msg.sender].length);
        bytes32 hash = contracts[msg.sender][_index];
        uint spot = oracleVal() * satUnits;
        require(msg.sender == allCalls[hash].holder && block.number <= allCalls[hash].maturity && spot > allCalls[hash].strike);
        
        //distribute funds
        uint payout = (allCalls[hash].amount * satUnits*(spot - (allCalls[hash].strike)))/spot;
        dt.transfer(allCalls[hash].holder, payout, false);
        //distribute excess collateral back to the seller
        dt.transfer(allCalls[hash].debtor, satUnits * allCalls[hash].amount - payout, false);
        
        //remove the option contract from the blockchian
        remove(allCalls[hash].holder, locate(allCalls[hash].holder, hash));
        remove(allCalls[hash].debtor, locate(allCalls[hash].debtor, hash));
        delete allCalls[hash];
    }
    
    function reclaim(bytes32 _hash) public {
        DappToken dt = DappToken(dappAddress);
        require(msg.sender == allCalls[_hash].debtor && block.number > allCalls[_hash].maturity);
        
        //send back all of the collateral to the seller
        dt.transfer(allCalls[_hash].debtor, satUnits * allCalls[_hash].amount, false);
        
        //remove the option contract from the blockchian
        remove(allCalls[_hash].holder, locate(allCalls[_hash].holder, _hash));
        remove(allCalls[_hash].debtor, locate(allCalls[_hash].debtor, _hash));
        delete allCalls[_hash];
    }
    
    function reclaimIndex(uint _index) public {
        DappToken dt = DappToken(dappAddress);
        require(_index < contracts[msg.sender].length);
        bytes32 hash = contracts[msg.sender][_index];
        require(msg.sender == allCalls[hash].debtor && block.number > allCalls[hash].maturity);
        
        //send back all of the collateral to the seller
        dt.transfer(allCalls[hash].debtor, satUnits * allCalls[hash].amount, false);

        //remove the option contract from the blockchian
        remove(allCalls[hash].holder, locate(allCalls[hash].holder, hash));
        remove(allCalls[hash].debtor, locate(allCalls[hash].debtor, hash));
        delete allCalls[hash];
    }
    
    function locate(address _addr, bytes32 _hash) internal view returns(uint){
        //optimise in the future to be O(log(n))
        for (uint i = 0; i < contracts[_addr].length; i++){
            if (contracts[_addr][i] == _hash)
                return i;
        }
    }
    
    //remove a specific index from a users personal options array
    function remove(address _addr, uint _index) internal {
        for (uint i = _index; i<contracts[_addr].length-1; i++){
            contracts[_addr][i] = contracts[_addr][i+1];
        }
        delete contracts[_addr][contracts[_addr].length-1];
        contracts[_addr].length--;
    }
    
    function myContracts() public view returns(bytes32[] memory){
        return contracts[msg.sender];
    }
    
    function contractAtIndex(uint _index) public view returns(bytes32){
        require(_index < contracts[msg.sender].length);
        return contracts[msg.sender][_index];
    }
    
    function contractBalance() public view returns(uint){
        return address(this).balance;
    }
    
    function oracleVal() public view returns(uint){
        oracle orc = oracle(oracleAddress);
        return orc.get();
    }
    
}