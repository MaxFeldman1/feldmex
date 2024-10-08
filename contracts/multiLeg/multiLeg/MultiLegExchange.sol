pragma solidity >=0.8.0;
import "../../interfaces/IERC20.sol";
import "../../interfaces/IOptionsHandler.sol";
import "../../interfaces/IMultiLegExchange.sol";
import "./mLegData.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract MultiLegExchange is mLegData, IMultiLegExchange {

    /*
        @Description: returns arrays callAmounts and callStrikes of a given position

        @param bytes32 _legsHash: the hash leading to the internalPositions

        @return int[] memory callAmounts: position.callAmounts
        @return uint[] memory callStrikes: position.callStrikes
        @return int[] memory putAmounts: position.putAmounts
        @return uint[] memory putStrikes: position.putStrikes
        @return int maxUnderlyingAssetDebtor: position.maxUnderlyingAssetDebtor
        @return int maxUnderlyingAssteHolder: position.maxUnderlyingAssetHolder
        @return int maxStrikeAssetDebtor: position.maxStrikeAssetDebtor
        @return int maxStrikeAssetHolder: position.maxStrikeAssetHolder
    */
    function positions(bytes32 _legsHash) public override view returns (
            int[] memory callAmounts,
            uint[] memory callStrikes,
            int[] memory putAmounts,
            uint[] memory putStrikes,
            int maxUnderlyingAssetDebtor,
            int maxUnderlyingAssetHolder,
            int maxStrikeAssetDebtor,
            int maxStrikeAssetHolder
        ){
        
        position memory pos = internalPositions[_legsHash];
        callAmounts = pos.callAmounts;
        callStrikes = pos.callStrikes;
        putAmounts = pos.putAmounts;
        putStrikes = pos.putStrikes;
        maxUnderlyingAssetDebtor = pos.maxUnderlyingAssetDebtor;
        maxUnderlyingAssetHolder = pos.maxUnderlyingAssetHolder;
        maxStrikeAssetDebtor = pos.maxStrikeAssetDebtor;
        maxStrikeAssetHolder = pos.maxStrikeAssetHolder;
    }

    /*
        @Description: add new position to enable trading on said position

        @param uint[] memory _callStrikes: the strikes of the call internalPositions
        @param int[] memory _callAmounts: the amount of the call positons at the various strikes in _callStrikes
        @param uint[] memory _putStrikes: the strikes of the put internalPositions
        @param int[] memory _putAmounts: the amount of the put positons at the various strikes in _putStrikes
    */
    function addLegHash(
        uint[] memory _callStrikes,
        int[] memory _callAmounts,
        uint[] memory _putStrikes,
        int[] memory _putAmounts
        ) public override {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("addLegHash(uint256[],int256[],uint256[],int256[])", _callStrikes, _callAmounts, _putStrikes, _putAmounts));
        require(success);
    }
        
    /*
        @Description: setup
    */
    constructor (address _underlyingAssetAddress, address _strikeAssetAddress, address _optionsAddress, address _delegateAddress, address _feeOracleAddress) {
        underlyingAssetAddress = _underlyingAssetAddress;
        optionsAddress = _optionsAddress;
        strikeAssetAddress = _strikeAssetAddress;
        delegateAddress = _delegateAddress;
        feeOracleAddress = _feeOracleAddress;
        IERC20 ua = IERC20(underlyingAssetAddress);
        underlyingAssetSubUnits = 10 ** uint(ua.decimals());
        ua.approve(optionsAddress, 2**255);
        IERC20 sa = IERC20(strikeAssetAddress);
        strikeAssetSubUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the internalUnderlyingAssetDeposits and internalStrikeAssetDeposits mappings

        @param uint _to: the address to which to credit deposited funds

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(address _to) public override returns (bool success){
        uint balance = IERC20(underlyingAssetAddress).balanceOf(address(this));
        uint sats = balance - internalUnderlyingAssetReserves;
        internalUnderlyingAssetReserves = balance;
        balance = IERC20(strikeAssetAddress).balanceOf(address(this));
        uint sc = balance - internalStrikeAssetReserves;
        internalStrikeAssetReserves = balance;
        internalUnderlyingAssetDeposits[_to] += sats;
        internalStrikeAssetDeposits[_to] += sc;
        success = true;
    }

    /*
        @Description: send back all funds tracked in the internalUnderlyingAssetDeposits and internalStrikeAssetDeposits mappings of the caller to the callers address

        @param bool _token: if true withdraw the tokens recorded in internalUnderlyingAssetDeposits if false withdraw the legsHash asset stored in internalStrikeAssetDeposits

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds(bool _token) public override {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("withdrawAllFunds(bool)", _token));
        require(success);
    }

    /*
        @Description: creates two hashes to be keys in the internalLinkedNodes and the internalOffers mapping

        @param Offer _offer: the offer for which to make the identifiers

        @return bytes32 _hash: key in internalOffers mapping
        @return bytes32 _name: key in internalLinkedNodes mapping
    */
    function hasher(Offer memory _offer) internal returns(bytes32 _hash, bytes32 _name){
        _hash =  keccak256(abi.encodePacked(_offer.maturity, _offer.legsHash, _offer.price, _offer.offerer, _offer.index, totalOrders));
        totalOrders++;
        _name = keccak256(abi.encodePacked(_hash, totalOrders));
    }


    /*
        @Description: checks if all strikes from _legsHash are contained by msg.sender in the options exchange

        @param uint _maturity: the maturity of the maturity strike combination in question
        @param bytes32 _legsHash: key in position mappings that leads to the position in question

        @return bool contains: true if all strikes from legsHash are contained otherwise false
    */
    function containsStrikes(uint _maturity, bytes32 _legsHash) internal view returns (bool contains) {
        position memory pos = internalPositions[_legsHash];
        IOptionsHandler optionsContract = IOptionsHandler(optionsAddress);
        for (uint i = 0; i < pos.callStrikes.length; i++){
            if (!optionsContract.contains(msg.sender, _maturity, pos.callStrikes[i])) return false;
        }
        for (uint i = 0; i < pos.putStrikes.length; i++){
            if (!optionsContract.contains(msg.sender, _maturity, pos.putStrikes[i])) return false;
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

        position memory pos = internalPositions[_legsHash];

        //lock collateral for calls
        uint req = uint(int(_amount) * (
            (_index%2 == 0 ? pos.maxUnderlyingAssetHolder : pos.maxUnderlyingAssetDebtor)
            + (_index < 2 ? _price : 0)
            ));
        if (int(req) > 0) {
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            req = req/_underlyingAssetSubUnits + (req%_underlyingAssetSubUnits == 0 ? 0 : 1);
            require(internalUnderlyingAssetDeposits[msg.sender] >= req);
            internalUnderlyingAssetDeposits[msg.sender] -= req;
        }

        //lock collateral for puts
        req = uint(int(_amount) * (
            (_index%2 == 0 ? pos.maxStrikeAssetHolder : pos.maxStrikeAssetDebtor)
            + (_index < 2 ? 0 : _price)
            ));
        if (int(req) > 0) {
            uint _strikeAssetSubUnits = strikeAssetSubUnits;    //gas savings
            req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
            require(internalStrikeAssetDeposits[msg.sender] >= req);
            internalStrikeAssetDeposits[msg.sender] -= req;
        }
    }

    /*
        @Description: creates an order and posts it in one of the 4 linked lists depending on if it is a buy or sell order and if it is for calls or puts
            unless this is the first order of its kind functionality is outsourced to insertOrder

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param uint8 _index: the index of the order to be placed
    */
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) public override payable {
        require(_maturity != 0 && _legsHash != 0 && _amount != 0);

        if (internalListHeads[_maturity][_legsHash][_index] != 0) {
            insertOrder(_maturity, _legsHash, _price, _amount, _index, internalListHeads[_maturity][_legsHash][_index]);
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
        internalOffers[hash] = offer;
        internalLinkedNodes[name] = linkedNode(hash, name, 0, 0);
        internalListHeads[_maturity][_legsHash][_index] = name;
        payFee();
        emit offerPosted(name, internalOffers[hash].maturity, internalOffers[hash].legsHash, internalOffers[hash].price, internalOffers[hash].amount, _index);
    }

    //allows for users to post Orders with a smaller gas usage by giving another order as refrence to find their orders position from
    /*
        @Description: this is the same as post order though it allows for gas to be saved by searching for the orders location in relation to another order
            this function is best called by passing in the name of an order that is directly next to the future location of your order
        
        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _price: the amount paid or received for the call or put
        @param uint _amount: the amount of calls or puts that this offer is for
        @param uint8 _index: the index of the order to be placed
        @param bytes32 _name: the name identifier of the order from which to search for the location to insert this order
    */
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) public override payable {
        //make sure the offer and node corresponding to the name is in the correct list
        require(internalOffers[internalLinkedNodes[_name].hash].maturity == _maturity && internalOffers[internalLinkedNodes[_name].hash].legsHash == _legsHash && _maturity != 0 &&  _legsHash != 0);
        require(internalOffers[internalLinkedNodes[_name].hash].index == _index);

        require(containsStrikes(_maturity, _legsHash));

        // any call with a non registered legs hash will be reverted
        lockCollateral(_legsHash, _price, _amount, _index);

        Offer memory offer = Offer(msg.sender, _maturity, _legsHash, _price, _amount, _index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //if we need to traverse down the list further away from the list head
        linkedNode memory currentNode = internalLinkedNodes[_name];
        bool _buy = _index%2==0;
        if ((_buy &&  internalOffers[currentNode.hash].price >= _price) || (!_buy  && internalOffers[currentNode.hash].price <= _price)){
            linkedNode memory previousNode;
            while (currentNode.name != 0){
                previousNode = currentNode;
                currentNode = internalLinkedNodes[currentNode.next];
                if ((_buy && internalOffers[currentNode.hash].price < _price) || (!_buy && internalOffers[currentNode.hash].price > _price)){
                    break;
                }
            }
            internalOffers[hash] = offer;
            //if this is the last node
            if (currentNode.name == 0){
                internalLinkedNodes[name] = linkedNode(hash, name, 0, previousNode.name);
                internalLinkedNodes[currentNode.name].previous = name;
                internalLinkedNodes[previousNode.name].next = name;
                emit offerPosted(name, internalOffers[hash].maturity, internalOffers[hash].legsHash, internalOffers[hash].price, internalOffers[hash].amount, _index);
            }
            //it falls somewhere in the middle of the chain
            else{
                internalLinkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
                internalLinkedNodes[currentNode.name].previous = name;
                internalLinkedNodes[previousNode.name].next = name;
                emit offerPosted(name, internalOffers[hash].maturity, internalOffers[hash].legsHash, internalOffers[hash].price, internalOffers[hash].amount, _index);
            }

        }
        //here we traverse up towards the list head
        else {
            /*  node node should == internalLinkedNodes[currentNode.next]
                do not be confused by the fact that is lags behind in the loop and == the value of currentNode in the previous iteration
            */
            linkedNode memory nextNode;
            while (currentNode.name != 0){
                nextNode = currentNode;
                currentNode = internalLinkedNodes[currentNode.previous];
                if ((_buy && internalOffers[currentNode.hash].price >= _price) || (!_buy && internalOffers[currentNode.hash].price <= _price)){
                    break;
                }
            }
            internalOffers[hash] = offer;
            //if this is the list head
            if (currentNode.name == 0){
                //nextNode is the head befoe execution of this local scope
                internalLinkedNodes[name] = linkedNode(hash, name, nextNode.name, 0);
                internalLinkedNodes[nextNode.name].previous = name;
                internalListHeads[_maturity][_legsHash][_index] = name;
                emit offerPosted(name, internalOffers[hash].maturity, internalOffers[hash].legsHash, internalOffers[hash].price, internalOffers[hash].amount, _index);
            }
            //falls somewhere in the middle of the list
            else {
                internalLinkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                internalLinkedNodes[nextNode.name].previous = name;
                internalLinkedNodes[currentNode.name].next = name;
                emit offerPosted(name, internalOffers[hash].maturity, internalOffers[hash].legsHash, internalOffers[hash].price, internalOffers[hash].amount, _index);
            }
        }
        payFee();
    }


    /*
        @Description: cancel order of specific identifier

        @param bytes32 _name: the hash to find the offer's linked node in internalLinkedNodes[]
    */
    function cancelOrder(bytes32 _name) public override {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("cancelOrder(bytes32)",_name));
        assert(success);
    }

    /*
        @Description: Caller of the function takes the best buy internalOffers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param uint8 _maxInterations: the maximum amount of calls to mintPosition
        @param bool _payInUnderlying: if true premium is paid in underlying asset if false premium is paid in strike asset

        @return uint _unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) public override returns (uint _unfilled) {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("marketSell(uint256,bytes32,int256,uint256,uint8,bool)",_maturity,_legsHash,_limitPrice,_amount,_maxIterations,_payInUnderlying));
        require(success);
        _unfilled = unfilled;
    }

    /*
        @Description: Caller of the function takes the best sell internalOffers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param bytes32 _legsHash: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: highest price to buy at
        @param uint _amount: the amount of calls or puts that this order is for
        @param uint8 _maxInterations: the maximum amount of calls to mintPosition
        @param bool _payInUnderlying: if true premium is paid in underlying asset if false premium is paid in strike asset

        @return uint _unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) public override returns (uint _unfilled) {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("marketBuy(uint256,bytes32,int256,uint256,uint8,bool)",_maturity,_legsHash,_limitPrice,_amount,_maxIterations,_payInUnderlying));
        require(success);
        _unfilled = unfilled;
    }

    //---------------------------------view functions------------------------------------------------
    function underlyingAssetDeposits(address _owner) public override view returns (uint) {return internalUnderlyingAssetDeposits[_owner];}
    function strikeAssetDeposits(address _owner) public override view returns (uint) {return internalStrikeAssetDeposits[_owner];}
    function listHeads(uint _maturity, bytes32 _legsHash, uint8 _index) public override view returns (bytes32) {return internalListHeads[_maturity][_legsHash][_index];}
    function linkedNodes(bytes32 _name) public override view returns (bytes32 hash, bytes32 name, bytes32 next, bytes32 previous) {
        linkedNode memory node = internalLinkedNodes[_name];
        hash = node.hash;
        name = node.name;
        next = node.next;
        previous = node.previous;
    }
    function offers(bytes32 _hash) public override view returns (address offerer, uint maturity, bytes32 legsHash, int price, uint amount, uint8 index) {
        Offer memory offer = internalOffers[_hash];
        offerer = offer.offerer;
        maturity = offer.maturity;
        legsHash = offer.legsHash;
        price = offer.price;
        amount = offer.amount;
        index = offer.index;
    }
    function underlyingAssetReserves() public override view returns (uint) {return internalUnderlyingAssetReserves;}
    function strikeAssetReserves() public override view returns (uint) {return internalStrikeAssetReserves;}


}