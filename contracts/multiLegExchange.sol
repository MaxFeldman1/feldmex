pragma solidity ^0.5.12;
import "./interfaces/ERC20.sol";
import "./options.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract multiLegExchange {
    //denominated in Underlying Token satUnits
    mapping(address => uint) claimedToken;
    
    //denominated in the legsHash asset scUnits
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
        bytes32 legsHash;
        int price;
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
        bytes32 legsHash,
        int price,
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
    //maturity => legsHash => headNode.name [longCall, shortCall, longPut, shortPut]
    mapping(uint => mapping(bytes32 => bytes32[2])) public listHeads;
    
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) public linkedNodes;

    /*
        Note all linkedNodes correspond to a buyOffer
        The offers[linkedNodes[name].hash] links to a buyOffer
    */
    
    //holds all offers
    mapping(bytes32 => Offer) public offers;

    struct position {
        int[] callAmounts;
        uint[] callStrikes;
        int[] putAmounts;
        uint[] putStrikes;
        uint maxUnderlyingAssetDebtor;
        uint maxUnderlyingAssetHolder;
        uint maxStrikeAssetDebtor;
        uint maxStrikeAssetHolder;
    }

    mapping(bytes32 => position) public positions;

    function addLegHash(uint[] memory _callStrikes, int[] memory _callAmounts, uint[] memory _putStrikes, int[] memory _putAmounts) public {
        //make sure that this is a multi leg order
        require(_callAmounts.length > 0 && _putAmounts.length > 0);
        require(_callAmounts.length==_callStrikes.length&&_putAmounts.length==_putStrikes.length);
        bytes32 hash = keccak256(abi.encodePacked(_callStrikes, _callAmounts, _putStrikes, _putAmounts));
        options optionsContract = options(optionsAddress);
        uint prevStrike;
        //load position
        optionsContract.clearPositions();
        for (uint i = 0; i < _callAmounts.length; i++){
            require(prevStrike < _callStrikes[i] && _callAmounts[i] != 0);
            prevStrike = _callStrikes[i];
            optionsContract.addPosition(_callStrikes[i], _callAmounts[i], true);
        }
        uint maxUnderlyingAssetDebtor = optionsContract.transferAmountPosition(address(0), 1, true);
        optionsContract.inversePosition(true);
        uint maxUnderlyingAssetHolder = optionsContract.transferAmountPosition(address(0), 1, true);

        prevStrike = 0;
        optionsContract.clearPositions();
        for (uint i = 0; i < _putAmounts.length; i++){
            require(prevStrike < _putStrikes[i] && _putAmounts[i] != 0);
            prevStrike = _putStrikes[i];
            optionsContract.addPosition(_putStrikes[i], _putAmounts[i], false);
        }
        uint maxStrikeAssetDebtor = optionsContract.transferAmountPosition(address(0), 1, false);
        optionsContract.inversePosition(false);
        uint maxStrikeAssetHolder = optionsContract.transferAmountPosition(address(0), 1, false);
        position memory pos = position(_callAmounts, _callStrikes, _putAmounts, _putStrikes, maxUnderlyingAssetDebtor, maxUnderlyingAssetHolder, maxStrikeAssetDebtor, maxStrikeAssetHolder);
        positions[hash] = pos;
    }
    
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address legsHashAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
    //previously recorded balances of this contract
    uint satReserves;
    uint scReserves;
    
    /*  
        @Description: initialise globals and preform initial processes with the underlying asset and legsHash asset contracts

        @param address _underlyingAssetAddress: address that shall be assigned to underlyingAssetAddress
        @param address _legsHashAssetAddress: address that shall be assigned to legsHashAssetAddress
        @param address _optionsAddress: address that shall be assigned to optionsAddress
    */
    constructor (address _underlyingAssetAddress, address _legsHashAssetAddress, address _optionsAddress) public{
        underlyingAssetAddress = _underlyingAssetAddress;
        optionsAddress = _optionsAddress;
        legsHashAssetAddress = _legsHashAssetAddress;
        ERC20 ua = ERC20(underlyingAssetAddress);
        satUnits = 10 ** uint(ua.decimals());
        ua.approve(optionsAddress, 2**255);
        ERC20 sa = ERC20(legsHashAssetAddress);
        scUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the claimedToken and claimedStable mappings

        @param uint _to: the address to which to credit deposited funds

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(address _to) public returns(bool success){
        uint balance = ERC20(underlyingAssetAddress).balanceOf(address(this));
        uint sats = balance - satReserves;
        satReserves = balance;
        balance = ERC20(legsHashAssetAddress).balanceOf(address(this));
        uint sc = balance - scReserves;
        scReserves = balance;
        claimedToken[_to] += sats;
        claimedStable[_to] += sc;
        success = true;
    }

    /*
        @Description: send back all funds tracked in the claimedToken and claimedStable mappings of the caller to the callers address

        @param bool _token: if true withdraw the tokens recorded in claimedToken if false withdraw the legsHash asset stored in claimedStable

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds(bool _token) public returns(bool success){
        if (_token){
            uint val = claimedToken[msg.sender];
            ERC20 ua = ERC20(underlyingAssetAddress);
            claimedToken[msg.sender] = 0;
            success = ua.transfer(msg.sender, val);
            satReserves -= val;
        }
        else {
            uint val = claimedStable[msg.sender];
            ERC20 sa = ERC20(legsHashAssetAddress);
            claimedStable[msg.sender] = 0;
            success = sa.transfer(msg.sender, val);
            scReserves -= val;
        }

    }
    
    /*
        @Description: creates two hashes to be keys in the linkedNodes and the offers mapping

        @param Offer _offer: the offer for which to make the identifiers

        @return bytes32 _hash: key in offers mapping
        @return bytes32 _name: key in linkedNodes mapping
    */
    function hasher(Offer memory _offer) internal returns(bytes32 _hash, bytes32 _name){
        _hash =  keccak256(abi.encodePacked(_offer.maturity, _offer.legsHash, _offer.price, _offer.offerer, _offer.index, totalOrders));
        totalOrders++;
        _name = keccak256(abi.encodePacked(_hash, now, totalOrders));
    }


    /*
        @Description: creates an order and posts it in one of the 4 linked lists depending on if it is a buy or sell order and if it is for calls or puts
            unless this is the first order of its kind functionality is outsourced to insertOrder

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order
    */
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) public {
        require(_maturity != 0 && _legsHash != 0 && _amount != 0);
        position memory pos = positions[_legsHash];

        //check that the neccesary strikes have been added

        if (listHeads[_maturity][_legsHash][_index] != 0) {
            insertOrder(_maturity, _legsHash, _price, _amount, _index, listHeads[_maturity][_legsHash][_index]);
            return;
        }
        //only continue execution here if listHead[_maturity][_legsHash][index] == 0
        if (_index == 0){
            uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetHolder) + _price));
            if (int(req) < 0) req = 0;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = _amount * pos.maxStrikeAssetHolder;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else if (_index == 1){
            uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetDebtor) - _price));
            if (int(req) < 0) req = 0;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = _amount * pos.maxStrikeAssetDebtor;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else if (_index == 2){
            uint req = _amount * pos.maxUnderlyingAssetHolder;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = uint(int(_amount) * (int(pos.maxStrikeAssetHolder) + _price));
            if (int(req) < 0) req = 0;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else {
            uint req = _amount * pos.maxUnderlyingAssetDebtor;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = uint(int(_amount) * (int(pos.maxStrikeAssetDebtor) - _price));
            if (int(req) < 0) req = 0;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        Offer memory offer = Offer(msg.sender, _maturity, _legsHash, _price, _amount, _index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //place order in the mappings
        offers[hash] = offer;
        linkedNodes[name] = linkedNode(hash, name, 0, 0);
        listHeads[_maturity][_legsHash][_index] = name;
        emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
    }

    //allows for users to post Orders with a smaller gas usage by giving another order as refrence to find their orders position from
    /*
        @Description: this is the same as post order though it allows for gas to be saved by searching for the orders location in relation to another order
            this function is best called by passing in the name of an order that is directly next to the future location of your order
        
        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order 
        @param bytes32 _name: the name identifier of the order from which to search for the location to insert this order
    */
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) public {
        //make sure the offer and node corresponding to the name is in the correct list
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].legsHash == _legsHash && _maturity != 0 &&  _legsHash != 0);
        require(offers[linkedNodes[_name].hash].index == _index);

        //ensure that the neccesary strikes have been added

        position memory pos = positions[_legsHash];

        if (_index == 0){
            uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetHolder) + _price));
            if (int(req) < 0) req = 0;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = _amount * pos.maxStrikeAssetHolder;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else if (_index == 1){
            uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetDebtor) - _price));
            if (int(req) < 0) req = 0;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = _amount * pos.maxStrikeAssetDebtor;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else if (_index == 2){
            uint req = _amount * pos.maxUnderlyingAssetHolder;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = uint(int(_amount) * (int(pos.maxStrikeAssetHolder) + _price));
            if (int(req) < 0) req = 0;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
        else {
            uint req = _amount * pos.maxUnderlyingAssetDebtor;
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
            req = uint(int(_amount) * (int(pos.maxStrikeAssetDebtor) - _price));
            if (int(req) < 0) req = 0;
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }

        Offer memory offer = Offer(msg.sender, _maturity, _legsHash, _price, _amount, _index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //if we need to traverse down the list further away from the list head
        linkedNode memory currentNode = linkedNodes[_name];
        bool _buy = _index%2==0;
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
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
                return;
            }
            //it falls somewhere in the middle of the chain
            else{
                linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
                linkedNodes[currentNode.name].previous = name;
                linkedNodes[previousNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
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
                listHeads[_maturity][_legsHash][_index] = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
                return; 
            }
            //falls somewhere in the middle of the list
            else {
                linkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                linkedNodes[nextNode.name].previous = name;
                linkedNodes[currentNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
                return;
            }
        }
    }

    /*
        @Description: removes the order with name identifier _name, prevents said order from being filled or taken

        @param bytes32: the identifier of the node which stores the order to cancel, offerToCancel == offers[linkedNodes[_name].hash]
    */
    function cancelOrderInternal(bytes32 _name) internal {
        linkedNode memory node = linkedNodes[_name];
        require(msg.sender == offers[node.hash].offerer);
        Offer memory offer = offers[node.hash];
        //uint8 index = (offer.buy? 0 : 1) + (offer.call? 0 : 2);
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.previous == 0){
            delete listHeads[offers[node.hash].maturity][offers[node.hash].legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offers[node.hash].maturity][offers[node.hash].legsHash][offer.index] = node.next;
        }
        emit offerCalceled(_name);
        delete linkedNodes[_name];
        delete offers[node.hash];
        position memory pos = positions[offer.legsHash];
        if (offer.index == 0){
            uint req = uint(int(offer.amount) * (int(pos.maxUnderlyingAssetHolder) + offer.price));
            if (int(req) < 0) req = 0;
            claimedToken[msg.sender] += req;
            claimedStable[msg.sender] += offer.amount * pos.maxStrikeAssetHolder;
        }
        else if (offer.index == 1){
            uint req = uint(int(offer.amount) * (int(pos.maxUnderlyingAssetDebtor) - offer.price));
            if (int(req) < 0) req = 0;
            claimedToken[msg.sender] += req;
            claimedStable[msg.sender] += offer.amount * pos.maxStrikeAssetDebtor;
        }
        else if (offer.index == 2){
            claimedToken[msg.sender] += offer.amount * pos.maxUnderlyingAssetHolder;
            uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetHolder) + offer.price));
            if (int(req) < 0) req = 0;
            claimedStable[msg.sender] += req;
        }
        else {
            claimedToken[msg.sender] += offer.amount * pos.maxUnderlyingAssetDebtor;
            uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetDebtor) - offer.price));
            if (int(req) < 0) req = 0;
            claimedStable[msg.sender] += req;
        }

    }
    

    function cancelOrder(bytes32 _name) public {
        cancelOrderInternal(_name);
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

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (_seller == offer.offerer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            cancelOrderInternal(_name);
            return true;
        }
        else {
            success = mintPosition(_seller, offer.offerer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            if (!success) return false;
        }
        //repair linked list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.legsHash][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
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

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            cancelOrderInternal(_name);
            return true;
        }
        else {
            success = mintPosition(offer.offerer, _buyer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            if (!success) return false;
        }
        //repair linked list
        if (node.next != 0 && node.previous != 0){
            linkedNodes[node.next].previous = node.previous;
            linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.next == 0){
            delete listHeads[offer.maturity][offer.legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            linkedNodes[node.next].previous = 0;
            listHeads[offer.maturity][offer.legsHash][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete linkedNodes[_name];
        delete offers[node.hash];
    }

    /*
        @Description: Caller of the function takes the best buy offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, bool _call) public returns(uint unfilled){
        require(_legsHash != 0);
        //ensure all strikes are contained
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][index]];
        Offer memory offer = offers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice){
            if (offer.amount > _amount || offer.price < 0 && uint(-offer.price)*offer.amount > (_call ? claimedToken[msg.sender] : claimedStable[msg.sender])){
                uint maxAmt;
                if (msg.sender == offer.offerer) {
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    position memory pos = positions[offer.legsHash];
                    if (offer.index == 0){
                        uint req = uint(int(offer.amount) * (int(pos.maxUnderlyingAssetHolder) + offer.price));
                        if (int(req) < 0) req = 0;
                        claimedToken[msg.sender] += req;
                        claimedStable[msg.sender] += offer.amount * pos.maxStrikeAssetHolder;
                    } else {
                        claimedToken[msg.sender] += offer.amount * pos.maxUnderlyingAssetHolder;
                        uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetHolder) + offer.price));
                        if (int(req) < 0) req = 0;
                        claimedStable[msg.sender] += req;
                    }
                    maxAmt = _amount;
                }
                else {
                    maxAmt = offer.amount > _amount ? _amount : offer.amount; 
                    if (offer.price < 0 && uint(-offer.price)*maxAmt > (_call ? claimedToken[msg.sender] : claimedStable[msg.sender]))
                        maxAmt = (_call ? claimedToken[msg.sender] : claimedStable[msg.sender])/uint(-offer.price);
                    if (maxAmt == 0) return _amount;
                    bool success = mintPosition(msg.sender, offer.offerer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
                    if (!success) return _amount;

                }
                offers[node.hash].amount -= maxAmt;
                emit offerAccepted(node.name, maxAmt);
                return _amount-maxAmt;
            }
            if (!takeBuyOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_legsHash][index]];
            offer = offers[node.hash];
        }
        unfilled = _amount;
    }

    /*
        @Description: Caller of the function takes the best sell offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: highest price to buy at
        @param uint _amount: the amount of calls or puts that this order is for
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, bool _call) public returns (uint unfilled){
        require(_legsHash != 0);
        //ensure all strikes are contained
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][index]];
        Offer memory offer = offers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price <= _limitPrice){
            if (offer.amount > _amount || offer.price > 0 && uint(offer.price)*offer.amount > (_call ? claimedToken[msg.sender] : claimedStable[msg.sender])){
                uint maxAmt;
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    position memory pos = positions[offer.legsHash];
                    if (offer.index == 1){
                        uint req = uint(int(offer.amount) * (int(pos.maxUnderlyingAssetDebtor) - offer.price));
                        if (int(req) < 0) req = 0;
                        claimedToken[msg.sender] += req;
                        claimedStable[msg.sender] += offer.amount * pos.maxStrikeAssetDebtor;
                    } else {
                        claimedToken[msg.sender] += offer.amount * pos.maxUnderlyingAssetDebtor;
                        uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetDebtor) - offer.price));
                        if (int(req) < 0) req = 0;
                        claimedStable[msg.sender] += req;
                    }
                    maxAmt = _amount;
                }
                else {
                    maxAmt = offer.amount > _amount ? _amount : offer.amount; 
                    if (offer.price > 0 && uint(offer.price)*offer.amount > (_call ? claimedToken[msg.sender] : claimedStable[msg.sender]))
                        maxAmt = (_call ? claimedToken[msg.sender] : claimedStable[msg.sender])/uint(offer.price);
                    if (maxAmt == 0) return _amount;
                    bool success = mintPosition(offer.offerer, msg.sender, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
                    if (!success) return _amount;
                }
                offers[node.hash].amount -= maxAmt;
                emit offerAccepted(node.name, maxAmt);
                return _amount-maxAmt;
            }
            if (!takeSellOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_legsHash][index]];
            offer = offers[node.hash];
        }
        unfilled = _amount;
    }

    function mintPosition(address _debtor, address _holder, uint _maturity, bytes32 _legsHash, uint _amount, int _price, uint8 _index) internal returns(bool success){
        /*
            debtor pays is true if debtor is making the market order and thus debtor must provide the necessary collateral
                whereas the holder has already provided the necessary collateral
                this means that the debtor recieves the price premium
        */
        _price *= int(_amount);
        if (_index%2==1 && _price > 0 && (_index < 2 ? claimedToken[_holder] : claimedStable[_holder]) < uint(_price)) return false;
        else if (_index%2==0 && _price < 0 && (_index < 2 ? claimedToken[_debtor] : claimedStable[_debtor]) < uint(-_price)) return false;
        address _optionsAddress = optionsAddress; //gas savings
        options optionsContract = options(_optionsAddress);
        position memory pos = positions[_legsHash];
        optionsContract.setParams(_debtor, _holder, _maturity);
        //load call position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.callAmounts.length; i++)
            optionsContract.addPosition(pos.callStrikes[i], pos.callAmounts[i], true);
        if (_index%2==0){
            uint limit = claimedToken[_debtor];
            limit = uint(int(limit)+(_index<2 ? _price : 0));
            optionsContract.setLimits(limit, pos.maxUnderlyingAssetHolder);
        }
        else{
            uint limit = claimedToken[_debtor];
            limit = uint(int(limit)-(_index<2 ? _price : 0));
            optionsContract.setLimits(pos.maxUnderlyingAssetDebtor, limit);
        }
        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return false;
        uint transferAmountDebtor = optionsContract.transferAmountDebtor();
        uint transferAmountHolder = optionsContract.transferAmountHolder();
        //load put position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.putAmounts.length; i++)
            optionsContract.addPosition(pos.putStrikes[i], pos.putAmounts[i], false);
        if (_index%2==0){
            uint limit = claimedStable[_debtor];
            limit = uint(int(limit)+(_index>1 ? _price : 0));
            optionsContract.setLimits(limit, pos.maxStrikeAssetHolder);
        }
        else{
            uint limit = claimedStable[_debtor];
            limit = uint(int(limit)-(_index>1 ? _price : 0));
            optionsContract.setLimits(pos.maxStrikeAssetDebtor, limit);
        }
        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignPutPosition()"));
        if (!success) return false;
        /*
            We have minted the put position but we still have data from the call position stored in transferAmountDebtor and transferAmountHolder
            handle distribution of funds in claimedToken mapping
        */
        if (_index%2==0){
            if (_index < 2 && _price > 0) claimedToken[_debtor] += uint(_price);
            else if(_index < 2) claimedToken[_debtor] -= uint(-_price);
            claimedToken[_debtor] -= transferAmountDebtor;
            claimedToken[_holder] += pos.maxUnderlyingAssetHolder - transferAmountHolder;
        } else {
            if (_index < 2 && _price > 0) claimedToken[_holder] -= uint(_price);
            else if (_index < 2) claimedToken[_holder] += uint(-_price);
            claimedToken[_holder] -= transferAmountHolder;
            claimedToken[_debtor] += pos.maxUnderlyingAssetDebtor - transferAmountDebtor;
        }
        satReserves -= transferAmountDebtor+transferAmountHolder;
        //update transfer amounts and handle distribution of funds in claimedStable mapping
        transferAmountDebtor = optionsContract.transferAmountDebtor();
        transferAmountHolder = optionsContract.transferAmountHolder();
        if (_index%2==0){
            if (_index > 1 && _price > 0) claimedStable[_debtor] += uint(_price);
            else if (_index < 2) claimedStable[_debtor] -= uint(-_price);
            claimedStable[_debtor] -= transferAmountDebtor;
            claimedStable[_holder] += pos.maxStrikeAssetHolder - transferAmountHolder;
        } else {
            if (_index > 1 && _price > 0) claimedStable[_holder] -= uint(_price);
            else if (_index < 2) claimedStable[_holder] += uint(-_price);
            claimedStable[_holder] -= transferAmountHolder;
            claimedStable[_debtor] += pos.maxStrikeAssetDebtor - transferAmountDebtor;
        }
        scReserves -= transferAmountDebtor+transferAmountHolder;
    }


}