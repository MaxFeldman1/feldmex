pragma solidity ^0.5.12;
import "./interfaces/ITimeSeriesOracle.sol";
import "./oracle.sol";
import "./interfaces/ERC20.sol";
import "./interfaces/Ownable.sol";
import "./ERC20FeldmexOptions/FeldmexERC20Helper.sol";
import "./multiLeg/mOrganizer.sol";
import "./FeldmexOptionsData.sol";

contract options is FeldmexOptionsData, Ownable {

        /*
        @Description: assigns the addesses of external contracts

        @param address _oracleAddress: address that shall be assigned to oracleAddress
        @param address _underlyingAssetAddress: address that shall be assigned to underlyingAssetAddress
        @param address _strikeAssetAddress: address that shall be assigned to strikeAssetAddress
        @param address _feldmexERC20HelperAddress: address that will be assigned to feldmexERC20HelperAddress
        @param address _mOrganizerAddress: address that will be assigned to mOrganizerAddress
        @param address _assignOptionsDelegateAddress: address that will be assigned to assignOptionsDelegateAddress
    */
    constructor (address _oracleAddress, address _underlyingAssetAddress, 
        address _strikeAssetAddress, address _feldmexERC20HelperAddress, 
        address _mOrganizerAddress, address _assignOptionsDelegateAddress) public {
        
        oracleAddress = _oracleAddress;
        underlyingAssetAddress = _underlyingAssetAddress;
        strikeAssetAddress = _strikeAssetAddress;
        exchangeAddress = msg.sender;
        feldmexERC20HelperAddress = _feldmexERC20HelperAddress;
        assignOptionsDelegateAddress = _assignOptionsDelegateAddress;
        mOrganizerAddress = _mOrganizerAddress;
        oracle orc = oracle(oracleAddress);
        inflator = orc.inflator();
        ERC20 ua = ERC20(underlyingAssetAddress);
        satUnits = 10 ** uint(ua.decimals());
        ERC20 sa = ERC20(strikeAssetAddress);
        scUnits = 10 ** uint(sa.decimals());
    }
    
    /*
        @Descripton: Sets the address of the smart contract that is trusted to see all users collateral requirements

        @param address _exchangeAddress: this is the address that will be assigned to this contracts exchangeAddress variable
    */
    function setExchangeAddress(address _exchangeAddress) onlyOwner public {
        require(exchangeAddress == owner);
        exchangeAddress = _exchangeAddress;
    }

    /*
        @Description: allows the deployer to set a new fee

        @param uint _feeDenominator: the value which will be the denominator in the fee on all transactions
            fee == (amount*priceOfOption)/feeDenominator
    */
    function setFee(uint _feeDeonominator) onlyOwner public {
        require(_feeDeonominator >= 500);
        feeDenominator = _feeDeonominator;
    }

    /*
        @Description: allows the owner of this contract to give and take approval from accounts that are providing liquidity
            If an address is already approved approval will be removed if not approval will be awarded

        @address _addr: the address to give or retract fee immunity from
    */
    function changeFeeStatus(address _addr) onlyOwner public {
        if (feeImmunity[_addr]) delete feeImmunity[_addr];
        else feeImmunity[_addr] = true;
    }

    /*
        @Description: transfers ownership of contract
            if exchangeAddress has not been set it is also set to _addr such that it is known that the exchange address has not been set when it == owner
    */
    function transferOwnership(address _newOwner) onlyOwner public {
        if (owner == exchangeAddress) exchangeAddress = _newOwner;
        super.transferOwnership(_newOwner);
    }



    /*
        @Description: after the maturity holders of contracts to claim the value of the contracts and allows debtors to claim the unused collateral

        @pram uint _maturity: the maturity that the sender of this transaction is attempting to claim rewards from

        @return bool success: if an error occurs returns false if no error return true
    */
    function claim(uint _maturity) public returns(bool success){
        require(_maturity < block.timestamp);
        //get info from the oracle
        ITimeSeriesOracle orc = ITimeSeriesOracle(oracleAddress);
        //oracle orc = oracle(oracleAddress);
        uint spot = orc.fetchSpotAtTime(_maturity);
        uint callValue = 0;
        uint putValue = 0;
        //calls & puts
        for (uint i = strikes[msg.sender][_maturity].length-1; i != uint(-1); i--){
            uint strike = strikes[msg.sender][_maturity][i];
            int callAmount = callAmounts[msg.sender][_maturity][strike];
            int putAmount = putAmounts[msg.sender][_maturity][strike];
            delete callAmounts[msg.sender][_maturity][strike];
            delete putAmounts[msg.sender][_maturity][strike];
            callValue += satValueOf(callAmount, strike, spot);
            putValue += scValueOf(putAmount, strike, spot);
            delete containedStrikes[msg.sender][_maturity][strike];
        }
        //satValueOf is inflated by _price parameter and scValueOf thus only divide out spot from callValue not putValue
        callValue /= spot;
        delete strikes[msg.sender][_maturity];
        if (callValue > satDeduction[msg.sender][_maturity]){
            callValue -= satDeduction[msg.sender][_maturity];
            uint fee = feeImmunity[msg.sender] ? 0 : callValue/feeDenominator;
            claimedTokens[owner] += fee;
            claimedTokens[msg.sender] += callValue - fee;
        }
        if (putValue > scDeduction[msg.sender][_maturity]){
            putValue -= scDeduction[msg.sender][_maturity];
            uint fee = feeImmunity[msg.sender] ? 0 : putValue/feeDenominator;
            claimedStable[owner] += fee;
            claimedStable[msg.sender] += putValue - fee;
        }
        success = true;
    }

    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively

        @return uint underlyingAsset: the amount of the underlying asset that has been withdrawn
        @return uint strikeAsset: the amount of the strike asset that has been withdrawn
    */
    function withdrawFunds() public returns(uint underlyingAsset, uint strikeAsset){
        ERC20 ua = ERC20(underlyingAssetAddress);
        underlyingAsset = claimedTokens[msg.sender];
        claimedTokens[msg.sender] = 0;
        ua.transfer(msg.sender, underlyingAsset);
        ERC20 sa = ERC20(strikeAssetAddress);
        strikeAsset = claimedStable[msg.sender];
        claimedStable[msg.sender] = 0;
        sa.transfer(msg.sender, strikeAsset);
        satReserves -= underlyingAsset;
        scReserves -= strikeAsset;
    }

    /*
        @Description: allows for users to deposit funds that are not tided up as collateral
            these funds are tracked in the claimedTokens mapping and the claimedStable mapping for the underlying and strike asset respectively
    */
    function depositFunds(address _to) public returns(bool success){
    	uint balance = ERC20(underlyingAssetAddress).balanceOf(address(this));
    	uint sats = balance - satReserves;
    	satReserves = balance;
    	balance = ERC20(strikeAssetAddress).balanceOf(address(this));
    	uint sc = balance - scReserves;
    	scReserves = balance;
    	claimedTokens[_to] += sats;
    	claimedStable[_to] += sc;
        success = true;
    }

    /*
        @Description: used to tell if strikes[givenAddress][givenMaturity] contains a given strike

        @param address _addr: the address is question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike price in question

        @return bool _contains: returns true if strike[_addr][_maturity] contains _strike otherwise returns false
    */
    function contains(address _addr, uint _maturity, uint _strike)public view returns(bool _contains){
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            if (strikes[_addr][_maturity][i] == _strike) return true;
        }
        _contains = false;
    }


    /*
        @Description: used to find the value of a given call postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the call contract in terms of the underlying versus stablecoie
        @param uint _price: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint value: the value of the position in terms of the underlying multiplied by the price
            inflate value by multiplying by price and divide out after doing calculations with the returned value to maintain accuracy
    */
    function satValueOf(int _amount, uint _strike, uint _price)internal view returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price > _strike){
                //inflator is canceld when it is divided by out
                //payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price * inflator - (_strike * inflator))/inflator;
                //payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - _strike) * inflator/inflator;
                payout = uint(_amount > 0 ? _amount : -_amount) * satUnits * (_price - _strike);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*satUnits*_price - payout;
            }
        } 
        value = 0;
    }

    /*
        @Description: used to find the value of a given put postioin at maturity in terms of the underlying

        @param int _amount: the net long/short position
            positive == long; negative == short
        @param uint _strike: the strike prive of the put contract in terms of the underlying versus stablecoie
        @param uint _prive: the spot price at which to find the value of the position in terms of the underlying versus stablecoie

        @return uint value: the value of the position in terms of the strike asset
    */
    function scValueOf(int _amount, uint _strike, uint _price)internal pure returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price < _strike){
                //inflator must be divided out thus remove *scUnits
                payout = (_strike - _price)*uint(_amount > 0 ? _amount : -_amount);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                //inflator must be divided out thus remove *scUnits
                return uint(-_amount)*_strike - payout;
            }
        }
        value = 0;
    }

    /*
        @Description: The function was created for positions at a strike to be inclueded in calculation of collateral requirements for a user
            User calls this instead of smart contract adding strikes automatically when funds are transfered to an address by the transfer or transferFrom functions
            because it prevents a malicious actor from overloading a user with many different strikes thus making it impossible to claim funds because of the gas limit
            strikes array is sorted from smallest to largest

        @param uint _maturity: this is the maturity at which the strike will be added if it is not already recorded at this maturity
        @param uint _strike: this is the strike that will be added.
        @param uint _index: the index at which to insert the strike
    */
    function addStrike(uint _maturity, uint _strike, uint _index) public {
        require(_maturity > 0 && _strike > 0);
        uint size = strikes[msg.sender][_maturity].length;
        require(_index <= size);
        if (_index > 0) require(_strike > strikes[msg.sender][_maturity][_index-1]);
        if (_index < size) require(_strike < strikes[msg.sender][_maturity][_index]);
        strikes[msg.sender][_maturity].push(_strike);
        for (uint i = size-1; i >= _index && i != uint(-1); i--)
            strikes[msg.sender][_maturity][i+1] = strikes[msg.sender][_maturity][i];
        strikes[msg.sender][_maturity][_index] = _strike;
        containedStrikes[msg.sender][_maturity][_strike] = true;
    }


    /*
        @Description: view function for both callAmounts and putAmounts
    */
    function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) public view returns(int256 balance){
        balance = _call ? callAmounts[_owner][_maturity][_strike] : putAmounts[_owner][_maturity][_strike];
    }


    /*
        @Description: add a strike to strikes[helperAddress][helperMaturity] and an amount to either callAmounts or putAmounts

        @param uint _strike: the strike of the position in question
        @param int _amount: the amount of the position in question
        @param bool _call: true if the position is for calls false if it is for puts
    */
    function addPosition(uint _strike, int _amount, bool _call) public {
        require(_strike > 0);
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint size = strikes[_helperAddress][_helperMaturity].length;
        if (size > 0) require(_strike > strikes[_helperAddress][_helperMaturity][size-1]);
        strikes[_helperAddress][_helperMaturity].push(_strike);
        if (_call)
            callAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
        else
            putAmounts[_helperAddress][_helperMaturity][_strike] = _amount;
    }

    /*
        @Description: deletes strikes[helperAddress][helperMaturity]
    */
    function clearPositions() public {
        delete strikes[helperAddress][helperMaturity];
    }

    /*
        @Description: multiplies all call/put Amounts by -1

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function inversePosition(bool _call) public {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("inversePosition(bool)", _call));
        assert(success);
    }

    /*
        @Description:finds the maximum amount of collateral needed to take on a position

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function transferAmount(bool _call) public returns (uint _debtorTransfer, uint _holderTransfer) {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("transferAmount(bool)", _call));
        assert(success);
        _debtorTransfer = uint(transferAmountDebtor);
        _holderTransfer = uint(transferAmountHolder);
    }


    /*
        @Description: assign the call position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignCallPosition() public {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("assignCallPosition()"));
        assert(success);
    }


    /*
        @Description: assign the put position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignPutPosition() public {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("assignPutPosition()"));
        assert(success);
    }


    /*
        @Description: set the values of debtor, holder, and maturity before calling assignCallPosition or assignPutPosition

        @param address _debtor: the address that will gain the opposite payoff profile of the position stored at helperAddress at helperMaturity
        @param address _holder: the address that will gain the payoff profile of the position stored at helperAddress at helperMaturity
        @param uint _maturity: the timestamp at which the puts may be exercised 
    */
    function setParams(address _debtor, address _holder, uint _maturity) public {
        debtor = _debtor;
        holder = _holder;
        maturity = _maturity;
    }

    /*
        @Description: sets the method by which funds will be aquired to fuffil collateral requirements

        @param bool _useDebtorInternalFunds: when msg.sender in assignCall/PutPosition is trusted address
            if false debtor funds stored in this contract will be used to fuffil debtor collateral requirements
            if true holder funds stored in this contract will be used to fuffil holder collateral requirements
        @param int _premium: the amount of premium payed by the debtor to the holder
    */
    function setPaymentParams(bool _useDebtorInternalFunds, int _premium) public {
        useDebtorInternalFunds = _useDebtorInternalFunds;
        premium = _premium;
    }

    //trusted address may be set to any FeldmexERC20Helper contract address
    function setTrustedAddressFeldmexERC20(uint _maturity, uint _strike, bool _call) public {
        trustedAddress = _call ? 
            FeldmexERC20Helper(feldmexERC20HelperAddress).callAddresses(address(this), _maturity, _strike) :
            FeldmexERC20Helper(feldmexERC20HelperAddress).putAddresses(address(this), _maturity, _strike);
    }
    //set the trusted address to the exchange address
    function setTrustedAddressMainExchange() public {trustedAddress = exchangeAddress;}
    //set the trusted address to a multi leg exchange
    function setTrustedAddressMultiLegExchange(uint8 _index) public {trustedAddress = mOrganizer(mOrganizerAddress).exchangeAddresses(address(this), _index);}

    /*
        @Description: set the maximum values for the transfer amounts

        @param int _maxDebtorTransfer: the maximum amount for transferAmountDebtor if this limit is breached assignPosition transactions will revert
        @param int _maxHolderTransfer: the maximum amount for transferAmountHolder if this limit is breached assignPosition transactions will revert
    */
    function setLimits(int _maxDebtorTransfer, int _maxHolderTransfer) public {
        maxDebtorTransfer = _maxDebtorTransfer;
        maxHolderTransfer = _maxHolderTransfer;
    }

    //---------------------view functions---------------
    function viewClaimedTokens() public view returns(uint){return claimedTokens[msg.sender];}

    function viewClaimedStable() public view returns(uint){return claimedStable[msg.sender];}

    function viewSatCollateral(uint _maturity) public view returns(uint){return satCollateral[msg.sender][_maturity];}

    function viewScCollateral(uint _maturity) public view returns(uint){return scCollateral[msg.sender][_maturity];}

    function viewStrikes(uint _maturity) public view returns(uint[] memory){return strikes[msg.sender][_maturity];}

    function viewSatDeduction(uint _maturity) public view returns(uint){return satDeduction[msg.sender][_maturity];}

    function viewScDeduction(uint _maturity) public view returns(uint){return scDeduction[msg.sender][_maturity];}
    //---------------------end view functions-----------
}