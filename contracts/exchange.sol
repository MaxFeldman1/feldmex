pragma solidity ^0.5.12;
import "./DappToken.sol";
import "./options.sol";
import "./stablecoin.sol";


contract exchange{
    //denominated in Underlying Token
    mapping(address => uint) public claimedToken;
    
    //denominated in the unit of account
    mapping(address => uint) public claimedStable;

    //stores price and hash of (maturity, stike, price)
    struct linkedNode{
        //offers[hash] => offer
        bytes32 hash;
        //linkedNodes[this.name] => this
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

    event hit(
        uint oof
    );

    /*
        listHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing offers at the top near the head
    */
    //maturity => strike => headNode.name [longCall, shortCall, longPut, shortPut]
    mapping(uint => mapping(uint => bytes32[4])) public listHeads;
    
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) public linkedNodes;

    /*
        Note all linkedNodes correspond to a buyOffer
        The offers[linkedNodes[name].hash] links to a buyOffer
    */
    
    //holds all offers
    mapping(bytes32 => Offer) public offers;
    
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address dappAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address stablecoinAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address payable optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint public totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;

    //variable occasionally used for testing purposes should not be present in production
    uint public testing;
    
    /*  
        @Description: initialise globals and preform initial processes with the token and stablecoin contracts

        @param address _dappAddress: address that shall be assigned to dappAddress
        @param address _stablecoinAddress: address that shall be assigned to stablecoinAddress
        @param address _optionsAddress: address that shall be assigned to optionsAddress
    */
    constructor (address _dappAddress, address _stablecoinAddress, address payable _optionsAddress) public{
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
    
    /*
        @Description: deposit funds in this contract, funds tracked by the claimedToken and claimedStable mappings

        @param uint _amount: the amount of the token to be deposited
        @param boolean _fullUnit: if true _amount is full units of the token if false _amount is the samllest unit of the token
        @param uint _amountStable: the amount of the stablecoin to be deposited
        @param boolean _fullUnitStable: if true _amountStable is full units of the stablecoin if false _amountStable is the smallest unit of the stablecoin

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(uint _amount, bool _fullUnit, uint _amountStable, bool _fullUnitStable) public returns(bool success){
        if (_amount != 0){
            DappToken dt = DappToken(dappAddress);
            if (dt.transferFrom(msg.sender, address(this), _amount, _fullUnit))
                claimedToken[msg.sender]+=_amount * (_fullUnit ? satUnits : 1);
            else 
                return false;
        }
        if (_amountStable != 0){
            stablecoin sc = stablecoin(stablecoinAddress);
            if (sc.transferFrom(msg.sender, address(this), _amountStable, _fullUnitStable))
                claimedStable[msg.sender]+=_amountStable *(_fullUnitStable ? scUnits : 1);
            else 
                return false;
        }
        return true;
    }
    
    /*
        @Description: send back all funds tracked in the claimedToken and claimedStable mappings of the caller to the callers address

        @param bool _token: if true withdraw the tokens recorded in claimedToken if false withdraw the stablecoins stored in claimedStable

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds(bool _token) public returns(bool success){
        if (_token){
            uint val = claimedToken[msg.sender];
            require(val > 0);
            DappToken dt = DappToken(dappAddress);
            claimedToken[msg.sender] = 0;
            return dt.transfer(msg.sender, val, false);
        }
        else {
            uint val = claimedStable[msg.sender];
            require(val > 0);
            stablecoin sc = stablecoin(stablecoinAddress);
            claimedStable[msg.sender] = 0;
            return sc.transfer(msg.sender, val, false);
        }

    }
    
    //------The following set of functions relate to management of the marketplace
    
    /*
        @Description: creates a hash of a given order by which it will it will be identified
            offers[returnValue] == _offer
        @return bytes32: key in offers mapping
    */
    function orderHasher(Offer memory _offer) internal view returns(bytes32){
        return keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.buy, _offer.call, now));
    }
    
    /*
        @Description: returns a unique identifier by which the node corresponding to each order may be accesse
            linkedNodes[returnValue].hash == _offerHash
        @return bytes32: key in linkedNodes mapping
    */
    function nodeHasher(bytes32 _offerHash) internal returns(bytes32){
        totalOrders++;
        return keccak256(abi.encodePacked(_offerHash, now, totalOrders));
    }
    
    
    /*
        @Description: creates an order and posts it in one of the 4 linked lists depending on if it is a buy or sell order and if it is for calls or puts

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order
    */
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
    /*
        @Description: this is the same as post order though it allows for gas to be saved by searching for the orders location in relation to another order
            this function is best called by passing in the name of an order that is directly next to the future location of your order
        
        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order 
        @param bytes32 _name: the name identifier of the order from which to search for the location to insert this order
    */
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

    /*
        @Description: removes the order with name identifier _name, prevents said order from being filled or taken

        @param bytes32: the identifier of the node which stores the order to cancel, offerToCancel == offers[linkedNodes[_name].hash]
    */
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
    

    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name

        @param address payable _seller: the seller that is taking the buy offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == offers[linkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer(address payable _seller, bytes32 _name) internal returns(bool success){

        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(offer.buy && _seller != offer.offerer);
        uint8 index = (offer.call? 0 : 2);
        //make sure the seller has sufficient collateral posted
        options optionsContract = options(optionsAddress);
        uint expectedAmt;
        if (offer.call){
            expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            require(claimedToken[_seller] >= expectedAmt);
            claimedToken[_seller] -= expectedAmt;
        }
        else{
            expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            require(claimedStable[_seller] >= expectedAmt);
            claimedStable[_seller] -= expectedAmt;
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
        if (offer.call){
            (bool safe, uint transferAmt) = optionsContract.mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            assert(safe);
            claimedToken[_seller] += offer.price * offer.amount;
            //redeem seller collateral that was not required
            claimedToken[_seller] += expectedAmt-transferAmt;
        }
        else{            
            (bool safe, uint transferAmt) = optionsContract.mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            assert(safe);
            claimedStable[_seller] += offer.price * offer.amount;
            //redeem seller collateral that was not required
            claimedStable[_seller] += expectedAmt - transferAmt;
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        return true;
    }

    /*
        @Description: handles logistics of the buyer accepting a sell order with the identifier _name

        @param address payable _buyer: the buyer that is taking the sell offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == offers[linkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
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
            (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.amount*satUnits);
            assert(safe);
            claimedToken[offer.offerer] += offer.price * offer.amount;
            //redeem the seller collateral that was not required
            claimedToken[offer.offerer] += (satUnits * offer.amount) - transferAmount;
        }
        else{

            (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.amount*scUnits*offer.strike);
            assert(safe);
            claimedStable[offer.offerer] += offer.price * offer.amount;
            //redeem the seller collateral that was not required
            claimedStable[offer.offerer] += (scUnits * offer.amount * offer.strike) - transferAmount;
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        return true;
    }

    /*
        @Description: Caller of the function takes the best buy offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 
    */
    function marketSell(uint _maturity, uint _strike, uint _limitPrice, uint _amount, bool _call) public {
        if (!_call){
            testing++;
        }
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        //require(listHeads[_maturity][_strike][index] != 0 && msg.sender != offer.offerer);
        //in each iteration we mint one contract
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice){
            if (offer.amount > _amount){
                offers[node.hash].amount -= _amount;
                options optionsContract = options(optionsAddress);
                if (_call){
                    uint expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(_amount), offer.strike);
                    require(claimedToken[msg.sender] >= expectedAmt);
                    claimedToken[msg.sender] -= expectedAmt;
                    (bool safe, uint transferAmount) = optionsContract.mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedToken[msg.sender] += expectedAmt - transferAmount;
                    claimedToken[msg.sender] += offer.price * _amount;

                }
                else {
                    uint expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(_amount), offer.strike);
                    require(claimedStable[msg.sender] >= expectedAmt);
                    claimedStable[msg.sender] -= expectedAmt;
                    (bool safe, uint transferAmount) = optionsContract.mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedStable[msg.sender] += expectedAmt - transferAmount;
                    claimedStable[msg.sender] += offer.price * _amount;
                }
                break;
            }
            _amount-=offer.amount;
            if (!takeBuyOffer(msg.sender, node.name)) {break;}
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][index]];
            offer = offers[node.hash];
        }
    }

    /*
        @Description: Caller of the function takes the best sell offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: highest price to buy at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 
    */
    function marketBuy(uint _maturity, uint _strike, uint _limitPrice, uint _amount, bool _call) public {
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0 && msg.sender != offer.offerer);
        while (_amount > 0 && node.name != 0 && claimedToken[msg.sender] >= offer.price && offer.price <= _limitPrice){
            if (offer.amount > _amount){
                offers[node.hash].amount -= _amount;
                options optionsContract = options(optionsAddress);
                if (_call){
                    require(claimedToken[msg.sender] >= offer.price * _amount);
                    claimedToken[msg.sender] -= offer.price * _amount;
                    
                    (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, _amount*satUnits);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedToken[offer.offerer] += (satUnits * _amount) - transferAmount;
                    claimedToken[offer.offerer] += offer.price * _amount;
                }
                else {
                    require(claimedStable[msg.sender] >= offer.price * _amount);
                    claimedStable[msg.sender] -= offer.price * _amount;
                    uint limit = _amount*scUnits*offer.strike;
                    (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, limit);
                    assert(safe);
                    //redeem the seller collateral that was not used
                    claimedStable[offer.offerer] += (scUnits * _amount * _strike) - transferAmount;
                    claimedStable[offer.offerer] += offer.price * _amount;
                }
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