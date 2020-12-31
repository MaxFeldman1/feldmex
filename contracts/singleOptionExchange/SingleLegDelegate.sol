pragma solidity >=0.8.0;

import "../interfaces/IOptionsHandler.sol";
import "./SingleLegData.sol";

contract SingleLegDelegate is SingleLegData {

    function cancelOrder(bytes32 _name) external {
        linkedNode memory node = _linkedNodes[_name];
        require(msg.sender == _offers[node.hash].offerer);
        Offer memory offer = _offers[node.hash];
        //uint8 index = (offer.buy? 0 : 1) + (offer.call? 0 : 2);
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            _linkedNodes[node.next].previous = node.previous;
            _linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.previous == 0){
            delete _listHeads[_offers[node.hash].maturity][_offers[node.hash].strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            _linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            _linkedNodes[node.next].previous = 0;
            _listHeads[_offers[node.hash].maturity][_offers[node.hash].strike][offer.index] = node.next;
        }
        emit offerCalceled(_name);
        delete _linkedNodes[_name];
        delete _offers[node.hash];
        if (offer.index == 0)
            _underlyingAssetDeposits[msg.sender] += (offer.price * offer.amount)/underlyingAssetSubUnits;
        else if (offer.index == 1){
            uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
            _underlyingAssetDeposits[msg.sender] += (offer.amount * (_underlyingAssetSubUnits - offer.price))/_underlyingAssetSubUnits;
        }
        else if (offer.index == 2)
            _strikeAssetDeposits[msg.sender] += (offer.price * offer.amount)/strikeAssetSubUnits;
        else
            _strikeAssetDeposits[msg.sender] += (offer.amount * (offer.strike - offer.price))/strikeAssetSubUnits;
    }


    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name
        @param address _seller: the seller that is taking the buy offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == _offers[_linkedNodes[_name].hash]
        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer(address _seller, bytes32 _name) internal returns(bool success){
        linkedNode memory node = _linkedNodes[_name];
        Offer memory offer = _offers[node.hash];
        require(offer.index%2 == 0);

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (_seller == offer.offerer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            if (offer.index < 2) _underlyingAssetDeposits[_seller] += offer.price * offer.amount / underlyingAssetSubUnits;
            else _strikeAssetDeposits[_seller] += offer.price * offer.amount / strikeAssetSubUnits;
            success = true;
        }
        else if (offer.index < 2){
            (success, ) = mintCall(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, offer.price,  true);
            if (!success) return false;
        }
        else {
            (success, ) = mintPut(_seller, offer.offerer, offer.maturity, offer.strike, offer.amount, offer.price, true);
            if (!success) return false;
        }
        //repair linked list
        if (node.next != 0 && node.previous != 0){
            _linkedNodes[node.next].previous = node.previous;
            _linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete _listHeads[offer.maturity][offer.strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            _linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            _linkedNodes[node.next].previous = 0;
            _listHeads[offer.maturity][offer.strike][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete _linkedNodes[_name];
        delete _offers[node.hash];
    }

    /*
        @Description: handles logistics of the buyer accepting a sell order with the identifier _name
        @param address _buyer: the buyer that is taking the sell offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == _offers[_linkedNodes[_name].hash]
        @return bool success: if an error occurs returns false if no error return true
    */
    function takeSellOffer(address _buyer, bytes32 _name) internal returns(bool success){
        linkedNode memory node = _linkedNodes[_name];
        Offer memory offer = _offers[node.hash];
        require(offer.index%2==1);

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.mintCall/Put
            */
            if (offer.index < 2) {
                uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings
                _underlyingAssetDeposits[_buyer] += (offer.amount * (_underlyingAssetSubUnits - offer.price)) / _underlyingAssetSubUnits;
            }
            else _strikeAssetDeposits[_buyer] += (offer.amount * (offer.strike - offer.price))/strikeAssetSubUnits;
            success = true;
        }
        else if (offer.index < 2){
            (success, ) = mintCall(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.price, false);
            if (!success) return false;
        }
        else {
            (success, ) = mintPut(offer.offerer, _buyer, offer.maturity, offer.strike, offer.amount, offer.price, false);
            if (!success) return false;
        }
        //repair linked list
        if (node.next != 0 && node.previous != 0){
            _linkedNodes[node.next].previous = node.previous;
            _linkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and strike
        else if (node.next == 0 && node.next == 0){
            delete _listHeads[offer.maturity][offer.strike][offer.index];
        }
        //last node
        else if (node.next == 0){
            _linkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            _linkedNodes[node.next].previous = 0;
            _listHeads[offer.maturity][offer.strike][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete _linkedNodes[_name];
        delete _offers[node.hash];
    }



    function marketSell(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external {
        require(_strike != 0);
        require((IOptionsHandler(optionsAddress)).contains(msg.sender, _maturity, _strike));
        uint8 index = (_call? 0: 2);
        linkedNode memory node = _linkedNodes[_listHeads[_maturity][_strike][index]];
        Offer memory offer = _offers[node.hash];
        require(_listHeads[_maturity][_strike][index] != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (msg.sender == offer.offerer) {
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    if (offer.index < 2) _underlyingAssetDeposits[msg.sender] += offer.price * _amount / underlyingAssetSubUnits;
                    else _strikeAssetDeposits[msg.sender] += offer.price * _amount / strikeAssetSubUnits;
                }
                else if (_call){
                    (bool success, ) = mintCall(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, offer.price, true);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                	}
                }
                else {
                    (bool success, ) = mintPut(msg.sender, offer.offerer, offer.maturity, offer.strike, _amount, offer.price, true);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                	}
                }
                _offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                unfilled = 0;
                return;
            }
            if (!takeBuyOffer(msg.sender, node.name)) {
            	unfilled = _amount;
            	return;
            }
            _amount-=offer.amount;
            //find the next offer
            node = _linkedNodes[_listHeads[_maturity][_strike][index]];
            offer = _offers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }


    function marketBuy(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external {
        require(_strike != 0);
        require((IOptionsHandler(optionsAddress)).contains(msg.sender, _maturity, _strike));
        uint8 index = (_call ? 1 : 3);
        linkedNode memory node = _linkedNodes[_listHeads[_maturity][_strike][index]];
        Offer memory offer = _offers[node.hash];
        require(_listHeads[_maturity][_strike][index] != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price <= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call options.mintCall/Put
                    */
                    if (_call) {
                        uint _underlyingAssetSubUnits = underlyingAssetSubUnits;
                        _underlyingAssetDeposits[msg.sender] += (_amount * (_underlyingAssetSubUnits - offer.price))/_underlyingAssetSubUnits;
                    }
                    else _strikeAssetDeposits[msg.sender] += (_amount * (offer.strike - offer.price))/strikeAssetSubUnits;
                }
                else if (_call){
                    (bool success, ) = mintCall(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, offer.price, false);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                	}
                }
                else { //!call && msg.sender != offer.offerer
                    (bool success, ) = mintPut(offer.offerer, msg.sender, offer.maturity, offer.strike, _amount, offer.price, false);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                	}
                }
                _offers[node.hash].amount -= _amount;
                emit offerAccepted(node.name, _amount);
                unfilled = 0;
                return;
            }
            if (!takeSellOffer(msg.sender, node.name)) {
            	unfilled = _amount;
            	return;
            }
            _amount-=offer.amount;
            //find the next offer
            node = _linkedNodes[_listHeads[_maturity][_strike][index]];
            offer = _offers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }

    /*
        @Description: handles the logistics of creating a long call position for the holder and short call position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address _debtor: the address that collateral posted here will be associated with and the for which the call will be considered a liability
        @param address _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the call contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the strike asset at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of calls that the debtor is adding as short and the holder is adding as long
        @param uint _price: the amount of funds per call option that is to be paid in premium
        @param bool _debtorPays: == (order.index == 0)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmt: returns the amount of the underlying that was transfered from the message sender to act as collateral for the debtor
    */
    function mintCall(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _price, bool _debtorPays) internal returns (bool success, int transferAmt){
        _price*=_amount;    //price is now equal to total option premium
        address _optionsAddress = optionsAddress; //gas savings
        IOptionsHandler optionsContract = IOptionsHandler(_optionsAddress);
        uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings

        _price = _price/_underlyingAssetSubUnits + (_debtorPays || _price%_underlyingAssetSubUnits == 0 ? 0 : 1);

        optionsContract.clearPositions();
        optionsContract.addPosition(_strike, int(_amount), true);
        optionsContract.setParams(_debtor,_holder,_maturity);
        optionsContract.setPaymentParams(_debtorPays, int(_price) );
        optionsContract.setTrustedAddressMainExchange();
        optionsContract.setLimits(int( _amount) - int(_price), int(_price) );

        (success,) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return (false, 0);
        if (_debtorPays) {
            //fetch transfer amount for holder
            transferAmt = int(_price);
            /*
                We do not need to worry about debtor here because that was all handled in the options handler contract
            */
        }
        else {
            transferAmt = optionsContract.transferAmountDebtor();
            _underlyingAssetDeposits[_debtor] += uint(int(_amount) - int(_price) - transferAmt);
            /*
                We do not need to worry about holder here because that was all handled in the options handler contract
            */
        }
        satReserves = uint(int(satReserves)-transferAmt);
    }

    /*
        @Description: handles the logistics of creating a long put position for the holder and short put position for the debtor
            collateral is given by the sender of this transaction who must have already approved this contract to spend on their behalf
            the sender of this transaction does not nessecarially need to be debtor or holder as the sender provides the needed collateral this cannot harm either the debtor or holder

        @param address _debtor: the address that collateral posted here will be associated with and the for which the put will be considered a liability
        @param address _holder: the address that owns the right to the value of the option contract at the maturity
        @param uint _maturity: the evm and unix timestamp at which the put contract matures and settles
        @param uint _strike: the spot price of the underlying in terms of the strike asset at which this option contract settles at the maturity timestamp
        @param uint _amount: the amount of puts that the debtor is adding as short and the holder is adding as long
        @param uint _price: the amount of funds per put option that is to be paid in premium
        @param bool _debtorPays: == (order.index == 2)

        @return bool success: if an error occurs returns false if no error return true
        @return uint transferAmt: returns the amount of strike asset that was transfered from the message sender to act as collateral for the debtor
    */
    function mintPut(address _debtor, address _holder, uint _maturity, uint _strike, uint _amount, uint _price, bool _debtorPays) internal returns (bool success, int transferAmt){
        address _optionsAddress = optionsAddress; //gas savings
        IOptionsHandler optionsContract = IOptionsHandler(_optionsAddress);

        optionsContract.clearPositions();
        optionsContract.addPosition(_strike, int(_amount), false);
        optionsContract.setParams(_debtor,_holder,_maturity);
        optionsContract.setTrustedAddressMainExchange();

        address _d = _debtor;   //prevent stack too deep

        uint _strikeAssetSubUnits = strikeAssetSubUnits;  //gas savings
        /*
            Total Req == ceil (_amount *_strike / strikeAssetSubUnits) == debtorReq + holderReq

            When _debtorPays
                holderReq = floor ( _amount * _price / strikeAssetSubUnits)
                debtorReq = ceil (_amount *_strike / strikeAssetSubUnits) - holderReq

            When !_debtorPays
                debtorReq = floor ( _amount * (_strike - _price)) / strikeAssetSubUnits )
                holderReq = ceil (_amount *_strike / strikeAssetSubUnits) - debtorReq
        */
        uint totalReq = _amount*_strike;
        totalReq = totalReq/_strikeAssetSubUnits + (totalReq%_strikeAssetSubUnits == 0 ? 0 : 1);

        uint debtorReq;
        uint holderReq;

        if (_debtorPays) {
            holderReq =  _amount * _price / _strikeAssetSubUnits;
            debtorReq = totalReq - holderReq;
        } else {
            debtorReq =  (_amount * (_strike - _price)) / _strikeAssetSubUnits;
            holderReq = totalReq - debtorReq;
        }
        optionsContract.setPaymentParams(_debtorPays, int(holderReq) );
        optionsContract.setLimits( int(debtorReq), int(holderReq) );

        (success,) = _optionsAddress.call(abi.encodeWithSignature("assignPutPosition()"));
        if (!success) return (false, 0);
        if (_debtorPays) {
            //fetch transfer amount for holder
            transferAmt = int(holderReq);
            /*
                We do not need to worry about debtor here because that was all handled in the options handler contract
            */
        }
        else {
            transferAmt = optionsContract.transferAmountDebtor();
            _strikeAssetDeposits[_d] += uint(int(debtorReq) - transferAmt);
            /*
                We do not need to worry about holder here because that was all handled in the options handler contract
            */
        }
        scReserves = uint(int(scReserves)-transferAmt);
    }



}