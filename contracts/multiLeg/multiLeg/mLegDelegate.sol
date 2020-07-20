pragma solidity >=0.6.0;
import "./mLegData.sol";
import "../../optionsHandler/options.sol";
import "../../feeOracle.sol";

contract mLegDelegate is mLegData {


    function payFee() public payable {
        feeOracle fo = feeOracle(feeOracleAddress);
        if (fo.isFeeImmune(optionsAddress, msg.sender)) return;
        uint fee = fo.multiLegExchangeFlatEtherFee();
        require(msg.value >= fee);
        msg.sender.transfer(msg.value-fee);
        payable(fo.feldmexTokenAddress()).transfer(fee);
    }


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

    /*
        @Description: method by which proxy contract may delegatecall this delegate contract to mint position using globals as params
    */
    function mintPosition() public {
    	bool success = mintPositionInternal(debtor,holder,maturity,legsHash,amount,price,index);
    	assert(success);
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
    function mintPositionInternal(address _debtor, address _holder, uint _maturity, bytes32 _legsHash, uint _amount, int _price, uint8 _index) internal returns(bool success){
        /*
            debtor pays is true if debtor is making the market order and thus debtor must provide the necessary collateral
                whereas the holder has already provided the necessary collateral
                this means that the debtor recieves the price premium
        */
        _price *= int(_amount);
        address _optionsAddress = optionsAddress; //gas savings
        options optionsContract = options(_optionsAddress);
        position memory pos = positions[_legsHash];
        optionsContract.setParams(_debtor, _holder, _maturity);
        optionsContract.setTrustedAddressMultiLegExchange(2);
        //load call position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.callAmounts.length; i++)
            optionsContract.addPosition(pos.callStrikes[i], int(_amount)*pos.callAmounts[i], true);
        if (_index<2){
            optionsContract.setPaymentParams(_index==0, _price);
            optionsContract.setLimits(int(_amount * pos.maxUnderlyingAssetDebtor) - _price, int(_amount * pos.maxUnderlyingAssetHolder) + _price);
        }
        else{
            optionsContract.setPaymentParams(_index==2, 0);
            optionsContract.setLimits(int(_amount * pos.maxUnderlyingAssetDebtor), int(_amount * pos.maxUnderlyingAssetHolder));
        }

        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return false;

        int transfer = _index%2==0 ? optionsContract.transferAmountHolder() : optionsContract.transferAmountDebtor();
        int transferAmount = -transfer;
        //load put position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.putAmounts.length; i++)
            optionsContract.addPosition(pos.putStrikes[i], int(_amount)*pos.putAmounts[i], false);
        if (_index>1){
            optionsContract.setPaymentParams(_index==2, _price);
            optionsContract.setLimits(int(_amount * pos.maxStrikeAssetDebtor) - _price, int(_amount * pos.maxStrikeAssetHolder) + _price);
        }
        else{
            optionsContract.setPaymentParams(_index==0, 0);
            optionsContract.setLimits(int(_amount * pos.maxStrikeAssetDebtor), int(_amount * pos.maxStrikeAssetHolder));
        }
        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignPutPosition()"));
        if (!success) return false;
        /*
            We have minted the put position but we still have data from the call position stored in transferAmountDebtor and transferAmountHolder
            handle distribution of funds in claimedToken mapping
        */
        address addr;
        if (_index%2==0){
            addr = _holder;
            transferAmount += int(_amount * pos.maxUnderlyingAssetHolder);
            if (_index==0) transferAmount += _price;
        } else {
            addr = _debtor;
            transferAmount += int(_amount * pos.maxUnderlyingAssetDebtor);
            if (_index==1) transferAmount -= _price;
        }
        if (int(claimedToken[addr]) < -transferAmount) return false;
        claimedToken[addr] += uint(int(claimedToken[addr]) + transferAmount);
        satReserves = uint(int(satReserves)-transfer);

        //update transfer amounts and handle distribution of funds in claimedStable mapping
        transfer = _index%2==0 ? optionsContract.transferAmountHolder() : optionsContract.transferAmountDebtor();
        transferAmount = -transfer;

        if (_index%2==0){
            addr = _holder;
            transferAmount += int(_amount * pos.maxStrikeAssetHolder);
            if (_index==2) transferAmount += _price;
        } else {
            addr = _debtor;
            transferAmount += int(_amount * pos.maxStrikeAssetDebtor);
            if (_index==3) transferAmount -= _price;
        }
        if (int(claimedStable[addr]) < -transferAmount) return false;
        claimedStable[addr] += uint(int(claimedStable[addr]) + transferAmount);
        scReserves = uint(int(scReserves)-transfer);
    }


}