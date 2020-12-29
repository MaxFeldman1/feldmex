pragma solidity >=0.8.0;
import "../interfaces/ITimeSeriesOracle.sol";
import "../oracle.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/Ownable.sol";
import "../interfaces/IOptionsHandler.sol";
import "../ERC20FeldmexOptions/FeldmexERC20Helper.sol";
import "../multiLeg/mOrganizer.sol";
import "./FeldmexOptionsData.sol";
import "../feeOracle.sol";

contract OptionsHandler is FeldmexOptionsData, Ownable, IOptionsHandler {

    /*
        @Description: setup
    */
    constructor (address _oracleAddress, address _underlyingAssetAddress,
        address _strikeAssetAddress, address _feldmexERC20HelperAddress,
        address _mOrganizerAddress, address _assignOptionsDelegateAddress,
        address _feeOracleAddress) {
        
        oracleAddress = _oracleAddress;
        internalUnderlyingAssetAddress = _underlyingAssetAddress;
        internalStrikeAssetAddress = _strikeAssetAddress;
        feldmexERC20HelperAddress = _feldmexERC20HelperAddress;
        assignOptionsDelegateAddress = _assignOptionsDelegateAddress;
        mOrganizerAddress = _mOrganizerAddress;
        feeOracleAddress = _feeOracleAddress;
        feeOracle(_feeOracleAddress).setSpecificFeeImmunity(address(this), msg.sender, true);
        IERC20 ua = IERC20(_underlyingAssetAddress);
        underlyingAssetSubUnits = 10 ** uint(ua.decimals());
        IERC20 sa = IERC20(_strikeAssetAddress);
        strikeAssetSubUnits = 10 ** uint(sa.decimals());
    }
    
    /*
        @Descripton: Sets the address of the smart contract that is trusted to see all users collateral requirements

        @param address _exchangeAddress: this is the address that will be assigned to this contracts exchangeAddress variable
    */
    function setExchangeAddress(address _exchangeAddress) onlyOwner public override {
        require(exchangeAddress == address(0));
        exchangeAddress = _exchangeAddress;
    }

    /*
        @Description: transfers ownership of contract
            if exchangeAddress has not been set it is also set to _addr such that it is known that the exchange address has not been set when it == owner

        @param address _newOwner: the address that will take ownership of this contract
    */
    function transferOwnership(address _newOwner) onlyOwner public override {
        super.transferOwnership(_newOwner);
        address _feeOracleAddress = feeOracleAddress;
        feeOracle fo = feeOracle(_feeOracleAddress);
        fo.setSpecificFeeImmunity(address(this), _newOwner, true);
        fo.setSpecificFeeImmunity(address(this), msg.sender, false);
    }



    /*
        @Description: after the maturity holders of contracts to claim the value of the contracts and allows debtors to claim the unused collateral

        @pram uint _maturity: the maturity that the sender of this transaction is attempting to claim rewards from

        @return bool success: if an error occurs returns false if no error return true
    */
    function claim(uint _maturity) public override returns(bool success){
        require(_maturity < block.timestamp);
        ITimeSeriesOracle orc = ITimeSeriesOracle(oracleAddress);
        uint spot = orc.fetchSpotAtTime(_maturity, internalUnderlyingAssetAddress);
        uint callValue = 0;
        uint putValue = 0;
        //calls & puts
        {
            uint i;
            unchecked {
                i = strikes[msg.sender][_maturity].length-1;
            }
            while (i != uint(int(-1))) {
                uint strike = strikes[msg.sender][_maturity][i];
                int callAmount = callAmounts[msg.sender][_maturity][strike];
                int putAmount = putAmounts[msg.sender][_maturity][strike];
                delete callAmounts[msg.sender][_maturity][strike];
                delete putAmounts[msg.sender][_maturity][strike];
                callValue += valueOfCall(callAmount, strike, spot);
                putValue += valueOfPut(putAmount, strike, spot);
                delete containedStrikes[msg.sender][_maturity][strike];
                unchecked { i--; }
            }
        }
        //valueOfCall is inflated by _price parameter and valueOfCall thus only divide out spot from callValue not putValue
        //prevent div by 0, also there are no calls at a strike of 0 so this does not affect payout
        //If spot == 0 so will callValue so there there is no harm done by this safety check
        if (spot != 0) callValue /= spot;
        //deflate put value
        putValue /= strikeAssetSubUnits;
        delete strikes[msg.sender][_maturity];
        feeOracle fo = feeOracle(feeOracleAddress);
        uint _feeDenominator = fo.fetchFee(address(this));
        bool _feeImmunity = fo.isFeeImmune(address(this), msg.sender);
        if (callValue > internalUnderlyingAssetDeduction[msg.sender][_maturity]){
            callValue -= internalUnderlyingAssetDeduction[msg.sender][_maturity];
            uint fee = _feeImmunity ? 0 : callValue/_feeDenominator;
            internalUnderlyingAssetDeposits[owner] += fee;
            internalUnderlyingAssetDeposits[msg.sender] += callValue - fee;
        }
        if (putValue > internalStrikeAssetDeduction[msg.sender][_maturity]){
            putValue -= internalStrikeAssetDeduction[msg.sender][_maturity];
            uint fee = _feeImmunity ? 0 : putValue/_feeDenominator;
            internalStrikeAssetDeposits[owner] += fee;
            internalStrikeAssetDeposits[msg.sender] += putValue - fee;
        }
        success = true;
    }

    /*
        @Descripton: allows for users to withdraw funds that are not locked up as collateral
            these funds are tracked in the internalUnderlyingAssetDeposits mapping and the internalStrikeAssetDeposits mapping for the underlying and strike asset respectively

        @return uint underlyingAsset: the amount of the underlying asset that has been withdrawn
        @return uint strikeAsset: the amount of the strike asset that has been withdrawn
    */
    function withdrawFunds() public override returns(uint underlyingAsset, uint strikeAsset){
        IERC20 ua = IERC20(internalUnderlyingAssetAddress);
        underlyingAsset = internalUnderlyingAssetDeposits[msg.sender];
        internalUnderlyingAssetDeposits[msg.sender] = 0;
        ua.transfer(msg.sender, underlyingAsset);
        IERC20 sa = IERC20(internalStrikeAssetAddress);
        strikeAsset = internalStrikeAssetDeposits[msg.sender];
        internalStrikeAssetDeposits[msg.sender] = 0;
        sa.transfer(msg.sender, strikeAsset);
        underlyingAssetReserves -= underlyingAsset;
        strikeAssetReserves -= strikeAsset;
    }

    /*
        @Description: allows for users to deposit funds that are not tided up as collateral
            these funds are tracked in the internalUnderlyingAssetDeposits mapping and the internalStrikeAssetDeposits mapping for the underlying and strike asset respectively
    */
    function depositFunds(address _to) public override returns (bool success){
    	uint balance = IERC20(internalUnderlyingAssetAddress).balanceOf(address(this));
    	uint underlyingAsset = balance - underlyingAssetReserves;
    	underlyingAssetReserves = balance;
    	balance = IERC20(internalStrikeAssetAddress).balanceOf(address(this));
    	uint strikeAsset = balance - strikeAssetReserves;
    	strikeAssetReserves = balance;
    	internalUnderlyingAssetDeposits[_to] += underlyingAsset;
    	internalStrikeAssetDeposits[_to] += strikeAsset;
        success = true;
    }

    /*
        @Description: used to tell if strikes[givenAddress][givenMaturity] contains a given strike

        @param address _addr: the address is question
        @param uint _maturity: the maturity in question
        @param uint _strike: the strike price in question

        @return bool _contains: returns true if strike[_addr][_maturity] contains _strike otherwise returns false
    */
    function contains(address _addr, uint _maturity, uint _strike) public override view returns (bool _contains){
        _contains = containedStrikes[_addr][_maturity][_strike];
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
    function valueOfCall(int _amount, uint _strike, uint _price)internal pure returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price > _strike){
                //inflator is canceld when it is divided by out
                //payout = uint(_amount > 0 ? _amount : -_amount) * (_price * inflator - (_strike * inflator))/inflator;
                //payout = uint(_amount > 0 ? _amount : -_amount) * (_price - _strike) * inflator/inflator;
                payout = uint(_amount > 0 ? _amount : -_amount) * (_price - _strike);
            }
            if (_amount > 0){
                return payout;
            }
            else {
                return uint(-_amount)*_price - payout;
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

        @return uint value: the value of the position in terms of the strike asset inflated by strikeAssetSubUnits
    */
    function valueOfPut(int _amount, uint _strike, uint _price)internal pure returns(uint value){
        uint payout = 0;
        if (_amount != 0){
            if (_price < _strike){
                payout = (_strike - _price)*uint(_amount > 0 ? _amount : -_amount);
            }
            if (_amount > 0){
                return payout;
            }
            else {
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
    function addStrike(uint _maturity, uint _strike, uint _index) public override {
        require(_maturity > 0 && _strike > 0);
        uint size = strikes[msg.sender][_maturity].length;
        /*
            we put a limit of 15 strikes added so as to limit gas expenditure when users make market orders in the exchange
        */
        require(_index <= size && size < 15);
        if (_index > 0) require(_strike > strikes[msg.sender][_maturity][_index-1]);
        if (_index < size) require(_strike < strikes[msg.sender][_maturity][_index]);
        strikes[msg.sender][_maturity].push(_strike);
        unchecked {
            for (uint i = size-1; i >= _index && i != uint(int(-1)); i--)
                strikes[msg.sender][_maturity][i+1] = strikes[msg.sender][_maturity][i];
        }
        strikes[msg.sender][_maturity][_index] = _strike;
        containedStrikes[msg.sender][_maturity][_strike] = true;
    }


    /*
        @Description: view function for both callAmounts and putAmounts
    */
    function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) public override view returns(int256 balance){
        balance = _call ? callAmounts[_owner][_maturity][_strike] : putAmounts[_owner][_maturity][_strike];
    }


    /*
        @Description: add a strike to strikes[helperAddress][helperMaturity] and an amount to either callAmounts or putAmounts

        @param uint _strike: the strike of the position in question
        @param int _amount: the amount of the position in question
        @param bool _call: true if the position is for calls false if it is for puts
    */
    function addPosition(uint _strike, int _amount, bool _call) public override {
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
    function clearPositions() public override {
        delete strikes[helperAddress][helperMaturity];
    }

    /*
        @Description: multiplies all call/put Amounts by -1

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function inversePosition(bool _call) public override {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("inversePosition(bool)", _call));
        assert(success);
    }

    /*
        @Description:finds the maximum amount of collateral needed to take on a position

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function transferAmount(bool _call) public override returns (uint _debtorTransfer, uint _holderTransfer) {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("transferAmount(bool)", _call));
        assert(success);
        _debtorTransfer = uint(internalTransferAmountDebtor);
        _holderTransfer = uint(internalTransferAmountHolder);
    }


    /*
        @Description: assign the call position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignCallPosition() public override {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("assignCallPosition()"));
        assert(success);
    }


    /*
        @Description: assign the put position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignPutPosition() public override {
        (bool success, ) = assignOptionsDelegateAddress.delegatecall(abi.encodeWithSignature("assignPutPosition()"));
        assert(success);
    }

    /*
        @Description: set the values of debtor, holder, and maturity before calling assignCallPosition or assignPutPosition

        @param address _debtor: the address that will gain the opposite payoff profile of the position stored at helperAddress at helperMaturity
        @param address _holder: the address that will gain the payoff profile of the position stored at helperAddress at helperMaturity
        @param uint _maturity: the timestamp at which the puts may be exercised 
    */
    function setParams(address _debtor, address _holder, uint _maturity) public override {
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
    function setPaymentParams(bool _useDebtorInternalFunds, int _premium) public override {
        useDebtorInternalFunds = _useDebtorInternalFunds;
        premium = _premium;
    }

    //trusted address may be set to any FeldmexERC20Helper contract address
    function setTrustedAddressFeldmexERC20(uint _maturity, uint _strike, bool _call) public override {
        trustedAddress = _call ? 
            FeldmexERC20Helper(feldmexERC20HelperAddress).callAddresses(address(this), _maturity, _strike) :
            FeldmexERC20Helper(feldmexERC20HelperAddress).putAddresses(address(this), _maturity, _strike);
    }
    //set the trusted address to the exchange address
    function setTrustedAddressMainExchange() public override {trustedAddress = exchangeAddress;}
    //set the trusted address to a multi leg exchange
    function setTrustedAddressMultiLegExchange(uint8 _index) public override {trustedAddress = mOrganizer(mOrganizerAddress).exchangeAddresses(address(this), _index);}

    /*
        @Description: set the maximum values for the transfer amounts

        @param int _maxDebtorTransfer: the maximum amount for internalTransferAmountDebtor if this limit is breached assignPosition transactions will revert
        @param int _maxHolderTransfer: the maximum amount for internalTransferAmountHolder if this limit is breached assignPosition transactions will revert
    */
    function setLimits(int _maxDebtorTransfer, int _maxHolderTransfer) public override {
        maxDebtorTransfer = _maxDebtorTransfer;
        maxHolderTransfer = _maxHolderTransfer;
    }

    /*
        @Description: choose whether or not to use funds from underlyingAsset/internalStrikeAssetDeposits to fund collateral requirements or do a direct transfer

        @param bool _set: true => use internal deposits, false => call transferFrom to meet collateral requirements for msg.sender
    */
    function setUseDeposits(bool _set) public {internalUseDeposits[msg.sender] = _set;}


    //----------------------------view functions--------------------------------------------
    function underlyingAssetAddress() public override view returns(address) {return internalUnderlyingAssetAddress;}
    function strikeAssetAddress() public override view returns(address) {return internalStrikeAssetAddress;}
    function underlyingAssetDeposits(address _owner) public override view returns (uint) {return internalUnderlyingAssetDeposits[_owner];}
    function strikeAssetDeposits(address _owner) public override view returns (uint) {return internalStrikeAssetDeposits[_owner];}
    function underlyingAssetCollateral(address _addr, uint _maturity) public override view returns (uint) {return internalUnderlyingAssetCollateral[_addr][_maturity];}
    function strikeAssetCollateral(address _addr, uint _maturity) public override view returns (uint) {return internalStrikeAssetCollateral[_addr][_maturity];}
    function underlyingAssetDeduction(address _addr, uint _maturity) public override view returns (uint) {return internalUnderlyingAssetDeduction[_addr][_maturity];}
    function strikeAssetDeduction(address _addr, uint _maturity) public override view returns (uint) {return internalStrikeAssetDeduction[_addr][_maturity];}
    function useDeposits(address _addr) public override view returns (bool) {return internalUseDeposits[_addr];}
    function transferAmountDebtor() public override view returns (int) {return internalTransferAmountDebtor;}
    function transferAmountHolder() public override view returns (int) {return internalTransferAmountHolder;}
    function viewStrikes(address _addr, uint _maturity) public override view returns(uint[] memory){return strikes[_addr][_maturity];}
}