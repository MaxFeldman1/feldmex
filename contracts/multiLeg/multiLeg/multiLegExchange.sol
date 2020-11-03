pragma solidity >=0.6.0;
import "../../interfaces/IERC20.sol";
import "../../optionsHandler/options.sol";
import "./mLegData.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract multiLegExchange is mLegData {

    function viewClaimed(bool _token) public view returns(uint ret){ret = _token? claimedToken[msg.sender] : claimedStable[msg.sender];}


    /*
        @Description: returns arrays callAmounts and callStrikes of a given position

        @param bytes32 _legsHash: the hash leading to the positions

        @return int[] memory callAmounts: position.callAmounts
        @return uint[] memory callStrikes: position.callStrikes
        @return int[] memory putAmounts: position.putAmounts
        @return uint[] memory putStrikes: position.putStrikes
    */
    function positionInfo(bytes32 _legsHash) public view returns(int[] memory callAmounts, uint[] memory callStrikes, int[] memory putAmounts, uint[] memory putStrikes){
        position memory pos = positions[_legsHash];
        callAmounts = pos.callAmounts;
        callStrikes = pos.callStrikes;
        putAmounts = pos.putAmounts;
        putStrikes = pos.putStrikes;
    }

    /*
        @Description: add new position to enable trading on said position

        @param uint[] memory _callStrikes: the strikes of the call positions
        @param int[] memory _callAmounts: the amount of the call positons at the various strikes in _callStrikes
        @param uint[] memory _putStrikes: the strikes of the put positions
        @param int[] memory _putAmounts: the amount of the put positons at the various strikes in _putStrikes
    */
    function addLegHash(uint[] memory _callStrikes, int[] memory _callAmounts, uint[] memory _putStrikes, int[] memory _putAmounts) public {
        //make sure that this is a multi leg order
        require(_callAmounts.length > 0 && _putAmounts.length > 0);
        require(_callAmounts.length==_callStrikes.length&&_putAmounts.length==_putStrikes.length);
        bytes32 hash = keccak256(abi.encodePacked(_callStrikes, _callAmounts, _putStrikes, _putAmounts));
        options optionsContract = options(optionsAddress);
        uint prevStrike;
        int _subUnits = int(satUnits);  //gas savings
        //load position
        optionsContract.clearPositions();
        for (uint i = 0; i < _callAmounts.length; i++){
            require(prevStrike < _callStrikes[i] && _callAmounts[i] != 0);
            prevStrike = _callStrikes[i];
            optionsContract.addPosition(_callStrikes[i], _subUnits*_callAmounts[i], true);
        }
        (uint maxUnderlyingAssetDebtor, uint maxUnderlyingAssetHolder) = optionsContract.transferAmount(true);

        prevStrike = 0;
        _subUnits = int(scUnits);    //gas savings
        optionsContract.clearPositions();
        for (uint i = 0; i < _putAmounts.length; i++){
            require(prevStrike < _putStrikes[i] && _putAmounts[i] != 0);
            prevStrike = _putStrikes[i];
            optionsContract.addPosition(_putStrikes[i], _subUnits*_putAmounts[i], false);
        }
        (uint maxStrikeAssetDebtor, uint maxStrikeAssetHolder) = optionsContract.transferAmount(false);
        position memory pos = position(_callAmounts, _callStrikes, _putAmounts, _putStrikes, maxUnderlyingAssetDebtor, maxUnderlyingAssetHolder, maxStrikeAssetDebtor, maxStrikeAssetHolder);
        positions[hash] = pos;
        emit legsHashCreated(hash);
    }
        
    /*
        @Description: setup
    */
    constructor (address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress, address _delegateAddress, address _feeOracleAddress) public {
        underlyingAssetAddress = _underlyingAssetAddress;
        optionsAddress = _optionsAddress;
        strikeAssetAddress = _strikeAssetAddress;
        delegateAddress = _delegateAddress;
        feeOracleAddress = _feeOracleAddress;
        IERC20 ua = IERC20(underlyingAssetAddress);
        satUnits = 10 ** uint(ua.decimals());
        ua.approve(optionsAddress, 2**255);
        IERC20 sa = IERC20(strikeAssetAddress);
        scUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the claimedToken and claimedStable mappings

        @param uint _to: the address to which to credit deposited funds

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(address _to) public returns(bool success){
        uint balance = IERC20(underlyingAssetAddress).balanceOf(address(this));
        uint sats = balance - satReserves;
        satReserves = balance;
        balance = IERC20(strikeAssetAddress).balanceOf(address(this));
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
            IERC20 ua = IERC20(underlyingAssetAddress);
            claimedToken[msg.sender] = 0;
            success = ua.transfer(msg.sender, val);
            satReserves -= val;
        }
        else {
            uint val = claimedStable[msg.sender];
            IERC20 sa = IERC20(strikeAssetAddress);
            claimedStable[msg.sender] = 0;
            success = sa.transfer(msg.sender, val);
            scReserves -= val;
        }
        assert(success);

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
        for (uint i = 0; i < pos.callStrikes.length; i++){
            if (!optionsContract.containedStrikes(msg.sender, _maturity, pos.callStrikes[i])) return false;
        }
        for (uint i = 0; i < pos.putStrikes.length; i++){
            if (!optionsContract.containedStrikes(msg.sender, _maturity, pos.putStrikes[i])) return false;
        }
        contains = true;
    }


    /*
        @Description: pay fee to feldmex token address
    */
    function payFee() internal {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("payFee()"));
        require(success);
    }


    /*
        @Description: lock up collateral necessary to post an order in the order book
            also any call with a non registered legs hash will be reverted

        @position pos: the multi leg position which collateral is being posted for
        @int _price: the premium which is to be paid per position
        @uint _amount: the amount of the position for which collateral is being posted
        @uint8 _index: index of the order being posted
    */
    function lockCollateral(bytes32 _legsHash, int _price, uint _amount, uint8 _index) internal {
        // debtors are paid premium by holders
        if (_index%2 == 1) _price *= -1;

        position memory pos = positions[_legsHash];

        //lock collateral for calls
        uint req = _amount * uint(
            int(_index%2 == 0 ? pos.maxUnderlyingAssetHolder : pos.maxUnderlyingAssetDebtor)
            + (_index < 2 ? _price : 0)
            );
        if (int(req) > 0) {
            uint _satUnits = satUnits;  //gas savings
            req = req/_satUnits + (req%_satUnits == 0 ? 0 : 1);
            require(claimedToken[msg.sender] >= req);
            claimedToken[msg.sender] -= req;
        }

        //lock collateral for puts
        req = _amount * uint(
            int(_index%2 == 0 ? pos.maxStrikeAssetHolder : pos.maxStrikeAssetDebtor)
            + (_index < 2 ? 0 : _price)
            );
        if (int(req) > 0) {
            uint _scUnits = scUnits;    //gas savings
            req = req/_scUnits + (req%_scUnits == 0 ? 0 : 1);
            require(claimedStable[msg.sender] >= req);
            claimedStable[msg.sender] -= req;
        }
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
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) public payable {
        require(_maturity != 0 && _legsHash != 0 && _amount != 0);

        if (listHeads[_maturity][_legsHash][_index] != 0) {
            insertOrder(_maturity, _legsHash, _price, _amount, _index, listHeads[_maturity][_legsHash][_index]);
            return;
        }
        //only continue execution here if listHead[_maturity][_legsHash][index] == 0

        require(containsStrikes(_maturity, _legsHash));

        // any call with a non registered legs hash will be reverted
        lockCollateral(_legsHash, _price, _amount, _index);

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
        @param bool _buy: if true this is a buy order if false this is a sell order
        @param bool _call: if true this is a call order if false this is a put order 
        @param bytes32 _name: the name identifier of the order from which to search for the location to insert this order
    */
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) public payable {
        //make sure the offer and node corresponding to the name is in the correct list
        require(offers[linkedNodes[_name].hash].maturity == _maturity && offers[linkedNodes[_name].hash].legsHash == _legsHash && _maturity != 0 &&  _legsHash != 0);
        require(offers[linkedNodes[_name].hash].index == _index);

        require(containsStrikes(_maturity, _legsHash));

        // any call with a non registered legs hash will be reverted
        lockCollateral(_legsHash, _price, _amount, _index);

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
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("cancelOrderInternal(bytes32)",_name));
        assert(success);
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
    function takeBuyOffer(address _seller, bytes32 _name) public returns(bool success){
        taker = _seller;
        name = _name;
        (success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("takeBuyOffer()"));
        assert(success);
    }

    /*
        @Description: handles logistics of the buyer accepting a sell order with the identifier _name

        @param address _buyer: the buyer that is taking the sell offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == offers[linkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeSellOffer(address _buyer, bytes32 _name) public returns(bool success){
        taker = _buyer;
        name = _name;
        (success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("takeSellOffer()"));
        assert(success);
    }

    /*
        @Description: Caller of the function takes the best buy offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param uint8 _maxInterations: the maximum amount of calls to mintPosition
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _call) public returns(uint unfilled){
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));
        //ensure all strikes are contained
        uint8 index = (_call? 0: 2);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][index]];
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
                    if (offer.index == 0){
                        uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetHolder) + offer.price));
                        if (int(req) > 0)
                            claimedToken[msg.sender] += req / satUnits;
                        claimedStable[msg.sender] += _amount * pos.maxStrikeAssetHolder / scUnits;
                    } else {
                        claimedToken[msg.sender] += _amount * pos.maxUnderlyingAssetHolder / satUnits;
                        uint req = uint(int(_amount) * (int(pos.maxStrikeAssetHolder) + offer.price));
                        if (int(req) > 0)
                            claimedStable[msg.sender] += req / scUnits;
                    }
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
            node = linkedNodes[listHeads[_maturity][_legsHash][index]];
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
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _call) public returns (uint unfilled){
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));
        //ensure all strikes are contained
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = linkedNodes[listHeads[_maturity][_legsHash][index]];
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
                    if (offer.index == 1){
                        uint req = uint(int(_amount) * (int(pos.maxUnderlyingAssetDebtor) - offer.price));
                        if (int(req) > 0)
                            claimedToken[msg.sender] += req / satUnits;
                        claimedStable[msg.sender] += _amount * pos.maxStrikeAssetDebtor / scUnits;
                    } else {
                        claimedToken[msg.sender] += _amount * pos.maxUnderlyingAssetDebtor / satUnits;
                        uint req = uint(int(_amount) * (int(pos.maxStrikeAssetDebtor) - offer.price));
                        if (int(req) > 0)
                        claimedStable[msg.sender] += req / scUnits;
                    }
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
            node = linkedNodes[listHeads[_maturity][_legsHash][index]];
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
        debtor = _debtor;
        holder = _holder;
        maturity = _maturity;
        legsHash = _legsHash;
        amount = _amount;
        price = _price;
        index = _index;
        (success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("mintPosition()"));
    }


}