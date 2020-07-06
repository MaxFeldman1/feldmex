pragma solidity >=0.5.0;
import "./mLegData.sol";
import "../options.sol";

contract mLegDelegate is mLegData {

    function cancelOrderInternal(bytes32 _name) public {
    	//bytes32 _name = name;
        linkedNode memory node = linkedNodes[_name];
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
            claimedToken[offer.offerer] += req;
            claimedStable[offer.offerer] += offer.amount * pos.maxStrikeAssetHolder;
        }
        else if (offer.index == 1){
            uint req = uint(int(offer.amount) * (int(pos.maxUnderlyingAssetDebtor) - offer.price));
            if (int(req) < 0) req = 0;
            claimedToken[offer.offerer] += req;
            claimedStable[offer.offerer] += offer.amount * pos.maxStrikeAssetDebtor;
        }
        else if (offer.index == 2){
            claimedToken[offer.offerer] += offer.amount * pos.maxUnderlyingAssetHolder;
            uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetHolder) + offer.price));
            if (int(req) < 0) req = 0;
            claimedStable[offer.offerer] += req;
        }
        else {
            claimedToken[offer.offerer] += offer.amount * pos.maxUnderlyingAssetDebtor;
            uint req = uint(int(offer.amount) * (int(pos.maxStrikeAssetDebtor) - offer.price));
            if (int(req) < 0) req = 0;
            claimedStable[offer.offerer] += req;
        }

    }
    
    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer() public {
    	address _seller = taker;	//gas savings
    	bytes32 _name = name;	//gas savings
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
            //name = _name;
            cancelOrderInternal(_name);
            return;
        }
        else {
            bool success = mintPositionInternal(_seller, offer.offerer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            assert(success);
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

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeSellOffer() public {
    	address _buyer = taker;	//gas savings
    	bytes32 _name = name;	//gas savings
        linkedNode memory node = linkedNodes[_name];
        Offer memory offer = offers[node.hash];
        require(offer.index%2==1);

        //now we make the trade happen
        //mint the option and distribute unused collateral
        if (offer.offerer == _buyer){
            /*
                state is not changed in options smart contract when values of _debtor and _holder arguments are the same in mintCall
                therefore we do not need to call options.assignPosition
            */
            //name = _name;
            cancelOrderInternal(_name);
            return;
        }
        else {
            bool success = mintPositionInternal(offer.offerer, _buyer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            assert(success);
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

    function mintPosition() public {
    	bool success = mintPositionInternal(debtor,holder,maturity,legsHash,amount,price,index);
    	assert(success);
    }

    function mintPositionInternal(address _debtor, address _holder, uint _maturity, bytes32 _legsHash, uint _amount, int _price, uint8 _index) internal returns(bool success){
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
            optionsContract.addPosition(pos.callStrikes[i], int(_amount)*pos.callAmounts[i], true);
        if (_index%2==0){
            uint limit = claimedToken[_debtor];
            limit = uint(int(limit)+(_index<2 ? _price : 0));
            optionsContract.setLimits(limit, _amount * pos.maxUnderlyingAssetHolder);
        }
        else{
            uint limit = claimedToken[_holder];
            limit = uint(int(limit)-(_index<2 ? _price : 0));
            optionsContract.setLimits(_amount * pos.maxUnderlyingAssetDebtor, limit);
        }
        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return false;
        uint transferAmountDebtor = uint(optionsContract.transferAmountDebtor());
        uint transferAmountHolder = uint(optionsContract.transferAmountHolder());
        //load put position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.putAmounts.length; i++)
            optionsContract.addPosition(pos.putStrikes[i], int(_amount)*pos.putAmounts[i], false);
        if (_index%2==0){
            uint limit = claimedStable[_debtor];
            limit = uint(int(limit)+(_index>1 ? _price : 0));
            optionsContract.setLimits(limit, _amount * pos.maxStrikeAssetHolder);
        }
        else{
            uint limit = claimedStable[_holder];
            limit = uint(int(limit)-(_index>1 ? _price : 0));
            optionsContract.setLimits(_amount * pos.maxStrikeAssetDebtor, limit);
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
            claimedToken[_holder] += _amount * pos.maxUnderlyingAssetHolder - transferAmountHolder;
        } else {
            if (_index < 2 && _price > 0) claimedToken[_holder] -= uint(_price);
            else if (_index < 2) claimedToken[_holder] += uint(-_price);
            claimedToken[_holder] -= transferAmountHolder;
            claimedToken[_debtor] += _amount * pos.maxUnderlyingAssetDebtor - transferAmountDebtor;
        }
        satReserves -= transferAmountDebtor+transferAmountHolder;
        //update transfer amounts and handle distribution of funds in claimedStable mapping
        transferAmountDebtor = uint(optionsContract.transferAmountDebtor());
        transferAmountHolder = uint(optionsContract.transferAmountHolder());
        if (_index%2==0){
            if (_index > 1 && _price > 0) claimedStable[_debtor] += uint(_price);
            else if (_index > 1) claimedStable[_debtor] -= uint(-_price);
            claimedStable[_debtor] -= transferAmountDebtor;
            claimedStable[_holder] += _amount * pos.maxStrikeAssetHolder - transferAmountHolder;
        } else {
            if (_index > 1 && _price > 0) claimedStable[_holder] -= uint(_price);
            else if (_index > 1) claimedStable[_holder] += uint(-_price);
            claimedStable[_holder] -= transferAmountHolder;
            claimedStable[_debtor] += _amount * pos.maxStrikeAssetDebtor - transferAmountDebtor;
        }
        scReserves -= transferAmountDebtor+transferAmountHolder;
    }


}