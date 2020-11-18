pragma solidity >=0.6.0;
import "../../interfaces/IERC20.sol";
import "../../optionsHandler/options.sol";
import "../../feeOracle.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract multiPutExchange {
    //denominated in the legsHash asset strikeAssetSubUnits
    mapping(address => uint) public strikeAssetDeposits;

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
            long put => index: 0
            short put => index: 1
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

    event legsHashCreated(
        bytes32 legsHash
    );

    /*
        listHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing offers at the top near the head
    */
    //maturity => legsHash => headNode.name [buy, sell]
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
        int[] putAmounts;
        uint[] putStrikes;
        int maxStrikeAssetDebtor;
        int maxStrikeAssetHolder;
    }
    //hash of position information => position
    mapping(bytes32 => position) public positions;

    /*
        @Description: returns arrays callAmounts and callStrikes of a given position

        @param bytes32 _legsHash: the hash leading to the positions

        @return int[] memory putAmounts: position.putAmounts
        @return uint[] memory putStrikes: position.putStrikes
    */
    function positionInfo(bytes32 _legsHash) public view returns(int[] memory putAmounts, uint[] memory putStrikes){
        position memory pos = positions[_legsHash];
        putAmounts = pos.putAmounts;
        putStrikes = pos.putStrikes;
    }

    /*
        @Description: add new position to enable trading on said position

        @param uint[] memory _putStrikes: the strikes of the put positions
        @param int[] memory _putAmounts: the amount of the put positons at the various strikes in _putStrikes
    */
    function addLegHash(uint[] memory _putStrikes, int[] memory _putAmounts) public {
        //make sure that this is a multi leg order
        require(_putAmounts.length > 1);
        require(_putAmounts.length==_putStrikes.length);
        int _strikeAssetSubUnits = int(strikeAssetSubUnits);  //gas savings
        bytes32 hash = keccak256(abi.encodePacked(_putStrikes, _putAmounts));
        options optionsContract = options(optionsAddress);
        uint prevStrike;
        //load position
        optionsContract.clearPositions();
        for (uint i = 0; i < _putAmounts.length; i++){
            require(prevStrike < _putStrikes[i] && _putAmounts[i] != 0);
            prevStrike = _putStrikes[i];
            optionsContract.addPosition(_putStrikes[i], _strikeAssetSubUnits*_putAmounts[i], false);
        }
        (uint maxStrikeAssetDebtor, uint maxStrikeAssetHolder) = optionsContract.transferAmount(false);
        require(int(maxStrikeAssetHolder) > -1);
        require(int(maxStrikeAssetDebtor) > -1);
        position memory pos = position(_putAmounts, _putStrikes, int(maxStrikeAssetDebtor), int(maxStrikeAssetHolder));
        positions[hash] = pos;
        emit legsHashCreated(hash);
    }
    
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint strikeAssetSubUnits;
    //previously recorded balances of this contract
    uint scReserves;
    //address of the contract that stores all fee information and collects all fees
    address feeOracleAddress;
    
    /*  
        @Description: setup
    */
    constructor (address _strikeAssetAddress, address _optionsAddress, address _feeOracleAddress) public {
        optionsAddress = _optionsAddress;
        strikeAssetAddress = _strikeAssetAddress;
        feeOracleAddress = _feeOracleAddress;
        IERC20 sa = IERC20(strikeAssetAddress);
        strikeAssetSubUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the strikeAssetDeposits mapping

        @param uint _to: the address to which to credit deposited funds

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(address _to) public returns(bool success){
        uint balance = IERC20(strikeAssetAddress).balanceOf(address(this));
        uint sc = balance - scReserves;
        scReserves = balance;
        strikeAssetDeposits[_to] += sc;
        success = true;
    }

    /*
        @Description: send back all funds tracked in strikeAssetDeposits mapping of the caller to the callers address

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds() public returns(bool success){
        uint val = strikeAssetDeposits[msg.sender];
        IERC20 sa = IERC20(strikeAssetAddress);
        strikeAssetDeposits[msg.sender] = 0;
        success = sa.transfer(msg.sender, val);
        scReserves -= val;
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
        @Description: checks if all strikes from _legsHash are contained by msg.sender in the options exchange

        @param uint _maturity: the maturity of the maturity strike combination in question
        @param bytes32 _legsHash: key in position mappings that leads to the position in question

        @return bool contains: true if all strikes from legsHash are contained otherwise false
    */
    function containsStrikes(uint _maturity, bytes32 _legsHash) internal view returns (bool contains) {
        position memory pos = positions[_legsHash];
        options optionsContract = options(optionsAddress);
        for (uint i = 0; i < pos.putStrikes.length; i++){
            if (!optionsContract.contains(msg.sender, _maturity, pos.putStrikes[i])) return false;
        }
        contains = true;
    }


    /*
        @Description: pay fee to feldmex token address
    */
    function payFee() internal {
        feeOracle fo = feeOracle(feeOracleAddress);
        if (fo.isFeeImmune(optionsAddress, msg.sender)) return;
        uint fee = fo.multiLegExchangeFlatEtherFee();
        require(msg.value >= fee);
        msg.sender.transfer(msg.value-fee);
        payable(fo.feldmexTokenAddress()).transfer(fee);
    }

    /*
        @Description: creates an order and posts it in one of the 4 linked lists depending on if it is a buy or sell order and if it is for calls or puts
            unless this is the first order of its kind functionality is outsourced to insertOrder

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param uint8 _index: the linked list in which this order is to be placed
    */
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) public payable {
        require(_maturity != 0 && _legsHash != 0 && _amount != 0);

        position memory pos = positions[_legsHash];

        require(pos.putAmounts.length > 0);

        if (listHeads[_maturity][_legsHash][_index] != 0) {
            insertOrder(_maturity, _legsHash, _price, _amount, _index, listHeads[_maturity][_legsHash][_index]);
            return;
        }
        //only continue execution here if listHead[_maturity][_legsHash][index] == 0

        require(_price < pos.maxStrikeAssetDebtor && _price > -pos.maxStrikeAssetHolder);
        require(containsStrikes(_maturity, _legsHash));

        if (_index == 0){
            uint req = uint(int(_amount) * (pos.maxStrikeAssetHolder + _price));
            if (int(req) > 0) {
                uint _strikeAssetSubUnits = strikeAssetSubUnits;
                req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
                require(strikeAssetDeposits[msg.sender] >= req);
                strikeAssetDeposits[msg.sender] -= req;
            }
        }
        else {
            uint req = uint(int(_amount) * (pos.maxStrikeAssetDebtor - _price));
            if (int(req) > 0) {
                uint _strikeAssetSubUnits = strikeAssetSubUnits;
                req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
                require(strikeAssetDeposits[msg.sender] >= req);
                strikeAssetDeposits[msg.sender] -= req;
            }
        }

        Offer memory offer = Offer(msg.sender, _maturity, _legsHash, _price, _amount, _index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //place order in the mappings
        offers[hash] = offer;
        linkedNodes[name] = linkedNode(hash, name, 0, 0);
        listHeads[_maturity][_legsHash][_index] = name;
        payFee();
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
        @param uint8 _index: the linked list in which this order is to be placed
        @param bytes32 _name: the name identifier of the order from which to search for the location to insert this order
    */
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) public payable {
        //make sure the offer and node corresponding to the name is in the correct list
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].legsHash == _legsHash && _maturity != 0 &&  _legsHash != 0);
        require(offers[linkedNodes[_name].hash].index == _index);

        require(containsStrikes(_maturity, _legsHash));

        position memory pos = positions[_legsHash];

        require(pos.putAmounts.length > 0);

        require(_price < pos.maxStrikeAssetDebtor && _price > -pos.maxStrikeAssetHolder);

        if (_index == 0){
            uint req = uint(int(_amount) * (pos.maxStrikeAssetHolder + _price));
            if (int(req) > 0) {
                uint _strikeAssetSubUnits = strikeAssetSubUnits;
                req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
                require(strikeAssetDeposits[msg.sender] >= req);
                strikeAssetDeposits[msg.sender] -= req;
            }
        }
        else {
            uint req = uint(int(_amount) * (pos.maxStrikeAssetDebtor - _price));
            if (int(req) > 0) {
                uint _strikeAssetSubUnits = strikeAssetSubUnits;
                req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
                require(strikeAssetDeposits[msg.sender] >= req);
                strikeAssetDeposits[msg.sender] -= req;
            }
        }

        Offer memory offer = Offer(msg.sender, _maturity, _legsHash, _price, _amount, _index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //if we need to traverse down the list further away from the list head
        linkedNode memory currentNode = linkedNodes[_name];
        if ((_index==0 &&  offers[currentNode.hash].price >= _price) || (_index==1  && offers[currentNode.hash].price <= _price)){
            linkedNode memory previousNode;
            while (currentNode.name != 0){
                previousNode = currentNode;
                currentNode = linkedNodes[currentNode.next];
                if ((_index==0 && offers[currentNode.hash].price < _price) || (_index==1 && offers[currentNode.hash].price > _price)){
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
            }
            //it falls somewhere in the middle of the chain
            else{
                linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
                linkedNodes[currentNode.name].previous = name;
                linkedNodes[previousNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
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
                if ((_index==0 && offers[currentNode.hash].price >= _price) || (_index==1 && offers[currentNode.hash].price <= _price)){
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
            }
            //falls somewhere in the middle of the list
            else {
                linkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                linkedNodes[nextNode.name].previous = name;
                linkedNodes[currentNode.name].next = name;
                emit offerPosted(name, offers[hash].maturity, offers[hash].legsHash, offers[hash].price, offers[hash].amount, _index);
            }
        }
        payFee();
    }

    /*
        @Description: removes the order with name identifier _name, prevents said order from being filled or taken

        @param bytes32: the identifier of the node which stores the order to cancel, offerToCancel == offers[linkedNodes[_name].hash]
    */
    function cancelOrderInternal(bytes32 _name) internal {
        linkedNode memory node = linkedNodes[_name];
        require(msg.sender == offers[node.hash].offerer);
        Offer memory offer = offers[node.hash];
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
            uint req = uint(int(offer.amount) * (pos.maxStrikeAssetHolder + offer.price));
            if (int(req) > 0)
                strikeAssetDeposits[offer.offerer] += req/strikeAssetSubUnits;
        }
        else {
            uint req = uint(int(offer.amount) * (pos.maxStrikeAssetDebtor - offer.price));
            if (int(req) > 0)
                strikeAssetDeposits[offer.offerer] += req/strikeAssetSubUnits;
        }

    }
    

    /*
        @Description: cancel order of specific identifier

        @param bytes32 _name: the hash to find the offer's linked node in linkedNodes[]
    */
    function cancelOrder(bytes32 _name) public {
        require(msg.sender == offers[linkedNodes[_name].hash].offerer);
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
        require(offer.index == 0);

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
        require(offer.index==1);

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.assignPosition
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
        @param uint8 _maxInterations: the maximum amount of calls to mintPosition

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) public returns(uint unfilled){
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));

        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][0]];
        Offer memory offer = offers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (msg.sender == offer.offerer) {
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call mintPosition
                    */
                    position memory pos = positions[offer.legsHash];
                    uint req = uint(int(_amount) * (pos.maxStrikeAssetHolder + offer.price));
                    if (int(req) > 0)
                        strikeAssetDeposits[msg.sender] += req/strikeAssetSubUnits;
                }
                else {
                    bool success = mintPosition(msg.sender, offer.offerer, offer.maturity, offer.legsHash, _amount, offer.price, offer.index);
                    if (!success) return _amount;

                }
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                return 0;
            }
            if (!takeBuyOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_legsHash][0]];
            offer = offers[node.hash];
            _maxIterations--;
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
        @param uint8 _maxInterations: the maximum amount of calls to mintPosition

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) public returns (uint unfilled){
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));

        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][1]];
        Offer memory offer = offers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price <= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call mintPosition
                    */
                    position memory pos = positions[offer.legsHash];
                    uint req = uint(int(_amount) * (pos.maxStrikeAssetDebtor - offer.price));
                    if (int(req) > 0)
                        strikeAssetDeposits[msg.sender] += req/strikeAssetSubUnits;
                }
                else {
                    bool success = mintPosition(offer.offerer, msg.sender, offer.maturity, offer.legsHash, _amount, offer.price, offer.index);
                    if (!success) return _amount;
                }
                offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                return 0;
            }
            if (!takeSellOffer(msg.sender, node.name)) return _amount;
            _amount-=offer.amount;
            //find the next offer
            node = linkedNodes[listHeads[_maturity][_legsHash][1]];
            offer = offers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }

    /*
        @Description: mint a specific position between two users

        @param address _ debtor: the address selling the position
        @param address _holder: the address buying the position
        @param uint _maturity: the maturity of the position to mint
        @param bytes32 _legsHash: the identifier to find the position in positions[]
        @param uint _amount: the amount of times to mint the position
        @param int _price: the premium paid by the holder to the debtor
        @param uint8 _index: the index of the offer for which this function is called
    */
    function mintPosition(address _debtor, address _holder, uint _maturity, bytes32 _legsHash, uint _amount, int _price, uint8 _index) internal returns(bool success){
        /*
            debtor pays is true if debtor is making the market order and thus debtor must provide the necessary collateral
                whereas the holder has already provided the necessary collateral
                this means that the debtor recieves the price premium
        */

        address _optionsAddress = optionsAddress; //gas savings
        options optionsContract = options(_optionsAddress);
        position memory pos = positions[_legsHash];
        optionsContract.setParams(_debtor, _holder, _maturity);
        //load put position into register
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.putAmounts.length; i++)
            optionsContract.addPosition(pos.putStrikes[i], int(_amount)*pos.putAmounts[i], false);
        optionsContract.setTrustedAddressMultiLegExchange(1);

        uint _strikeAssetSubUnits = strikeAssetSubUnits;    //gas savings

        int premium;
        {
            uint totalReq;
            uint holderReq;

            {
                //accounting for holder and debtor must be done seperately as that is how it is done in the options handler
                uint temp = _amount * uint(pos.maxStrikeAssetHolder);
                holderReq = temp/_strikeAssetSubUnits + (temp%_strikeAssetSubUnits == 0 ? 0 : 1);
                totalReq = holderReq;

                temp = _amount * uint(pos.maxStrikeAssetDebtor);
                totalReq += temp/_strikeAssetSubUnits + (temp%_strikeAssetSubUnits == 0 ? 0 : 1);
            }


            /*
                pos refers to the state of pos after the reassignment of its members

                pos.maxStrikeAssetHolder = holderReq + premium
                
                premium = pos.maxStrikeAssetHolder - holderReq
            */

            if (_index == 0) {
                pos.maxStrikeAssetHolder = int(_amount) * (pos.maxStrikeAssetHolder + _price) / int(_strikeAssetSubUnits);
                pos.maxStrikeAssetDebtor = int(totalReq) - pos.maxStrikeAssetHolder;
            } else {
                pos.maxStrikeAssetDebtor = int(_amount) * (pos.maxStrikeAssetDebtor - _price) / int(_strikeAssetSubUnits);
                pos.maxStrikeAssetHolder = int(totalReq) - pos.maxStrikeAssetDebtor;
            }
            premium = pos.maxStrikeAssetHolder - int(holderReq);
        }
        optionsContract.setLimits(pos.maxStrikeAssetDebtor, pos.maxStrikeAssetHolder);

        optionsContract.setPaymentParams(_index==0, premium);

        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignPutPosition()"));
        if (!success) return false;

        int transferAmount;
        if (_index==0){
            address addr = _holder; //prevent stack too deep
            transferAmount = optionsContract.transferAmountHolder();
            strikeAssetDeposits[addr] += uint(pos.maxStrikeAssetHolder - transferAmount);
        } else {
            address addr = _debtor; //prevent stack too deep
            transferAmount = optionsContract.transferAmountDebtor();
            strikeAssetDeposits[addr] += uint(pos.maxStrikeAssetDebtor - transferAmount);
        }
        scReserves = uint(int(scReserves)-transferAmount);
    }


}