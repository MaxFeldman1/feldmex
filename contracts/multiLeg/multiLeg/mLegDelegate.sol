pragma solidity >=0.8.0;
import "./mLegData.sol";
import "../../feeOracle.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IOptionsHandler.sol";

contract mLegDelegate is mLegData {


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

    function addLegHash(
        uint[] memory _callStrikes,
        int[] memory _callAmounts,
        uint[] memory _putStrikes,
        int[] memory _putAmounts
        ) external {
        //make sure that this is a multi leg order
        require(_callAmounts.length > 0 && _putAmounts.length > 0);
        require(_callAmounts.length==_callStrikes.length&&_putAmounts.length==_putStrikes.length);
        bytes32 hash = keccak256(abi.encodePacked(_callStrikes, _callAmounts, _putStrikes, _putAmounts));
        IOptionsHandler optionsContract = IOptionsHandler(optionsAddress);
        uint prevStrike;
        int _subUnits = int(underlyingAssetSubUnits);  //gas savings
        //load position
        optionsContract.clearPositions();
        for (uint i = 0; i < _callAmounts.length; i++){
            require(prevStrike < _callStrikes[i] && _callAmounts[i] != 0);
            prevStrike = _callStrikes[i];
            optionsContract.addPosition(_callStrikes[i], _subUnits*_callAmounts[i], true);
        }
        (uint maxUnderlyingAssetDebtor, uint maxUnderlyingAssetHolder) = optionsContract.transferAmount(true);
        require(int(maxUnderlyingAssetHolder) > -1);
        require(int(maxUnderlyingAssetDebtor) > -1);
        prevStrike = 0;
        _subUnits = int(strikeAssetSubUnits);    //gas savings
        optionsContract.clearPositions();
        for (uint i = 0; i < _putAmounts.length; i++){
            require(prevStrike < _putStrikes[i] && _putAmounts[i] != 0);
            prevStrike = _putStrikes[i];
            optionsContract.addPosition(_putStrikes[i], _subUnits*_putAmounts[i], false);
        }
        (uint maxStrikeAssetDebtor, uint maxStrikeAssetHolder) = optionsContract.transferAmount(false);
        require(int(maxStrikeAssetHolder) > -1);
        require(int(maxStrikeAssetDebtor) > -1);
        position memory pos = position(
            _callAmounts,
            _callStrikes,
            _putAmounts,
            _putStrikes,
            int(maxUnderlyingAssetDebtor),
            int(maxUnderlyingAssetHolder),
            int(maxStrikeAssetDebtor),
            int(maxStrikeAssetHolder)
        );
        internalPositions[hash] = pos;
        emit legsHashCreated(hash);
    }

    function withdrawAllFunds(bool _token) public {
        if (_token){
            uint val = internalUnderlyingAssetDeposits[msg.sender];
            IERC20 ua = IERC20(underlyingAssetAddress);
            internalUnderlyingAssetDeposits[msg.sender] = 0;
            ua.transfer(msg.sender, val);
            internalUnderlyingAssetReserves -= val;
        }
        else {
            uint val = internalStrikeAssetDeposits[msg.sender];
            IERC20 sa = IERC20(strikeAssetAddress);
            internalStrikeAssetDeposits[msg.sender] = 0;
            sa.transfer(msg.sender, val);
            internalStrikeAssetReserves -= val;
        }
    }

    function payFee() public payable {
        feeOracle fo = feeOracle(feeOracleAddress);
        if (fo.isFeeImmune(optionsAddress, msg.sender)) return;
        uint fee = fo.multiLegExchangeFlatEtherFee();
        require(msg.value >= fee);
        payable(msg.sender).transfer(msg.value-fee);
        payable(fo.feldmexTokenAddress()).transfer(fee);
    }


    function cancelOrderInternal(bytes32 _name) internal {
    	//bytes32 _name = name;
        linkedNode memory node = internalLinkedNodes[_name];
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
            uint req = uint(int(offer.amount) * (pos.maxUnderlyingAssetHolder + offer.price)) / underlyingAssetSubUnits;
            if (int(req) < 0) req = 0;
            internalUnderlyingAssetDeposits[offer.offerer] += req;
            internalStrikeAssetDeposits[offer.offerer] += offer.amount * uint(pos.maxStrikeAssetHolder) / strikeAssetSubUnits;
        }
        else if (offer.index == 1){
            uint req = uint(int(offer.amount) * (pos.maxUnderlyingAssetDebtor - offer.price)) / underlyingAssetSubUnits;
            if (int(req) < 0) req = 0;
            internalUnderlyingAssetDeposits[offer.offerer] += req;
            internalStrikeAssetDeposits[offer.offerer] += offer.amount * uint(pos.maxStrikeAssetDebtor) / strikeAssetSubUnits;
        }
        else if (offer.index == 2){
            internalUnderlyingAssetDeposits[offer.offerer] += offer.amount * uint(pos.maxUnderlyingAssetHolder) / underlyingAssetSubUnits;
            uint req = uint(int(offer.amount) * (pos.maxStrikeAssetHolder + offer.price)) / strikeAssetSubUnits;
            if (int(req) < 0) req = 0;
            internalStrikeAssetDeposits[offer.offerer] += req;
        }
        else {
            internalUnderlyingAssetDeposits[offer.offerer] += offer.amount * uint(pos.maxUnderlyingAssetDebtor) / underlyingAssetSubUnits;
            uint req = uint(int(offer.amount) * (pos.maxStrikeAssetDebtor - offer.price)) / strikeAssetSubUnits;
            if (int(req) < 0) req = 0;
            internalStrikeAssetDeposits[offer.offerer] += req;
        }

    }


    function cancelOrder(bytes32 _name) external {
        cancelOrderInternal(_name);
    }


    /*
        @Description: handles logistics of the seller accepting a buy order with identifier _name

        @param address _seller: the seller that is taking the buy offer
        @param bytes32 _name: the identifier of the node which stores the offer to take, offerToTake == internalOffers[internalLinkedNodes[_name].hash]

        @return bool success: if an error occurs returns false if no error return true
    */
    function takeBuyOffer(address _seller, bytes32 _name) public returns (bool success) {
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
            //name = _name;
            cancelOrderInternal(_name);
            return true;
        }
        else {
            success = mintPosition(_seller, offer.offerer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            require(success);
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
    function takeSellOffer(address _buyer, bytes32 _name) public returns (bool success) {
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
            //name = _name;
            cancelOrderInternal(_name);
            return true;
        }
        else {
            success = mintPosition(offer.offerer, _buyer, offer.maturity, offer.legsHash, offer.amount, offer.price, offer.index);
            require(success);
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


    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) external {
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));
        //ensure all strikes are contained
        uint8 index = (_payInUnderlying? 0: 2);
        linkedNode memory node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][index]];
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
                    if (offer.index == 0){
                        uint req = uint(int(_amount) * (pos.maxUnderlyingAssetHolder + offer.price));
                        if (int(req) > 0)
                            internalUnderlyingAssetDeposits[msg.sender] += req / underlyingAssetSubUnits;
                        internalStrikeAssetDeposits[msg.sender] += _amount * uint(pos.maxStrikeAssetHolder) / strikeAssetSubUnits;
                    } else {
                        internalUnderlyingAssetDeposits[msg.sender] += _amount * uint(pos.maxUnderlyingAssetHolder) / underlyingAssetSubUnits;
                        uint req = uint(int(_amount) * (pos.maxStrikeAssetHolder + offer.price));
                        if (int(req) > 0)
                            internalStrikeAssetDeposits[msg.sender] += req / strikeAssetSubUnits;
                    }
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
            node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][index]];
            offer = internalOffers[node.hash];
            _maxIterations--;
        }
        unfilled = _amount;
    }


    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) external {
        require(_legsHash != 0);
        require(containsStrikes(_maturity, _legsHash));
        //ensure all strikes are contained
        uint8 index = (_payInUnderlying ? 1 : 3);
        linkedNode memory node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][index]];
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
                    if (offer.index == 1){
                        uint req = uint(int(_amount) * (pos.maxUnderlyingAssetDebtor - offer.price));
                        if (int(req) > 0)
                            internalUnderlyingAssetDeposits[msg.sender] += req / underlyingAssetSubUnits;
                        internalStrikeAssetDeposits[msg.sender] += _amount * uint(pos.maxStrikeAssetDebtor) / strikeAssetSubUnits;
                    } else {
                        internalUnderlyingAssetDeposits[msg.sender] += _amount * uint(pos.maxUnderlyingAssetDebtor) / underlyingAssetSubUnits;
                        uint req = uint(int(_amount) * (pos.maxStrikeAssetDebtor - offer.price));
                        if (int(req) > 0)
                        internalStrikeAssetDeposits[msg.sender] += req / strikeAssetSubUnits;
                    }
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
            node = internalLinkedNodes[internalListHeads[_maturity][_legsHash][index]];
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
        optionsContract.setParams(_debtor, _holder, _maturity);
        optionsContract.setTrustedAddressMultiLegExchange(2);
        position memory pos = internalPositions[_legsHash];
        //load call position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.callAmounts.length; i++)
            optionsContract.addPosition(pos.callStrikes[i], int(_amount)*pos.callAmounts[i], true);

        uint _subUnits = underlyingAssetSubUnits;  //gas savings

        int premium;
        {
            uint totalReq;
            uint holderReq;

            {
                //accounting for holder and debtor must be done seperately as that is how it is done in the options handler
                uint temp = _amount * uint(pos.maxUnderlyingAssetHolder);
                holderReq = temp/_subUnits + (temp%_subUnits == 0 ? 0 : 1);
                totalReq = holderReq;

                temp = _amount * uint(pos.maxUnderlyingAssetDebtor);
                totalReq += temp/_subUnits + (temp%_subUnits == 0 ? 0 : 1);            
            }

            /*
                pos refers to the state of pos after the reassignment of its members

                pos.maxUnderlyingAssetHolder = holderReq + premium
                
                premium = pos.maxUnderlyingAssetHolder - holderReq
            */
            if (_index == 0) {
                pos.maxUnderlyingAssetHolder = int(_amount) * (pos.maxUnderlyingAssetHolder + _price) / int(_subUnits);
                pos.maxUnderlyingAssetDebtor = int(totalReq) - pos.maxUnderlyingAssetHolder;
            } else if (_index == 1) {
                pos.maxUnderlyingAssetDebtor = int(_amount) * (pos.maxUnderlyingAssetDebtor - _price) / int(_subUnits);
                pos.maxUnderlyingAssetHolder = int(totalReq) - pos.maxUnderlyingAssetDebtor;
            } else if (_index == 2) {
                pos.maxUnderlyingAssetHolder = int(_amount) * pos.maxUnderlyingAssetHolder / int(_subUnits);
                pos.maxUnderlyingAssetDebtor = int(totalReq) - pos.maxUnderlyingAssetHolder;
            } else {
                pos.maxUnderlyingAssetDebtor = int(_amount) * pos.maxUnderlyingAssetDebtor / int(_subUnits);
                pos.maxUnderlyingAssetHolder = int(totalReq) - pos.maxUnderlyingAssetDebtor;
            }
            premium = pos.maxUnderlyingAssetHolder - int(holderReq);
        }
        optionsContract.setLimits(pos.maxUnderlyingAssetDebtor, pos.maxUnderlyingAssetHolder);
        optionsContract.setPaymentParams(_index%2 == 0, premium);

        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignCallPosition()"));
        if (!success) return false;

        //store data before calling assignPutPosition
        int transferAmount;
        int optionsTransfer;
        if (_index%2 == 0) {
            optionsTransfer = optionsContract.transferAmountHolder();
            transferAmount = pos.maxUnderlyingAssetHolder - optionsTransfer;
        } else {
            optionsTransfer = optionsContract.transferAmountDebtor();
            transferAmount = pos.maxUnderlyingAssetDebtor - optionsTransfer;
        }

        //load put position
        optionsContract.clearPositions();
        for (uint i = 0; i < pos.putAmounts.length; i++)
            optionsContract.addPosition(pos.putStrikes[i], int(_amount)*pos.putAmounts[i], false);

        _subUnits = strikeAssetSubUnits;    //gas savings
        {
            uint totalReq;
            uint holderReq;

            {
                //accounting for holder and debtor must be done seperately as that is how it is done in the options handler
                uint temp = _amount * uint(pos.maxStrikeAssetHolder);
                holderReq = temp/_subUnits + (temp%_subUnits == 0 ? 0 : 1);
                totalReq = holderReq;

                temp = _amount * uint(pos.maxStrikeAssetDebtor);
                totalReq += temp/_subUnits + (temp%_subUnits == 0 ? 0 : 1);
            }

            /*
                pos refers to the state of pos after the reassignment of its members

                pos.maxStrikeAssetHolder = holderReq + premium

                premium = pos.maxStrikeAssetHolder - holderReq
            */
            if (_index == 0) {
                pos.maxStrikeAssetHolder = int(_amount) * pos.maxStrikeAssetHolder / int(_subUnits);
                pos.maxStrikeAssetDebtor = int(totalReq) - pos.maxStrikeAssetHolder;
            } else if (_index == 1) {
                pos.maxStrikeAssetDebtor = int(_amount) * pos.maxStrikeAssetDebtor / int(_subUnits);
                pos.maxStrikeAssetHolder = int(totalReq) - pos.maxStrikeAssetDebtor;
            } else if (_index == 2) {
                pos.maxStrikeAssetHolder = int(_amount) * (pos.maxStrikeAssetHolder + _price) / int(_subUnits);
                pos.maxStrikeAssetDebtor = int(totalReq) - pos.maxStrikeAssetHolder;
            } else {
                pos.maxStrikeAssetDebtor = int(_amount) * (pos.maxStrikeAssetDebtor - _price) / int(_subUnits);
                pos.maxStrikeAssetHolder = int(totalReq) - pos.maxStrikeAssetDebtor;
            }
            premium = pos.maxStrikeAssetHolder - int(holderReq);
        }
        optionsContract.setLimits(pos.maxStrikeAssetDebtor, pos.maxStrikeAssetHolder);
        optionsContract.setPaymentParams(_index%2 == 0, premium);

        (success, ) = _optionsAddress.call(abi.encodeWithSignature("assignPutPosition()"));
        if (!success) return false;
        /*
            We have minted the put position but we still have data from the call position stored in transferAmountDebtor and transferAmountHolder
            handle distribution of funds in internalUnderlyingAssetDeposits mapping
        */
        address addr = _index%2 == 0 ? _holder : _debtor;
        internalUnderlyingAssetReserves = uint(int(internalUnderlyingAssetReserves)-optionsTransfer);
        if (int(internalUnderlyingAssetDeposits[addr]) < -transferAmount) return false;
        internalUnderlyingAssetDeposits[addr] = uint(int(internalUnderlyingAssetDeposits[addr]) + transferAmount);

        if (_index%2==0){
            optionsTransfer = optionsContract.transferAmountHolder();
            transferAmount = pos.maxStrikeAssetHolder - optionsTransfer;
        } else {
            optionsTransfer = optionsContract.transferAmountDebtor();
            transferAmount = pos.maxStrikeAssetDebtor - optionsTransfer;
        }
        internalStrikeAssetReserves = uint(int(internalStrikeAssetReserves)-optionsTransfer);
        if (int(internalStrikeAssetDeposits[addr]) < -transferAmount) return false;
        internalStrikeAssetDeposits[addr] = uint(int(internalStrikeAssetDeposits[addr]) + transferAmount);
    }


}