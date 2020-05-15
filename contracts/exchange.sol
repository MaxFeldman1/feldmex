pragma solidity ^0.5.12;
import "./DappToken.sol";
import "./options.sol";
import "./stablecoin.sol";


contract exchange{
    //denominated in Underlying Token satUnits
    mapping(address => uint) claimedToken;
    
    //denominated in the unit of account scUnits
    mapping(address => uint) claimedStable;

    //------------functions to view balances----------------
    function viewClaimed(bool _token) public view returns(uint){return _token? claimedToken[msg.sender] : claimedStable[msg.sender];}
    //function viewClaimedToken() public view returns(uint){return claimedToken[msg.sender];}

    //function viewClaimedStable() public view returns(uint){return claimedStable[msg.sender];}

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
        address offerer;
        uint maturity;
        uint strike;
        uint price;
        uint amount;
        bool buy;
        bool call;
    }
    
    event offerPosted(
        bytes32 name,
        uint maturity,
        uint strike,
        uint price,
        uint amount,
        uint index
    );

    event offerCalceled(
        bytes32 name
    );

    event offerAccepted(
        bytes32 name,
        uint amount
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
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
    //variable occasionally used for testing purposes should not be present in production
    //uint public testing;
    
    /*  
        @Description: initialise globals and preform initial processes with the token and stablecoin contracts

        @param address _dappAddress: address that shall be assigned to dappAddress
        @param address _stablecoinAddress: address that shall be assigned to stablecoinAddress
        @param address _optionsAddress: address that shall be assigned to optionsAddress
    */
    constructor (address _dappAddress, address _stablecoinAddress, address _optionsAddress) public{
        dappAddress = _dappAddress;
        optionsAddress = _optionsAddress;
        stablecoinAddress = _stablecoinAddress;
        DappToken dt = DappToken(dappAddress);
        satUnits = dt.satUnits();
        dt.approve(optionsAddress, 2**255);
        stablecoin sc = stablecoin(stablecoinAddress);
        scUnits = sc.scUnits();
        sc.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the claimedToken and claimedStable mappings

        @param uint _amount: the amount of the token to be deposited
        @param boolean _fullUnit: if true _amount is full units of the token if false _amount is the samllest unit of the token
        @param uint _amountStable: the amount of the stablecoin to be deposited
        @param boolean _fullUnitStable: if true _amountStable is full units of the stablecoin if false _amountStable is the smallest unit of the stablecoin

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(uint _amount, uint _amountStable) public returns(bool success){
        if (_amount != 0){
            DappToken dt = DappToken(dappAddress);
            if (dt.transferFrom(msg.sender, address(this), _amount))
                claimedToken[msg.sender]+=_amount;
            else 
                return false;
        }
        if (_amountStable != 0){
            stablecoin sc = stablecoin(stablecoinAddress);
            if (sc.transferFrom(msg.sender, address(this), _amountStable))
                claimedStable[msg.sender]+=_amountStable;
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
            return dt.transfer(msg.sender, val);
        }
        else {
            uint val = claimedStable[msg.sender];
            require(val > 0);
            stablecoin sc = stablecoin(stablecoinAddress);
            claimedStable[msg.sender] = 0;
            return sc.transfer(msg.sender, val);
        }

    }
    
    /*
        @Description: creates two hashes to be keys in the linkedNodes and the offers mapping

        @param Offer _offer: the offer for which to make the identifiers

        @return bytes32 _hash: key in offers mapping
        @return bytes32 _name: key in linkedNodes mapping
    */
    function hasher(Offer memory _offer) internal returns(bytes32 _hash, bytes32 _name){
        bytes32 ret1 =  keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.buy, _offer.call, totalOrders));
        totalOrders++;
        return (ret1, keccak256(abi.encodePacked(ret1, now, totalOrders)));
    }


    /*
        @Description: creates an order and posts it in one of the 4 linked lists depending on if it is a buy or sell order and if it is for calls or puts
            unless this is the first order of its kind functionality is outsourced to insertOrder

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order
    */
    function postOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call) public {
        require(_maturity != 0 && _price != 0 && _price < (_call? satUnits: scUnits*_strike) && _strike != 0);
        uint8 index = (_buy? 0 : 1) + (_call? 0 : 2);
        if (listHeads[_maturity][_strike][index] != 0) {
            insertOrder(_maturity, _strike, _price, _amount, _buy, _call, listHeads[_maturity][_strike][index]);
            return;
        }
        //only continue execution here if listHead[_maturity][_strike][index] == 0
        if (index == 0){
            require(claimedToken[msg.sender] >= _price*_amount);
            claimedToken[msg.sender] -= _price * _amount;
        }
        else if (index == 1){
            require(claimedToken[msg.sender] >= _amount * (satUnits - _price));
            claimedToken[msg.sender] -= _amount * (satUnits - _price);
        }
        else if (index == 2){
            require(claimedStable[msg.sender] >= _price*_amount);
            claimedStable[msg.sender] -= _price * _amount;
        }
        else {
            require(claimedStable[msg.sender] >= _amount * (scUnits * _strike - _price));
            claimedStable[msg.sender] -= _amount * (scUnits * _strike - _price);
        }
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, _buy, _call);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //place order in the mappings
        offers[hash] = offer;
        linkedNodes[name] = linkedNode(hash, name, 0, 0);
        listHeads[_maturity][_strike][index] = name;
        emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
        return;
    }

    //allows for users to post Orders with a smaller gas usage by giving another order as refrence to find their orders position from
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
        //make sure the offer and node corresponding to the name is in the correct list
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].strike == _strike && _maturity != 0 && _price != 0 && _price < (_call? satUnits: scUnits*_strike) && _strike != 0);
        require(offers[linkedNodes[_name].hash].buy  == _buy && offers[linkedNodes[_name].hash].call == _call);
        uint8 index = (_buy? 0 : 1) + (_call? 0 : 2);
        if (index == 0){
            require(claimedToken[msg.sender] >= _price*_amount);
            claimedToken[msg.sender] -= _price * _amount;
        }
        else if (index == 1){
            require(claimedToken[msg.sender] >= _amount * (satUnits - _price));
            claimedToken[msg.sender] -= _amount * (satUnits - _price);
        }
        else if (index == 2){
            require(claimedStable[msg.sender] >= _price*_amount);
            claimedStable[msg.sender] -= _price * _amount;
        }
        else {
            require(claimedStable[msg.sender] >= _amount * (scUnits * _strike - _price));
            claimedStable[msg.sender] -= _amount * (scUnits * _strike - _price);
        }

        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, _buy, _call);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
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
                emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
                return;
            }
            //it falls somewhere in the middle of the chain
            else{
                linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
                linkedNodes[currentNode.name].previous = name;
                linkedNodes[previousNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
                return;
            }

        }
        //here we traverse up towards the list head
        else {
            /*  node node should == linkedNodes[currentNode.next]
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
                emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
                return; 
            }
            //falls somewhere in the middle of the list
            else {
                linkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                linkedNodes[nextNode.name].previous = name;
                linkedNodes[currentNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
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
        emit offerCalceled(_name);
        delete linkedNodes[_name];
        delete offers[node.hash];
        if (index == 0)
            claimedToken[msg.sender] += offer.price * offer.amount;
        else if (index == 1)
            claimedToken[msg.sender] += offer.amount * (satUnits - offer.price);
        else if (index == 2)
            claimedStable[msg.sender] += offer.price * offer.amount;
        else
            claimedStable[msg.sender] += offer.amount * (scUnits * offer.strike - offer.price);
    }
    

    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name

        @param address _seller: the seller that is taking the buy offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == offers[linkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer(address _seller, bytes32 _name) internal returns(bool success){
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(offer.buy);
        uint8 index = (offer.call? 0 : 2);
        //make sure the seller has sufficient collateral posted
        options optionsContract = options(optionsAddress);
        uint expectedAmt = 0;
        if (_seller == offer.offerer) {
            require((offer.call ? claimedToken[_seller] : claimedStable[_seller]) >= expectedAmt);
        }
        else if (offer.call){
            expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            require(offer.price * offer.amount >= expectedAmt || claimedToken[_seller] >= expectedAmt - (offer.price * offer.amount));
            claimedToken[_seller] -= offer.price * offer.amount  >= expectedAmt ? 0 : expectedAmt - offer.price * offer.amount;
        }
        else{
            expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            require(offer.price * offer.amount >= expectedAmt || claimedStable[_seller] >= expectedAmt - (offer.price * offer.amount));
            claimedStable[_seller] -= offer.price * offer.amount  >= expectedAmt ? 0 : expectedAmt - offer.price * offer.amount;
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
        emit offerAccepted(_name, offer.amount);
        //now we make the trade happen
        if (offer.call){
            (bool safe, uint transferAmt) = optionsContract.mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            assert(safe);
            //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
            /*
                2nd expression in ternary operator simplifies as follows
                offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                offer.price*offer.amount - transferAmount
            */
            claimedToken[_seller] += offer.price * offer.amount  >= expectedAmt || offer.offerer == _seller ? offer.price * offer.amount - transferAmt : expectedAmt-transferAmt;
        }
        else{            
            (bool safe, uint transferAmt) = optionsContract.mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            assert(safe);
            //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
            /*
                2nd expression in ternary operator simplifies as follows
                offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                offer.price*offer.amount - transferAmount
            */
            claimedStable[_seller] += offer.price * offer.amount  >= expectedAmt || offer.offerer == _seller ? offer.price * offer.amount - transferAmt : expectedAmt-transferAmt;
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        return true;
    }

    /*
        @Description: handles logistics of the buyer accepting a sell order with the identifier _name

        @param address _buyer: the buyer that is taking the sell offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == offers[linkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeSellOffer(address _buyer, bytes32 _name) internal returns(bool success){
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(!offer.buy);
        uint8 index = (offer.call? 1 : 3);
        //make sure the seller has sufficient collateral posted
        if (_buyer == offer.offerer) {}
        else if (offer.call){
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
        emit offerAccepted(_name, offer.amount);
        //now we make the trade happen
        options optionsContract = options(optionsAddress);
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall
            */
            if (offer.call) claimedToken[_buyer] += offer.amount * (satUnits - offer.price);
            else claimedStable[_buyer] += offer.amount * (scUnits * offer.strike - offer.price); 
        }
        else if (offer.call){
            (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.amount*satUnits);
            assert(safe);
            //redeem the seller collateral that was not required
            claimedToken[offer.offerer] += (satUnits * offer.amount) - transferAmount;
        }
        else{
            (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.amount*scUnits*offer.strike);
            assert(safe);
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
        require(_strike != 0);
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice){
            if (offer.amount > _amount){
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                options optionsContract = options(optionsAddress);
                if (_call){
                    uint expectedAmt = 0;
                    if (msg.sender != offer.offerer) {
                        expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(_amount), offer.strike);
                        require(offer.price * _amount >= expectedAmt || claimedToken[msg.sender] >= expectedAmt - (offer.price * _amount));
                        claimedToken[msg.sender] -= offer.price * _amount >= expectedAmt ? 0 : expectedAmt - offer.price * _amount;
                    }
                    (bool safe, uint transferAmount) = optionsContract.mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
                    /*
                        2nd expression in ternary operator simplifies as follows
                        offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                        offer.price*offer.amount - transferAmount
                    */
                    claimedToken[msg.sender] += offer.price * _amount >= expectedAmt || offer.offerer == msg.sender ? offer.price * _amount - transferAmount : expectedAmt-transferAmount;
                }
                else {
                    uint expectedAmt = 0;
                    if (msg.sender != offer.offerer){
                        expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(_amount), offer.strike);
                        require(offer.price * _amount >= expectedAmt || claimedStable[msg.sender] >= expectedAmt - (offer.price * _amount));
                        claimedStable[msg.sender] -= offer.price * _amount >= expectedAmt ? 0 : expectedAmt - offer.price * _amount;
                    }
                    (bool safe, uint transferAmount) = optionsContract.mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
                    /*
                        2nd expression in ternary operator simplifies as follows
                        offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                        offer.price*offer.amount - transferAmount
                    */
                    claimedStable[msg.sender] += offer.price * _amount >= expectedAmt || offer.offerer == msg.sender ? offer.price * _amount - transferAmount : expectedAmt-transferAmount;
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
        require(_strike != 0);
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && (_call ? claimedToken[msg.sender] : claimedStable[msg.sender]) >= offer.price && offer.price <= _limitPrice){
            if (offer.amount > _amount){
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                options optionsContract = options(optionsAddress);
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall
                    */
                    if (_call) claimedToken[msg.sender] += _amount * (satUnits - offer.price);
                    else claimedStable[msg.sender] += _amount * (scUnits * offer.strike - offer.price); 
                }
                else if (_call){
                    require(claimedToken[msg.sender] >= offer.price * _amount);
                    claimedToken[msg.sender] -= offer.price * _amount;
                    
                    (bool safe, uint transferAmount) = optionsContract.mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, _amount*satUnits);
                    assert(safe);
                    //redeem the seller collateral that was not required
                    claimedToken[offer.offerer] += (satUnits * _amount) - transferAmount;
                }//*
                else { //!call && msg.sender != offer.offerer
                    require(claimedStable[msg.sender] >= offer.price * _amount);
                    claimedStable[msg.sender] -= offer.price * _amount;
                    uint limit = _amount*scUnits*offer.strike;
                    (bool safe, uint transferAmount) = optionsContract.mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, limit);
                    assert(safe);
                    //redeem the seller collateral that was not used
                    claimedStable[offer.offerer] += (scUnits * _amount * _strike) - transferAmount;
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