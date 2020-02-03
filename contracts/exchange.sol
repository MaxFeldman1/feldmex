pragma solidity ^0.5.12;
import "./DappToken.sol";
import "./options.sol";
import "./stablecoin.sol";

/*
    To-Do
    .) add a fouth parameter uint _limitPrice to marketSell and marketBuy to ensure price of contracts
*/

contract exchange{
    //denominated in Underlying Token
    mapping(address => uint) public claimedToken;
    
    //denominated in the unit of account
    mapping(address => uint) public claimedStable;

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
        bool buy;
        bool call;
    }
    
    event offerPosted(
        bytes32 hash
    );

    //-----------mappings for marketplace functionality--------------
    //maturity => strike => headNode.name [longCall, shortCall, longPut, shortPut]
    mapping(uint => mapping(uint => bytes32[4])) public listHeads;
    
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
    address stablecoinAddress;
    address optionsAddress;
    //incrementing identifier for each order
    uint public totalOrders;
    //number of satoshis in one DappToken _fullUnit
    uint satUnits;
    uint scUnits;

    uint public testing;
    
    constructor (address _dappAddress, address _stablecoinAddress, address _optionsAddress) public{
        dappAddress = _dappAddress;
        optionsAddress = _optionsAddress;
        stablecoinAddress = _stablecoinAddress;
        totalOrders = 1;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
        dt.approve(optionsAddress, 2**255, false);
        stablecoin sc = stablecoin(stablecoinAddress);
        scUnits = sc.scUnits();
        sc.approve(optionsAddress, 2**255, false);
    }
    
    function postCollateral(uint _amount, bool _fullUnit, uint _amountStable, bool _fullUnitStable) public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        if (_amount != 0){
            if (dt.transferFrom(msg.sender, address(this), _amount, _fullUnit)){
                claimedToken[msg.sender]+=_amount * (_fullUnit ? satUnits : 1);
                if (_amountStable == 0) return true;
            }
        }
        stablecoin sc = stablecoin(stablecoinAddress);
        if (sc.transferFrom(msg.sender, address(this), _amountStable, _fullUnit)){
            claimedStable[msg.sender]+=_amountStable *(_fullUnitStable ? scUnits : 1);
        }
        return false;
    }
    
    function claimedCollateral(address _addr, bool _fullUnit) public view returns(uint){
        return claimedToken[_addr]/(_fullUnit ? satUnits : 1);
    }
    
    function withdrawCollateral(uint _value, bool _fullUnit) public returns(bool success){
        DappToken dt = DappToken(dappAddress);
        require(claimedToken[msg.sender]/(_fullUnit ? satUnits : 1) >= _value);
        return dt.transfer(msg.sender, _value, _fullUnit);
    }
    
    function withdrawMaxCollateral() public returns(bool success){
        uint val = claimedToken[msg.sender];
        require(val > 0);
        DappToken dt = DappToken(dappAddress);
        claimedToken[msg.sender] = 0;
        return dt.transfer(msg.sender, val, false);
    }
    
    //------The following set of functions relate to management of the marketplace
    
    //the output of this function for each offer is its identifier in the offers mapping
    function orderHasher(Offer memory _offer) internal view returns(bytes32){
        return keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.buy, _offer.call, now));
    }
    
    //the output of this function for each linkedNode is its identifier in the linkedNodes mapping
    function nodeHasher(bytes32 _offerHash) internal returns(bytes32){
        totalOrders++;
        return keccak256(abi.encodePacked(_offerHash, now, totalOrders));
    }
    
    
    //---------------------The following set of functions relates to buying and selling of contracts---------------------

    //consolodates functionality for buying and selling calls and puts into one function
    function postOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call) public {
        //require collateral and deduct collateral from balance
        uint index;
        if (_buy && _call){
            require(claimedToken[msg.sender] >= _price*_amount);
            claimedToken[msg.sender] -= _price * _amount;
            index = 0;
        }
        else if (!_buy && _call){
            require(claimedToken[msg.sender] >= satUnits*_amount);
            claimedToken[msg.sender] -= satUnits * _amount;
            index = 1;
        }
        else if (_buy && !_call){
            require(claimedStable[msg.sender] >= _price*_amount);
            claimedStable[msg.sender] -= _price * _amount;
            index = 2;
        }
        else {
            require(claimedStable[msg.sender] >= scUnits*_amount*_strike);
            claimedStable[msg.sender] -= scUnits * _amount * _strike;
            index = 3;
        }
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, _buy, _call);
        //buyOffer identifier
        bytes32 hash = orderHasher(offer);
        //linkedNode identifier
        bytes32 name = nodeHasher(hash);
        offers[hash] = offer;
        //set current node to the head node
        linkedNode memory currentNode = linkedNodes[listHeads[_maturity][_strike][index]];
        if ((_buy && offers[currentNode.hash].price <= _price) || (!_buy && (offers[currentNode.hash].price >= _price || offers[currentNode.hash].price == 0))){
            linkedNodes[name] = linkedNode(hash, name, currentNode.name, 0);
            if (offers[currentNode.hash].price != 0){
                linkedNodes[listHeads[_maturity][_strike][index]].previous = name;
            }
            listHeads[_maturity][_strike][index] = name;
            emit offerPosted(hash);
            return;
        }
        linkedNode memory previousNode;
        while (currentNode.name != 0){
            previousNode = currentNode;
            currentNode = linkedNodes[currentNode.next];
            if ((_buy && offers[currentNode.hash].price <= _price) || (!_buy && offers[currentNode.hash].price >= _price)){
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

    //allows for users to post Orders with less transaction fees by giving another order as refrence to find their orders position from
    function insertOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call, bytes32 _name) public {
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].strike == _strike);
        uint index;
        if (_buy && _call){
            require(claimedToken[msg.sender] >= _price*_amount);
            require(offers[linkedNodes[_name].hash].buy && offers[linkedNodes[_name].hash].call);
            claimedToken[msg.sender] -= _price * _amount;
            index = 0;
        }
        else if (!_buy && _call){
            require(claimedToken[msg.sender] >= satUnits*_amount);
            require(!offers[linkedNodes[_name].hash].buy && offers[linkedNodes[_name].hash].call);
            claimedToken[msg.sender] -= satUnits * _amount;
            index = 1;
        }
        else if (_buy && !_call){
            require(claimedStable[msg.sender] >= _price*_amount);
            require(offers[linkedNodes[_name].hash].buy && !offers[linkedNodes[_name].hash].call);
            claimedStable[msg.sender] -= _price * _amount;
            index = 2;
        }
        else {
            require(claimedStable[msg.sender] >= scUnits*_amount*_strike);
            require(!offers[linkedNodes[_name].hash].buy && !offers[linkedNodes[_name].hash].call);
            claimedStable[msg.sender] -= scUnits * _amount * _strike;
            index = 3;
        }

        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, _buy, _call);
        //buyOffer identifier
        bytes32 hash = orderHasher(offer);
        //linkedNode identifier
        bytes32 name = nodeHasher(hash);
        //if we need to traverse down the list further away from the list head
        linkedNode memory currentNode = linkedNodes[_name];
        if ((_buy &&  offers[currentNode.hash].price >= _price) || (!_buy  && offers[currentNode.hash].price <= _price)){
            linkedNode memory previousNode;
            while (currentNode.name != 0){
                previousNode = currentNode;
                currentNode = linkedNodes[currentNode.next];
                if ((_buy && offers[currentNode.hash].price < _price) || (!_buy && offers[currentNode.hash].price > _price)){
                    break;
                }
            }
            offers[hash] = offer;
            //if this is the last node
            if (currentNode.name == 0){
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
        //here we traverse up towards the list head
        else {
            /*  curent node should == linkedNodes[currentNode.next]
                do not be confused by the fact that is lags behind in the loop and == the value of currentNode in the previous iteration
            */
            linkedNode memory nextNode;
            while (currentNode.name != 0){
                nextNode = currentNode;
                currentNode = linkedNodes[currentNode.previous];
                if ((_buy && offers[currentNode.hash].price >= _price) || (!_buy && offers[currentNode.hash].price <= _price)){
                    break;
                }
            }
            offers[hash] = offer;
            //if this is the list head
            if (currentNode.name == 0){
                //nextNode is the head befoe execution of this local scope
                linkedNodes[name] = linkedNode(hash, name, nextNode.name, 0);
                linkedNodes[nextNode.name].previous = name;
                listHeads[_maturity][_strike][index] = name;
                emit offerPosted(hash);
                return; 
            }
            //falls somewhere in the middle of the list
            else {
                linkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                linkedNodes[nextNode.name].previous = name;
                linkedNodes[currentNode.name].next = name;
                emit offerPosted(hash);
                return;
            }
        }
    }

    function cancelOrder(bytes32 _name) public {
        linkedNode memory node = linkedNodes[_name];
        require(msg.sender == offers[node.hash].offerer);
        Offer memory offer = offers[node.hash];
        uint index;
        if (offer.buy && offer.call)
            index = 0;
        else if (!offer.buy && offer.call)
            index = 1;
        else if (offer.buy)
            index = 2;
        else
            index = 3;
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.previous == 0){
            delete listHeads[offers[node.hash].maturity][offers[node.hash].strike][index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offers[node.hash].maturity][offers[node.hash].strike][index] = node.next;
        }
        delete linkedNodes[_name];
        delete offers[node.hash];
        if (index == 0)
            claimedToken[msg.sender] += offer.price * offer.amount;
        else if (index == 1)
            claimedToken[msg.sender] += satUnits * offer.amount;
        else if (index == 2)
            claimedStable[msg.sender] += offer.price * offer.amount;
        else
            claimedStable[msg.sender] += scUnits * offer.strike * offer.amount;
    }
    
    function takeBuyOffer(address payable _seller, bytes32 _name) internal returns(bool success){
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(offer.buy && _seller != offer.offerer);
        uint8 index = (offer.call? 0 : 2);
        //make sure the seller has sufficient collateral posted
        if (offer.call){
            require(claimedToken[_seller] >= satUnits * offer.amount);
            claimedToken[_seller] -= satUnits * offer.amount;
        }
        else{
            require(claimedStable[_seller] >= scUnits * offer.amount * offer.strike);
            claimedStable[_seller] -= scUnits * offer.amount * offer.strike;
        }

        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][index] = node.next;
        }
        
        //now we make the trade happen
        options optionsContract = options(optionsAddress);
        //dt.approve(optionsAddress, satUnits, false);
        //give the seller the amount paid
        if (offer.call){
            claimedToken[_seller] += offer.price * offer.amount;

            (bool safe, uint transferAmount) = optionsContract.mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount);
            assert(safe);
            //redeem the seller collateral that was not required
            claimedToken[_seller] += (satUnits * offer.amount) - transferAmount;
            //assert(optionsContract.mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount));
        }
        else{
            claimedStable[_seller] += offer.price * offer.amount;

            (bool safe, uint transferAmount) = optionsContract.mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount);
            assert(safe);
            //redeem seller collateral that was not required
            claimedStable[_seller] += (scUnits * offer.amount * offer.strike) - transferAmount;
            //assert(optionsContract.mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount));
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        return true;
    }

    function takeSellOffer(address payable _buyer, bytes32 _name) internal returns(bool success){
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(!offer.buy && _buyer != offer.offerer);
        uint8 index = (offer.call? 1 : 3);
        //make sure the seller has sufficient collateral posted
        if (offer.call){
            require(claimedToken[_buyer] >= offer.price * offer.amount);
            claimedToken[_buyer] -= offer.price * offer.amount;
        }
        else{
            require(claimedStable[_buyer] >= offer.price * offer.amount);
            claimedStable[_buyer] -= offer.price * offer.amount;
        }

        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][index] = node.next;
        }
        
        //now we make the trade happen
        options optionsContract = options(optionsAddress);
        //give the seller the amount paid
        if (offer.call){
            claimedToken[offer.offerer] += offer.price * offer.amount;

            (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount);
            assert(safe);
            //redeem the seller collateral that was not required
            claimedToken[offer.offerer] += (satUnits * offer.amount) - transferAmount;
            //assert(optionsContract.mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount));
        }
        else{
            claimedStable[offer.offerer] += offer.price * offer.amount;

            (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount);
            assert(safe);
            //redeem the seller collateral that was not required
            claimedStable[offer.offerer] += (scUnits * offer.amount * offer.strike) - transferAmount;
            //assert(optionsContract.mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount));
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        return true;
    }

    function marketSell(uint _maturity, uint _strike, uint _amount, bool _call) public {
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0 && msg.sender != offer.offerer);
        if (_call) require(claimedToken[msg.sender] >= satUnits * _amount);
        else require(claimedStable[msg.sender] >= scUnits * _amount * _strike);
        //in each iteration we mint one contract
        while (_amount > 0 && node.name != 0){
            if (offer.amount > _amount){
                options optionsContract = options(optionsAddress);
                if (_call){
                    claimedToken[msg.sender] -= satUnits * _amount;

                    (bool safe, uint transferAmount) = optionsContract.mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedToken[msg.sender] += (satUnits * _amount) - transferAmount;
                    //assert(optionsContract.mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount));
                    claimedToken[msg.sender] += offer.price * _amount;

                }
                else {
                    claimedStable[msg.sender] -= scUnits * _amount * _strike;

                    (bool safe, uint transferAmount) = optionsContract.mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedStable[msg.sender] += (scUnits * _amount * _strike) - transferAmount;
                    //assert(optionsContract.mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount));
                    claimedStable[msg.sender] += offer.price * _amount;
                }
                offers[node.hash].amount -= _amount;
                break;
            }
            _amount-=offer.amount;
            if (!takeBuyOffer(msg.sender, node.name)) break;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][index]];
            offer = offers[node.hash];
        }
    }

    function marketBuy(uint _maturity, uint _strike, uint _amount, bool _call) public {
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0 && msg.sender != offer.offerer);
        while (_amount > 0 && node.name != 0 && claimedToken[msg.sender] >= offer.price){
            if (offer.amount > _amount){
                options optionsContract = options(optionsAddress);
                if (_call){
                    require(claimedToken[msg.sender] >= offer.price * _amount);
                    claimedToken[msg.sender] -= offer.price * _amount;
                    
                    (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedToken[offer.offerer] += (satUnits * _amount) - transferAmount;
                    //assert(optionsContract.mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount));
                    claimedToken[offer.offerer] += offer.price * _amount;
                }
                else {
                    require(claimedStable[msg.sender] >= offer.price * _amount);
                    claimedStable[msg.sender] -= offer.price * _amount;

                    (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount);
                    assert(safe);
                    //redeem the seller collateral that was not used
                    claimedStable[offer.offerer] += (scUnits * _amount * _strike) - transferAmount;
                    //assert(optionsContract.mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount));
                    claimedStable[offer.offerer] += offer.price * _amount;
                }
                offers[node.hash].amount -= _amount;
                break;
            }
            _amount-=offer.amount;
            if (!takeSellOffer(msg.sender, node.name)) break;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][index]];
            offer = offers[node.hash];
        }
    }
}