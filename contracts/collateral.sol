pragma solidity ^0.5.12;
import "./DappToken.sol";
import "./calls.sol";
import "./stablecoin.sol";

/*
    To-Do
    .) add a fouth parameter uint _limitPrice to marketSell and marketBuy to ensure price of contracts
*/

contract collateral{
    //total amount of locked collateral for each address
    mapping(address => uint) public claimed;
    
    //stores price and hash of (maturity, stike, price)
    struct linkedNode{
        //offers[hash] is the offer
        bytes32 hash;
        //this == linkedNodes[name]
        bytes32 name;
        bytes32 next;
        bytes32 previous;
    }

    struct Offer{
        address payable offerer;
        uint maturity;
        uint strike;
        uint price;
        uint amount;
        //if true this is a buy offer if false it is a sell offer
        bool buy;
    }
    
    event offerPosted(
        bytes32 hash
    );

    //-----------mappings for marketplace functionality--------------
    //maturity => strike => headNode.name
    mapping(uint => mapping(uint => bytes32[2])) public listHeads;
    
    //holds all nodes
    mapping (bytes32 => linkedNode) public linkedNodes;
    
    /*
        Note all linkedNodes correspond to a buyOffer
        The offers[linkedNodes[name].hash] links to a buyOffer
    */
    
    //holds all offers
    mapping(bytes32 => Offer) public offers;
    //---------------END---------------------------------------------
    
    //address of outside token contract
    address dappAddress;
    address callsAddress;
    //incrementing identifier for each order
    uint public totalOrders;
    //number of satoshis in one DappToken _fullUnit
    uint satUnits;

    uint public testing;
    
    constructor (address _dappAddress, address _callsAddress) public{
        dappAddress = _dappAddress;
        callsAddress = _callsAddress;
        totalOrders = 1;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
        dt.approve(callsAddress, 2**255, false);
    }
    
    function postCollateral(uint _amount, bool _fullUnit) public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        if (dt.transferFrom(msg.sender, address(this), _amount, _fullUnit)){
            claimed[msg.sender]+=_amount*(_fullUnit ? satUnits : 1);
            return true;
        }
        return false;
    }
    
    function claimedCollateral(address _addr, bool _fullUnit) public view returns(uint){
        return claimed[_addr]/(_fullUnit ? satUnits : 1);
    }
    
    function withdrawCollateral(uint _value, bool _fullUnit) public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        require(claimed[msg.sender]/(_fullUnit ? satUnits : 1) >= _value);
        return dt.transfer(msg.sender, _value, _fullUnit);
    }
    
    function withdrawMaxCollateral() public returns(bool success){
        uint val = claimed[msg.sender];
        require(val > 0);
        DappToken dt = DappToken(dappAddress);
        claimed[msg.sender] = 0;
        return dt.transfer(msg.sender, val, false);
    }
    
    //------The following set of functions relate to management of the marketplace
    
    //the output of this function for each offer is its identifier in the offers mapping
    function orderHasher(Offer memory _offer) internal view returns(bytes32){
        return keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.buy, now));
    }
    
    //the output of this function for each linkedNode is its identifier in the linkedNodes mapping
    function nodeHasher(bytes32 _offerHash) internal returns(bytes32){
        totalOrders++;
        return keccak256(abi.encodePacked(_offerHash, now, totalOrders));
    }
    
    
    //---------------------The following set of functions relates to buying and selling of contracts---------------------

    function postBuy(uint _maturity, uint _strike, uint _price, uint _amount) public {
        //require collateral
        require(claimed[msg.sender] >= _price * _amount);
        claimed[msg.sender] -= _price * _amount;
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, true);
        //buyOffer identifier
        bytes32 hash = orderHasher(offer);
        //linkedNode identifier
        bytes32 name = nodeHasher(hash);
        offers[hash] = offer;
        //set current node to the head node
        linkedNode memory currentNode = linkedNodes[listHeads[_maturity][_strike][0]];
        if (offers[currentNode.hash].price <= _price){
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, 0);
            if (offers[currentNode.hash].price != 0){
                linkedNodes[listHeads[_maturity][_strike][0]].previous = name;
            }
            listHeads[_maturity][_strike][0] = name;
            emit offerPosted(hash);
            return;
        }
        linkedNode memory previousNode;
        while (currentNode.name != 0){
            previousNode = currentNode;
            currentNode = linkedNodes[currentNode.next];
            if (offers[currentNode.hash].price <= _price){
                break;
            }
        }
        //if previous node is null this is the head node
        if (offers[previousNode.hash].price == 0){
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, 0);
            linkedNodes[currentNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
        //if this is the last node
        else if (currentNode.name == 0){
            linkedNodes[name] = linkedNode(hash, name, 0, previousNode.name);
            linkedNodes[currentNode.name].previous = name;
            linkedNodes[previousNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
        //it falls somewhere in the middle of the chain
        else{
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
            linkedNodes[currentNode.name].previous = name;
            linkedNodes[previousNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
    }
    
    function cancelBuy(bytes32 _name) public {
        linkedNode memory node = linkedNodes[_name];
        require(msg.sender == offers[node.hash].offerer && offers[node.hash].buy);
        claimed[msg.sender] += offers[node.hash].price * offers[node.hash].amount;
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
            testing = 1;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.previous == 0){
            delete listHeads[offers[node.hash].maturity][offers[node.hash].strike][0];
            testing = 2;
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
            testing = 3;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offers[node.hash].maturity][offers[node.hash].strike][0] = node.next;
            testing = 4;
        }
        delete linkedNodes[_name];
        delete offers[node.hash];
    }
    
    function takeBuyOffer(address payable _seller, bytes32 _name) internal {
        DappToken dt = DappToken(dappAddress);
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        testing = offer.maturity;
        require(claimed[_seller] >= satUnits * offer.amount && _seller != offer.offerer && offer.buy);
        claimed[_seller] -= satUnits * offer.amount;

        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][0];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][0] = node.next;
        }
        
        //now we make the trade happen
        calls callContract = calls(callsAddress);
        //dt.approve(callsAddress, satUnits, false);
        //give the seller the amount paid
        dt.transfer(_seller, offer.price, false);
        assert(callContract.mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount));
        
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
    }

    function marketSell(uint _maturity, uint _strike, uint _amount) public {
        DappToken dt = DappToken(dappAddress);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][0]];
        Offer memory offer = offers[node.hash];
        require(claimed[msg.sender] >= satUnits * _amount && listHeads[_maturity][_strike][0] != 0 && msg.sender != offer.offerer);
        //in each iteration we mint one contract
        while (_amount > 0 && node.name != 0){
            calls callContract = calls(callsAddress);
            if (offer.amount > _amount){
                require(callContract.mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount));
                claimed[msg.sender] -= satUnits * _amount;
                offers[node.hash].amount -= _amount;
                assert(dt.transfer(msg.sender, offer.price * _amount, false));
                break;
            }
            _amount-=offer.amount;
            takeBuyOffer(msg.sender, node.name);
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][0]];
            offer = offers[node.hash];
        }
    }

    function postSell(uint _maturity, uint _strike, uint _price, uint _amount) public {
        //require collateral
        require(claimed[msg.sender] >= satUnits * _amount && _price > 0);
        claimed[msg.sender] -= satUnits * _amount;
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, false);
        //sellOffer identifier
        bytes32 hash = orderHasher(offer);
        //linkedNode identifier
        bytes32 name = nodeHasher(hash);
        offers[hash] = offer;
        //set current node to the head node
        linkedNode memory currentNode = linkedNodes[listHeads[_maturity][_strike][1]];
        if (offers[currentNode.hash].price==0 || offers[currentNode.hash].price >= _price){
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, 0);
            if (offers[currentNode.hash].price != 0){
                linkedNodes[listHeads[_maturity][_strike][1]].previous = name;
            }
            listHeads[_maturity][_strike][1] = name;
            emit offerPosted(hash);
            return;
        }
        linkedNode memory previousNode;
        while (currentNode.name != 0){
            previousNode = currentNode;
            currentNode = linkedNodes[currentNode.next];
            if (offers[currentNode.hash].price >= _price){
                break;
            }
        }
        //if previous node is null this is the head node
        if (offers[previousNode.hash].price == 0){
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, 0);
            linkedNodes[currentNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
        //if this is the last node
        else if (currentNode.name == 0){
            linkedNodes[name] = linkedNode(hash, name, 0, previousNode.name);
            linkedNodes[currentNode.name].previous = name;
            linkedNodes[previousNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
        //it falls somewhere in the middle of the chain
        else{
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
            linkedNodes[currentNode.name].previous = name;
            linkedNodes[previousNode.name].next = name;
            emit offerPosted(hash);
            return;
        }
    }

    function cancelSell(bytes32 _name) public {
        linkedNode memory node = linkedNodes[_name];
        require(msg.sender == offers[node.hash].offerer && !offers[node.hash].buy);
        claimed[msg.sender] += satUnits * offers[node.hash].amount;
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.previous == 0){
            delete listHeads[offers[node.hash].maturity][offers[node.hash].strike][1];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offers[node.hash].maturity][offers[node.hash].strike][1] = node.next;
        }
        delete linkedNodes[_name];
        delete offers[node.hash];  
    }

    function takeSellOffer(address payable _buyer, bytes32 _name) internal {
        DappToken dt = DappToken(dappAddress);
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(claimed[_buyer] >= offer.price * offer.amount && _buyer != offer.offerer && !offer.buy);
        claimed[_buyer] -= offer.price * offer.amount;
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][1];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][1] = node.next;
        }
        
        //now we make the trade happen
        calls callContract = calls(callsAddress);
        //give the seller the amount paid
        dt.transfer(offer.offerer, offer.price, false);
        assert(callContract.mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount));
        
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
    }

    function marketBuy(uint _maturity, uint _strike, uint _amount) public {
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][1]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][1] != 0 && msg.sender != offer.offerer);
        //in each iteration we mint one contracts
        while (_amount > 0 && node.name != 0 && claimed[msg.sender] >= offer.price){
            calls callContract = calls(callsAddress);
            if (offer.amount > _amount){
                require(claimed[msg.sender] >= offer.price * _amount);
                claimed[msg.sender] -= offer.price * _amount;
                assert(callContract.mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount));
                offers[node.hash].amount -= _amount;
                break;
            }
            _amount-=offer.amount;
            takeSellOffer(msg.sender, node.name);
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][1]];
            offer = offers[node.hash];
        }
    }
}