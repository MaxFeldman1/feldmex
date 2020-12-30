pragma solidity >=0.8.0;
import "../interfaces/IERC20.sol";
import "../interfaces/IOptionsHandler.sol";
import "../interfaces/ISingleLegExchange.sol";
import "../feeOracle.sol";
import "./SingleLegData.sol";

/*
    Due to contract size limitations we cannot add error strings in require statements in this contract
*/
contract SingleLegExchange is ISingleLegExchange, SingleLegData {

    /*  
        @Description: set up
    */
    constructor (
        address _underlyingAssetAddress,
        address _strikeAssetAddress,
        address _optionsAddress,
        address _feeOracleAddress,
        address _delegateAddress
        ) {
        
        underlyingAssetAddress = _underlyingAssetAddress;
        optionsAddress = _optionsAddress;
        strikeAssetAddress = _strikeAssetAddress;
        feeOracleAddress = _feeOracleAddress;
        delegateAddress = _delegateAddress;
        IERC20 ua = IERC20(underlyingAssetAddress);
        underlyingAssetSubUnits = 10 ** uint(ua.decimals());
        ua.approve(optionsAddress, 2**255);
        IERC20 sa = IERC20(strikeAssetAddress);
        strikeAssetSubUnits = 10 ** uint(sa.decimals());
        sa.approve(optionsAddress, 2**255);
    }
    
    /*
        @Description: deposit funds in this contract, funds tracked by the _underlyingAssetDeposits and _strikeAssetDeposits mappings

        @param uint _to: the address to which to credit deposited funds

        @return bool success: if an error occurs returns false if no error return true
    */
    function depositFunds(address _to) external override returns(bool success){
        uint balance = IERC20(underlyingAssetAddress).balanceOf(address(this));
        uint sats = balance - satReserves;
        satReserves = balance;
        balance = IERC20(strikeAssetAddress).balanceOf(address(this));
        uint sc = balance - scReserves;
        scReserves = balance;
        _underlyingAssetDeposits[_to] += sats;
        _strikeAssetDeposits[_to] += sc;
        success = true;
    }

    /*
        @Description: send back all funds tracked in the _underlyingAssetDeposits and _strikeAssetDeposits mappings of the caller to the callers address

        @param bool _token: if true withdraw the tokens recorded in _underlyingAssetDeposits if false withdraw the strike asset stored in _strikeAssetDeposits

        @return bool success: if an error occurs returns false if no error return true
    */
    function withdrawAllFunds(bool _token) external override returns(bool success){
        if (_token){
            uint val = _underlyingAssetDeposits[msg.sender];
            IERC20 ua = IERC20(underlyingAssetAddress);
            _underlyingAssetDeposits[msg.sender] = 0;
            success = ua.transfer(msg.sender, val);
            satReserves -= val;
        }
        else {
            uint val = _strikeAssetDeposits[msg.sender];
            IERC20 sa = IERC20(strikeAssetAddress);
            _strikeAssetDeposits[msg.sender] = 0;
            success = sa.transfer(msg.sender, val);
            scReserves -= val;
        }

    }
    
    /*
        @Description: creates two hashes to be keys in the _linkedNodes and the _offers mapping

        @param Offer _offer: the offer for which to make the identifiers

        @return bytes32 _hash: key in _offers mapping
        @return bytes32 _name: key in _linkedNodes mapping
    */
    function hasher(Offer memory _offer) internal returns(bytes32 _hash, bytes32 _name){
        _hash =  keccak256(abi.encodePacked(_offer.maturity, _offer.strike, _offer.price, _offer.offerer, _offer.index, totalOrders));
        totalOrders++;
        _name = keccak256(abi.encodePacked(_hash, totalOrders));
    }


    /*
        @Description: pay fee to feldmex token address
    */
    function payFee() internal {
        feeOracle fo = feeOracle(feeOracleAddress);
        if (fo.isFeeImmune(optionsAddress, msg.sender)) return;
        uint fee = fo.exchangeFlatEtherFee();
        require(msg.value >= fee);
        payable(msg.sender).transfer(msg.value-fee);
        payable(fo.feldmexTokenAddress()).transfer(fee);
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
    function postOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call) external override payable {
        require(_maturity != 0 && _price != 0 && _price < (_call? underlyingAssetSubUnits: _strike) && _strike != 0);
        require((IOptionsHandler(optionsAddress)).contains(msg.sender, _maturity, _strike));
        uint8 index = (_buy? 0 : 1) + (_call? 0 : 2);
        if (_listHeads[_maturity][_strike][index] != 0) {
            insertOrder(_maturity, _strike, _price, _amount, _buy, _call, _listHeads[_maturity][_strike][index]);
            return;
        }
        //only continue execution here if listHead[_maturity][_strike][index] == 0
        if (index == 0){
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            uint req = _price* _amount;
            req = req/_underlyingAssetSubUnits + (req%_underlyingAssetSubUnits == 0 ? 0 : 1);
            require(_underlyingAssetDeposits[msg.sender] >= req);
            _underlyingAssetDeposits[msg.sender] -= req;
        }
        else if (index == 1){
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            uint req = _amount * (underlyingAssetSubUnits - _price);
            req = req/_underlyingAssetSubUnits + (req%_underlyingAssetSubUnits == 0 ? 0 : 1);
            require(_underlyingAssetDeposits[msg.sender] >= req);
            _underlyingAssetDeposits[msg.sender] -= req;
        }
        else if (index == 2){
            uint _strikeAssetSubUnits = strikeAssetSubUnits;  //gas savings
            uint req = _price* _amount;
            req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
            require(_strikeAssetDeposits[msg.sender] >= req);
            _strikeAssetDeposits[msg.sender] -= req;
        }
        else {
            /*
                because:
                    inflator == strikeAssetSubUnits && _strike == inflator * nonInflatedStrike
                therefore:
                    _amount * (strikeAssetSubUnits * nonInflatedStrike - price) ==
                    _amount * (strikeAssetSubUnits * (_strike /inflator) - price) ==
                    _amount * (_strike - price)
                
            */
            uint _strikeAssetSubUnits = strikeAssetSubUnits;  //gas savings
            uint req = _amount * (_strike - _price);
            req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
            require(_strikeAssetDeposits[msg.sender] >= req);
            _strikeAssetDeposits[msg.sender] -= req;
        }
        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //place order in the mappings
        _offers[hash] = offer;
        _linkedNodes[name] = linkedNode(hash, name, 0, 0);
        _listHeads[_maturity][_strike][index] = name;
        payFee();
        emit offerPosted(name, _offers[hash].maturity, _offers[hash].strike, _offers[hash].price, _offers[hash].amount, index);
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
    function insertOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call, bytes32 _name) public override payable {
        //make sure the offer and node corresponding to the name is in the correct list
        require(_offers[_linkedNodes[_name].hash].maturity == _maturity && _offers[_linkedNodes[_name].hash].strike == _strike && _maturity != 0 && _price != 0 && _price < (_call? underlyingAssetSubUnits: _strike) && _strike != 0);
        uint8 index = (_buy? 0 : 1) + (_call? 0 : 2);
        require(_offers[_linkedNodes[_name].hash].index == index);
        require((IOptionsHandler(optionsAddress)).contains(msg.sender, _maturity, _strike));
        if (index == 0){
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            uint req = _price* _amount;
            req = req/_underlyingAssetSubUnits + (req%_underlyingAssetSubUnits == 0 ? 0 : 1);
            require(_underlyingAssetDeposits[msg.sender] >= req);
            _underlyingAssetDeposits[msg.sender] -= req;
        }
        else if (index == 1){
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            uint req = _amount * (underlyingAssetSubUnits - _price);
            req = req/_underlyingAssetSubUnits + (req%_underlyingAssetSubUnits == 0 ? 0 : 1);
            require(_underlyingAssetDeposits[msg.sender] >= req);
            _underlyingAssetDeposits[msg.sender] -= req;
        }
        else if (index == 2){
            uint _strikeAssetSubUnits = strikeAssetSubUnits;  //gas savings
            uint req = _price* _amount;
            req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
            require(_strikeAssetDeposits[msg.sender] >= req);
            _strikeAssetDeposits[msg.sender] -= req;
        }
        else {
            uint _strikeAssetSubUnits = strikeAssetSubUnits;  //gas savings
            uint req = _amount * (_strike - _price);
            req = req/_strikeAssetSubUnits + (req%_strikeAssetSubUnits == 0 ? 0 : 1);
            require(_strikeAssetDeposits[msg.sender] >= req);
            _strikeAssetDeposits[msg.sender] -= req;
        }

        Offer memory offer = Offer(msg.sender, _maturity, _strike, _price, _amount, index);
        //get hashes
        (bytes32 hash, bytes32 name) = hasher(offer);
        //if we need to traverse down the list further away from the list head
        linkedNode memory currentNode = _linkedNodes[_name];
        if ((_buy &&  _offers[currentNode.hash].price >= _price) || (!_buy  && _offers[currentNode.hash].price <= _price)){
            linkedNode memory previousNode;
            while (currentNode.name != 0){
                previousNode = currentNode;
                currentNode = _linkedNodes[currentNode.next];
                if ((_buy && _offers[currentNode.hash].price < _price) || (!_buy && _offers[currentNode.hash].price > _price)){
                    break;
                }
            }
            _offers[hash] = offer;
            //if this is the last node
            if (currentNode.name == 0){
                _linkedNodes[name] = linkedNode(hash, name, 0, previousNode.name);
                _linkedNodes[currentNode.name].previous = name;
                _linkedNodes[previousNode.name].next = name;
                emit offerPosted(name, _offers[hash].maturity, _offers[hash].strike, _offers[hash].price, _offers[hash].amount, index);
            }
            //it falls somewhere in the middle of the chain
            else{
                _linkedNodes[name] = linkedNode(hash, name, currentNode.name, previousNode.name);
                _linkedNodes[currentNode.name].previous = name;
                _linkedNodes[previousNode.name].next = name;
                emit offerPosted(name, _offers[hash].maturity, _offers[hash].strike, _offers[hash].price, _offers[hash].amount, index);
            }

        }
        //here we traverse up towards the list head
        else {
            /*  node node should == _linkedNodes[currentNode.next]
                do not be confused by the fact that is lags behind in the loop and == the value of currentNode in the previous iteration
            */
            linkedNode memory nextNode;
            while (currentNode.name != 0){
                nextNode = currentNode;
                currentNode = _linkedNodes[currentNode.previous];
                if ((_buy && _offers[currentNode.hash].price >= _price) || (!_buy && _offers[currentNode.hash].price <= _price)){
                    break;
                }
            }
            _offers[hash] = offer;
            //if this is the list head
            if (currentNode.name == 0){
                //nextNode is the head befoe execution of this local scope
                _linkedNodes[name] = linkedNode(hash, name, nextNode.name, 0);
                _linkedNodes[nextNode.name].previous = name;
                _listHeads[_maturity][_strike][index] = name;
                emit offerPosted(name, _offers[hash].maturity, _offers[hash].strike, _offers[hash].price, _offers[hash].amount, index);
            }
            //falls somewhere in the middle of the list
            else {
                _linkedNodes[name] = linkedNode(hash, name, nextNode.name, currentNode.name);
                _linkedNodes[nextNode.name].previous = name;
                _linkedNodes[currentNode.name].next = name;
                emit offerPosted(name, _offers[hash].maturity, _offers[hash].strike, _offers[hash].price, _offers[hash].amount, index);
            }
        }
        payFee();
    }

    /*
        @Description: removes the order with name identifier _name, prevents said order from being filled or taken

        @param bytes32: the identifier of the node which stores the order to cancel, offerToCancel == _offers[_linkedNodes[_name].hash]
    */
    function cancelOrder(bytes32 _name) external override {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("cancelOrder(bytes32)", _name));
        require(success);
    }


    /*
        @Description: Caller of the function takes the best buy _offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: lowest price to sell at
        @param uint _amount: the amount of calls or puts that this order is for
        @param uint8 _maxInterations: the maximum amount of calls to mintCall/mintPut
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketSell(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external override returns (uint _unfilled) {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("marketSell(uint256,uint256,uint256,uint256,uint8,bool)",
            _maturity,
            _strike,
            _limitPrice,
            _amount,
            _maxIterations,
            _call
        ));
        require(success);
        _unfilled = unfilled;
    }

    /*
        @Description: Caller of the function takes the best sell _offers of either calls or puts, when offer is taken the contract in options.sol is called to mint the calls or puts
            After an offer is taken it is removed so that it may not be taken again

        @param unit _maturity: the timstamp at which the call or put is settled
        @param uint _strike: the settlement price of the the underlying asset at the maturity
        @param uint _limitPrice: highest price to buy at
        @param uint _amount: the amount of calls or puts that this order is for
        @param uint8 _maxInterations: the maximum amount of calls to mintCall/mintPut
        @param bool _call: if true this is a call order if false this is a put order 

        @return uint unfilled: total amount of options requested in _amount parameter that were not minted
    */
    function marketBuy(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external override returns (uint _unfilled) {
        (bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("marketBuy(uint256,uint256,uint256,uint256,uint8,bool)",
            _maturity,
            _strike,
            _limitPrice,
            _amount,
            _maxIterations,
            _call
        ));
        require(success);
        _unfilled = unfilled;
    }

    //-----------------------------------------v-i-e-w-s------------------------------------
    function underlyingAssetDeposits(address _owner) external view override returns (uint) {
        return _underlyingAssetDeposits[_owner];
    }
    function strikeAssetDeposits(address _owner) external view override returns (uint) {
        return _strikeAssetDeposits[_owner];
    }
    function listHeads(uint _maturity, uint _strike, uint _index) external view override returns (bytes32) {
        return _listHeads[_maturity][_strike][_index];
    }
    function linkedNodes(bytes32 _name) external view override returns (bytes32 hash, bytes32 name, bytes32 next, bytes32 previous) {
        linkedNode memory node = _linkedNodes[_name];
        hash = node.hash;
        name = node.name;
        next = node.next;
        previous = node.previous;
    }

    function offers(bytes32 _hash) external view override returns (address offerer, uint maturity, uint strike, uint price, uint amount, uint8 index) {
        Offer memory offer = _offers[_hash];
        offerer = offer.offerer;
        maturity = offer.maturity;
        strike = offer.strike;
        price = offer.price;
        amount = offer.amount;
        index = offer.index;
    }

}