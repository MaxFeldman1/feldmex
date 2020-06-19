pragma solidity ^0.5.12;
import "./interfaces/ERC20.sol";
import "./options.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract exchange{
    //denominated in Underlying Token satUnits
    mapping(address => uint) claimedToken;
    
    //denominated in the strike asset scUnits
    mapping(address => uint) claimedStable;

    //------------functions to view balances----------------
    function viewClaimed(bool _token) public view returns(uint ret){ret = _token? claimedToken[msg.sender] : claimedStable[msg.sender];}
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
        /*
            long call => index: 0
            short call => index: 1
            long put => index: 2
            short put => index: 3
        */
        uint8 index;
    }
    
    event offerPosted(
        bytes32 name,
        uint maturity,
        uint strike,
        uint price,
        uint amount,
        uint8 index
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
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
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
        @Description: initialise globals and preform initial processes with the underlying asset and strike asset contracts

        @param address _underlyingAssetAddress: address that shall be assigned to underlyingAssetAddress
        @param address _strikeAssetAddress: address that shall be assigned to strikeAssetAddress
        @param address _optionsAddress: address that shall be assigned to optionsAddress
    */
    constructor (address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress) public{
        underlyingAssetAddress = _underlyingAssetAddress;
        optionsAddress = _optionsAddress;
        strikeAssetAddress = _strikeAssetAddress;
        ERC20 ua = ERC20(underlyingAssetAddress);
        satUnits = 10 ** uint(ua.decimals());
        ua.approve(optionsAddress, 2**255);
        ERC20 sa = ERC20(strikeAssetAddress);
        scUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the claimedToken and claimedStable mappings

        @param uint _amount: the amount of the token to be deposited
        @param uint _amountStable: the amount of the strike asset to be deposited

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(uint _amount, uint _amountStable) public returns(bool success){
        if (_amount != 0){
            ERC20 ua = ERC20(underlyingAssetAddress);
            if (ua.transferFrom(msg.sender, address(this), _amount))
                claimedToken[msg.sender]+=_amount;
            else 
                return false;
        }
        if (_amountStable != 0){
            ERC20 sa = ERC20(strikeAssetAddress);
            if (sa.transferFrom(msg.sender, address(this), _amountStable))
                claimedStable[msg.sender]+=_amountStable;
            else 
                return false;
        }
        success = true;
    }
    
    /*
        @Description: send back all funds tracked in the claimedToken and claimedStable mappings of the caller to the callers address

        @param bool _token: if true withdraw the tokens recorded in claimedToken if false withdraw the strike asset stored in claimedStable

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds(bool _token) public returns(bool success){
        if (_token){
            uint val = claimedToken[msg.sender];
            require(val > 0);
            ERC20 ua = ERC20(underlyingAssetAddress);
            claimedToken[msg.sender] = 0;
            success = ua.transfer(msg.sender, val);
        }
        else {
            uint val = claimedStable[msg.sender];
            require(val > 0);
            ERC20 sa = ERC20(strikeAssetAddress);
            claimedStable[msg.sender] = 0;
            success = sa.transfer(msg.sender, val);
        }

    }
    
    /*
        @Description: creates two hashes to be keys in the linkedNodes and the offers mapping

        @param Offer _offer: the offer for which to make the identifiers

        @return bytes32 _hash: key in offers mapping
        @return bytes32 _name: key in linkedNodes mapping
    */
    function hasher(Offer memory _offer) internal returns(bytes32 _hash, bytes32 _name){
        _hash =  keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.index, totalOrders));
        totalOrders++;
        _name = keccak256(abi.encodePacked(_hash, now, totalOrders));
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
        require(_maturity != 0 && _price != 0 && _price < (_call? satUnits: _strike) && _strike != 0);
        require((options(optionsAddress)).contains(msg.sender, _maturity, _strike));
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
            uint req = _amount * (satUnits - _price);
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
        }
        else if (index == 2){
            require(claimedStable[msg.sender] >= _price*_amount);
            claimedStable[msg.sender] -= _price * _amount;
        }
        else {
            /*
                because:
                    inflator == scUnits && _strike == inflator * nonInflatedStrike
                therefore:
                    _amount * (scUnits * nonInflatedStrike - price) ==
                    _amount * (scUnits * (_strike /inflator) - price) ==
                    _amount * (_strike - price)
                
            */
            require(claimedStable[msg.sender] >= _amount * (_strike - _price));
            claimedStable[msg.sender] -= _amount * (_strike - _price);
        }
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //place order in the mappings
        offers[hash] = offer;
        linkedNodes[name] = linkedNode(hash, name, 0, 0);
        listHeads[_maturity][_strike][index] = name;
        emit offerPosted(name, offers[hash].maturity, offers[hash].strike, offers[hash].price, offers[hash].amount, index);
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
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].strike == _strike && _maturity != 0 && _price != 0 && _price < (_call? satUnits: _strike) && _strike != 0);
        uint8 index = (_buy? 0 : 1) + (_call? 0 : 2);
        require(offers[linkedNodes[_name].hash].index == index);
        require((options(optionsAddress)).contains(msg.sender, _maturity, _strike));
        if (index == 0){
            require(claimedToken[msg.sender] >= _price*_amount);
            claimedToken[msg.sender] -= _price * _amount;
        }
        else if (index == 1){
            uint req = _amount * (satUnits - _price);
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
        }
        else if (index == 2){
            require(claimedStable[msg.sender] >= _price*_amount);
            claimedStable[msg.sender] -= _price * _amount;
        }
        else {
            require(claimedStable[msg.sender] >= _amount * (_strike - _price));
            claimedStable[msg.sender] -= _amount * (_strike - _price);
        }

        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, index);
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
        //uint8 index = (offer.buy? 0 : 1) + (offer.call? 0 : 2);
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.previous == 0){
            delete listHeads[offers[node.hash].maturity][offers[node.hash].strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offers[node.hash].maturity][offers[node.hash].strike][offer.index] = node.next;
        }
        emit offerCalceled(_name);
        delete linkedNodes[_name];
        delete offers[node.hash];
        if (offer.index == 0)
            claimedToken[msg.sender] += offer.price * offer.amount;
        else if (offer.index == 1)
            claimedToken[msg.sender] += offer.amount * (satUnits - offer.price);
        else if (offer.index == 2)
            claimedStable[msg.sender] += offer.price * offer.amount;
        else
            claimedStable[msg.sender] += offer.amount * (offer.strike - offer.price);
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
        require(offer.index%2 == 0);
        //uint8 index = (offer.call? 0 : 2);
        //make sure the seller has sufficient collateral posted
        options optionsContract = options(optionsAddress);
        uint expectedAmt;
        if (_seller == offer.offerer) {}
        else if (offer.index < 2){
            expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            if (offer.price * offer.amount < expectedAmt && claimedToken[_seller] < expectedAmt - (offer.price * offer.amount)) return false;
            claimedToken[_seller] -= offer.price * offer.amount  >= expectedAmt ? 0 : expectedAmt - offer.price * offer.amount;
        }
        else{
            expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(offer.amount), offer.strike);
            if (offer.price * offer.amount < expectedAmt && claimedStable[_seller] < expectedAmt - (offer.price * offer.amount)) return false;
            claimedStable[_seller] -= offer.price * offer.amount  >= expectedAmt ? 0 : expectedAmt - offer.price * offer.amount;
        }

        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //now we make the trade happen
        if (_seller == offer.offerer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            if (offer.index < 2) claimedToken[_seller] += offer.price * offer.amount;
            else claimedStable[_seller] += offer.price * offer.amount;
        }
        else if (offer.index < 2){

            uint transferAmt = mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
            /*
                2nd expression in ternary operator simplifies as follows
                offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                offer.price*offer.amount - transferAmount
            */
            claimedToken[_seller] += offer.price * offer.amount  >= expectedAmt ? offer.price * offer.amount - transferAmt : expectedAmt-transferAmt;
        }
        else{            
            uint transferAmt = mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, expectedAmt);
            //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
            /*
                2nd expression in ternary operator simplifies as follows
                offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                offer.price*offer.amount - transferAmount
            */
            claimedStable[_seller] += offer.price * offer.amount  >= expectedAmt ? offer.price * offer.amount - transferAmt : expectedAmt-transferAmt;
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        success = true;
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
        require(offer.index%2==1);
        //uint8 index = (offer.call? 1 : 3);
        //make sure the seller has sufficient collateral posted
        if (_buyer == offer.offerer) {}
        else if (offer.index < 2){
            if (claimedToken[_buyer] < offer.price * offer.amount) return false;
            claimedToken[_buyer] -= offer.price * offer.amount;
        }
        else{
            if (claimedStable[_buyer] < offer.price * offer.amount) return false;
            claimedStable[_buyer] -= offer.price * offer.amount;
        }

        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.strike][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            if (offer.index < 2) claimedToken[_buyer] += offer.amount * (satUnits - offer.price);
            else claimedStable[_buyer] += offer.amount * (offer.strike - offer.price); 
        }
        else if (offer.index < 2){
            uint _satUnitsTimesAmount = offer.amount*satUnits; //gas savings
            uint transferAmount = mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, _satUnitsTimesAmount);
            //redeem the seller collateral that was not required
            claimedToken[offer.offerer] += (_satUnitsTimesAmount) - transferAmount;
        }
        else{
            uint transferAmount = mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.amount*offer.strike);
            //redeem the seller collateral that was not required
            claimedStable[offer.offerer] += (offer.amount * offer.strike) - transferAmount;
        }
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
        success = true;
    }

    /*
        @Description: Caller of the function takes the best buy offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, uint _strike, uint _limitPrice, uint _amount, bool _call) public returns(uint unfilled){
        require(_strike != 0);
        require((options(optionsAddress)).contains(msg.sender, _maturity, _strike));
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0);
        options optionsContract = options(optionsAddress);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice){
            if (offer.amount > _amount){
                if (msg.sender == offer.offerer) {
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    if (offer.index < 2) claimedToken[msg.sender] += offer.price * _amount;
                    else claimedStable[msg.sender] += offer.price * _amount;
                }
                else if (_call){
                    uint expectedAmt = optionsContract.transferAmount(true, msg.sender, offer.maturity, -int(_amount), offer.strike);
                    if (offer.price * _amount < expectedAmt && claimedToken[msg.sender] < expectedAmt - (offer.price * _amount)) return _amount;
                    claimedToken[msg.sender] -= offer.price * _amount >= expectedAmt ? 0 : expectedAmt - offer.price * _amount;
                    uint transferAmount = mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    //redeem the seller collateral that was not required
                    //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
                    /*
                        2nd expression in ternary operator simplifies as follows
                        offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                        offer.price*offer.amount - transferAmount
                    */
                    claimedToken[msg.sender] += offer.price * _amount >= expectedAmt ? offer.price * _amount - transferAmount : expectedAmt-transferAmount;
                }
                else {
                    uint expectedAmt = optionsContract.transferAmount(false, msg.sender, offer.maturity, -int(_amount), offer.strike);
                    if (offer.price * _amount < expectedAmt && claimedStable[msg.sender] < expectedAmt - (offer.price * _amount)) return _amount;
                    claimedStable[msg.sender] -= offer.price * _amount >= expectedAmt ? 0 : expectedAmt - offer.price * _amount;
                    uint transferAmount = mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, expectedAmt);
                    //redeem the seller collateral that was not required
                    //redeem difference between expectedAmt and transferAmt and any excess between option premium recieved and expectedAmt
                    /*
                        2nd expression in ternary operator simplifies as follows
                        offer.price*offer.amount - expectedAmount + (expectedAmount - transferAmount)
                        offer.price*offer.amount - transferAmount
                    */
                    claimedStable[msg.sender] += offer.price * _amount >= expectedAmt ? offer.price * _amount - transferAmount : expectedAmt-transferAmount;
                }
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                return 0;
            }
            if (!takeBuyOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][index]];
            offer = offers[node.hash];
        }
        unfilled = _amount;
    }

    /*
        @Description: Caller of the function takes the best sell offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: highest price to buy at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, uint _strike, uint _limitPrice, uint _amount, bool _call) public returns (uint unfilled){
        require(_strike != 0);
        require((options(optionsAddress)).contains(msg.sender, _maturity, _strike));
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_strike][index]];
        Offer memory offer = offers[node.hash];
        require(listHeads[_maturity][_strike][index] != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && (_call ? claimedToken[msg.sender] : claimedStable[msg.sender]) >= offer.price && offer.price <= _limitPrice){
            if (offer.amount > _amount){
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    if (_call) claimedToken[msg.sender] += _amount * (satUnits - offer.price);
                    else claimedStable[msg.sender] += _amount * (offer.strike - offer.price); 
                }
                else if (_call){
                    if (claimedToken[msg.sender] < offer.price * _amount) return _amount;
                    claimedToken[msg.sender] -= offer.price * _amount;
                    uint limit = _amount*satUnits;
                    uint transferAmount = mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, limit);
                    //redeem the seller collateral that was not required
                    claimedToken[offer.offerer] += (limit) - transferAmount;
                }//*
                else { //!call && msg.sender != offer.offerer
                    if (claimedStable[msg.sender] < offer.price * _amount) return _amount;
                    claimedStable[msg.sender] -= offer.price * _amount;
                    uint limit = _amount*offer.strike;
                    uint transferAmount = mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, limit);
                    //redeem the seller collateral that was not used
                    claimedStable[offer.offerer] += (_amount * _strike) - transferAmount;
                }
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                return 0;
            }
            if (!takeSellOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_strike][index]];
            offer = offers[node.hash];
        }
        unfilled = _amount;
    }

    function mintCall(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) internal returns (uint transferAmt){        
        options optionsContract = options(optionsAddress);
        optionsContract.clearPositions();
        optionsContract.addPosition(_strike, int(_amount), true);
        (transferAmt, ) = optionsContract.assignCallPosition(_debtor, _holder, _maturity);
        assert(transferAmt <= _maxTransfer);
    }

    function mintPut(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _maxTransfer) internal returns (uint transferAmt){        
        options optionsContract = options(optionsAddress);
        optionsContract.clearPositions();
        optionsContract.addPosition(_strike, int(_amount), false);
        (transferAmt, ) = optionsContract.assignPutPosition(_debtor, _holder, _maturity);
        assert(transferAmt <= _maxTransfer);
    }

}