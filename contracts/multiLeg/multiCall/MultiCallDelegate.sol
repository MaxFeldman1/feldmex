pragma solidity >=0.8.0;
import "../../interfaces/IOptionsHandler.sol";
import "./MultiCallData.sol";

contract MultiCallDelegate is MultiCallData {

    /*
        @Description: removes the order with name identifier _name, prevents said order from being filled or taken

        @param bytes32: the identifier of the node which stores the order to cancel, offerToCancel == internalOffers[internalLinkedNodes[_name].hash]
    */
    function cancelOrderInternal(bytes32 _name) internal {
        linkedNode memory node = internalLinkedNodes[_name];
        require(msg.sender == internalOffers[node.hash].offerer);
        Offer memory offer = internalOffers[node.hash];
        //uint8 index = (offer.buy? 0 : 1) + (offer.call? 0 : 2);
        //if this node is somewhere in the middle of the list
        if (node.next != 0 && node.previous != 0){
            internalLinkedNodes[node.next].previous = node.previous;
            internalLinkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.previous == 0){
            delete internalListHeads[internalOffers[node.hash].maturity][internalOffers[node.hash].legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            internalLinkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            internalLinkedNodes[node.next].previous = 0;
            internalListHeads[internalOffers[node.hash].maturity][internalOffers[node.hash].legsHash][offer.index] = node.next;
        }
        emit offerCalceled(_name);
        delete internalLinkedNodes[_name];
        delete internalOffers[node.hash];
        position memory pos = internalPositions[offer.legsHash];
        if (offer.index == 0){
            uint req = uint(int(offer.amount) * (pos.maxUnderlyingAssetHolder + offer.price));
            if (int(req) > 0)
                internalUnderlyingAssetDeposits[offer.offerer] += req/underlyingAssetSubUnits;
        }
        else {
            uint req = uint(int(offer.amount) * (pos.maxUnderlyingAssetDebtor - offer.price));
            if (int(req) > 0)
                internalUnderlyingAssetDeposits[offer.offerer] += req/underlyingAssetSubUnits;
        }

    }

    function cancelOrder(bytes32 _name) external {
	    /*
			ensure sender is order maker in proxy contract
	    */
    	cancelOrderInternal(_name);
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
        contains = true;
    }

    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name

        @param address _seller: the seller that is taking the buy offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == internalOffers[internalLinkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer(address _seller, bytes32 _name) internal returns(bool success){
        linkedNode memory node = internalLinkedNodes[_name];
        Offer memory offer = internalOffers[node.hash];
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
            internalLinkedNodes[node.next].previous = node.previous;
            internalLinkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.next == 0){
            delete internalListHeads[offer.maturity][offer.legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            internalLinkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            internalLinkedNodes[node.next].previous = 0;
            internalListHeads[offer.maturity][offer.legsHash][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete internalLinkedNodes[_name];
        delete internalOffers[node.hash];
    }

    /*
        @Description: handles logistics of the buyer accepting a sell order with the identifier _name

        @param address _buyer: the buyer that is taking the sell offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == internalOffers[internalLinkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeSellOffer(address _buyer, bytes32 _name) internal returns(bool success){
        linkedNode memory node = internalLinkedNodes[_name];
        Offer memory offer = internalOffers[node.hash];
        require(offer.index%2==1);

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
            internalLinkedNodes[node.next].previous = node.previous;
            internalLinkedNodes[node.previous].next = node.next;
        }
        //this is the only offer for the maturity and legsHash
        else if (node.next == 0 && node.next == 0){
            delete internalListHeads[offer.maturity][offer.legsHash][offer.index];
        }
        //last node
        else if (node.next == 0){
            internalLinkedNodes[node.previous].next = 0;
        }
        //head node
        else{
            internalLinkedNodes[node.next].previous = 0;
            internalListHeads[offer.maturity][offer.legsHash][offer.index] = node.next;
        }
        emit offerAccepted(_name, offer.amount);
        //clean storage
        delete internalLinkedNodes[_name];
        delete internalOffers[node.hash];
    }


    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) external {
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));

        linkedNode memory node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][0]];
        Offer memory offer = internalOffers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price >= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (msg.sender == offer.offerer) {
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call mintPosition
                    */
                    position memory pos = internalPositions[offer.legsHash];
                    uint req = uint(int(_amount) * (pos.maxUnderlyingAssetHolder + offer.price));
                    if (int(req) > 0)
                        internalUnderlyingAssetDeposits[msg.sender] += req/underlyingAssetSubUnits;
                }
                else {
                    bool success = mintPosition(msg.sender, offer.offerer, offer.maturity, offer.legsHash, _amount, offer.price, offer.index);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                	}
                }
                internalOffers[node.hash].amount -= _amount;
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
            node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][0]];
            offer = internalOffers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }


    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) external {
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));

        linkedNode memory node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][1]];
        Offer memory offer = internalOffers[node.hash];
        require(node.name != 0);
        //in each iteration we call options.mintCall/Put once
        while (_amount > 0 && node.name != 0 && offer.price <= _limitPrice && _maxIterations != 0){
            if (offer.amount > _amount){
                if (offer.offerer == msg.sender){
                    /*
                        state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                        therefore we do not need to call mintPosition
                    */
                    position memory pos = internalPositions[offer.legsHash];
                    uint req = uint(int(_amount) * (pos.maxUnderlyingAssetDebtor - offer.price));
                    if (int(req) > 0)
                        internalUnderlyingAssetDeposits[msg.sender] += req/underlyingAssetSubUnits;
                }
                else {
                    bool success = mintPosition(offer.offerer, msg.sender, offer.maturity, offer.legsHash, _amount, offer.price, offer.index);
                    if (!success) {
                    	unfilled = _amount;
                    	return;
                    }
                }
                internalOffers[node.hash].amount -= _amount;
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
            node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][1]];
            offer = internalOffers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }



	/*
        @Description: mint a specific position between two users

        @param address _ debtor: the address selling the position
        @param address _holder: the address buying the position
        @param uint _maturity: the maturity of the position to mint
        @param bytes32 _legsHash: the identifier to find the position in internalPositions[]
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
        IOptionsHandler optionsContract = IOptionsHandler(_optionsAddress);
        position memory pos = internalPositions[_legsHash];
        optionsContract.setParams(_debtor, _holder, _maturity);
        //load call position into register
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.callAmounts.length; i++)
            optionsContract.addPosition(pos.callStrikes[i], int(_amount)*pos.callAmounts[i], true);
        optionsContract.setTrustedAddressMultiLegExchange(0);

        uint _underlyingAssetSubUnits = underlyingAssetSubUnits;  //gas savings

        int premium;
        {
            uint totalReq;
            uint holderReq;

            {
                //accounting for holder and debtor must be done seperately as that is how it is done in the options handler
                uint temp = _amount * uint(pos.maxUnderlyingAssetHolder);
                holderReq = temp/_underlyingAssetSubUnits + (temp%_underlyingAssetSubUnits == 0 ? 0 : 1);
                totalReq = holderReq;

                temp = _amount * uint(pos.maxUnderlyingAssetDebtor);
                totalReq += temp/_underlyingAssetSubUnits + (temp%_underlyingAssetSubUnits == 0 ? 0 : 1);            
            }


            /*
                pos refers to the state of pos after the reassignment of its members

                pos.maxUnderlyingAssetHolder = holderReq + premium
                
                premium = pos.maxUnderlyingAssetHolder - holderReq
            */

            if (_index == 0) {
                pos.maxUnderlyingAssetHolder = int(_amount) * (pos.maxUnderlyingAssetHolder + _price) / int(_underlyingAssetSubUnits);
                pos.maxUnderlyingAssetDebtor = int(totalReq) - pos.maxUnderlyingAssetHolder;
            } else {
                pos.maxUnderlyingAssetDebtor = int(_amount) * (pos.maxUnderlyingAssetDebtor - _price) / int(_underlyingAssetSubUnits);
                pos.maxUnderlyingAssetHolder = int(totalReq) - pos.maxUnderlyingAssetDebtor;
            }
            premium = pos.maxUnderlyingAssetHolder - int(holderReq);
        }

        optionsContract.setLimits(pos.maxUnderlyingAssetDebtor, pos.maxUnderlyingAssetHolder);
        optionsContract.setPaymentParams(_index==0, premium);

        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return false;

        int transferAmount;
        if (_index==0){
            address addr = _holder; //prevent stack too deep
            transferAmount = optionsContract.transferAmountHolder();
            internalUnderlyingAssetDeposits[addr] += uint( pos.maxUnderlyingAssetHolder - transferAmount);
        } else {
            address addr = _debtor; //prevent stack too deep
            transferAmount = optionsContract.transferAmountDebtor();
            internalUnderlyingAssetDeposits[addr] += uint( pos.maxUnderlyingAssetDebtor - transferAmount);
        }
        underlyingAssetReserves = uint(int(underlyingAssetReserves)-transferAmount);
    }
}
