pragma solidity >=0.8.0;
import "../interfaces/IERC20.sol";
import "../ERC20FeldmexOptions/FeldmexERC20Helper.sol";
import "./FeldmexOptionsData.sol";

contract assignOptionsDelegate is FeldmexOptionsData {

    //neccessary internal functions
    /*
        @Description: combine position stored at helperAddress at helperMaturity with another address at a specified maturity

        @param address _addr: the address of the account for which to combine the position stored at helperAddress at helperMaturity
        @param uint _maturity: the maturity for which to combine the position stored at helperAddress at helperMaturity
        @param bool _call: true if the position is for calls false if it is for puts        
    */
    function combinePosition(address _addr, uint _maturity, bool _call) internal {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity; //gas savings
        uint size = strikes[_helperAddress][_helperMaturity].length;
        if (_call) {
            for (uint i; i < size; i++) {
                uint strike = strikes[_helperAddress][_helperMaturity][i];
                int amount = callAmounts[_helperAddress][_helperMaturity][strike];
                if (!containedStrikes[_addr][_maturity][strike] && amount <= 0) {
                    assert(msg.sender == trustedAddress);
                }
                callAmounts[_addr][_maturity][strike] += amount;
            }
        } else {
            for (uint i; i < size; i++) {
                uint strike = strikes[_helperAddress][_helperMaturity][i];
                int amount = putAmounts[_helperAddress][_helperMaturity][strike];
                if (!containedStrikes[_addr][_maturity][strike] && amount <= 0) {
                    assert(msg.sender == trustedAddress);
                }
                putAmounts[_addr][_maturity][strike] += amount;
            }
        }
    }


    /*
        @Description: used to find the minimum amount of collateral that is required to to support call positions for a certain user at a given maturity

        @param address _addr: address in question
        @param uint _maturity: maturity in question

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in the underlying
        @return uint: sum of all short call positions multiplied by underlyingAssetSubUnits
    */
    function collateralCalls(address _addr, uint _maturity) internal view returns (uint minCollateral, uint liabilities) {
        int delta = 0;
        int value = 0;
        int cumulativeStrike;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            int strike = int(strikes[_addr][_maturity][i]);
            int amt = callAmounts[_addr][_maturity][uint(strike)];
            /*
                value = underlyingAssetSubUnits * sigma((delta*strike-cumulativeStrike)/strike)
            */
            int numerator = (delta*strike-cumulativeStrike);
            value = numerator/strike;
            cumulativeStrike += amt*int(strike);
            delta += amt;
            if (value < 0 && uint(-value) >= minCollateral) {
                if (numerator%strike != 0) value--;
                minCollateral = uint(-value);
            }
            if (amt < 0) liabilities+=uint(-amt);
        }
        //value at inf
        value = delta;
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
    }

    /*
        @Description: used to find the minimum amount of collateral that is required to to support put positions for a certain user at a given maturity

        @param address _addr: address in question
        @param uint _maturity: maturity in question

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in strike asset
        @return uint: negative value denominated in strikeAssetSubUnits of all short put postions at a spot price of 0
    */
    function collateralPuts(address _addr, uint _maturity) internal view returns(uint minCollateral, uint liabilities){
        int delta = 0;
        int value = 0;
        uint prevStrike;
        uint lastIndex;
        unchecked {
            lastIndex = strikes[_addr][_maturity].length-1;
        }

        for(uint i = lastIndex; i != uint(int(-1)); ) {
            uint strike = strikes[_addr][_maturity][i];
            int amt = putAmounts[_addr][_maturity][strike];
            value += delta * (int(prevStrike)-int(strike));
            delta += amt;
            prevStrike = strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (amt < 0) liabilities+=uint(-amt)*strike;
            unchecked { i--; }
        }
        //value at 0
        value += delta * int(prevStrike);
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
        minCollateral = minCollateral/strikeAssetSubUnits + (minCollateral%strikeAssetSubUnits == 0 ? 0 : 1);
        liabilities = liabilities/strikeAssetSubUnits + (liabilities%strikeAssetSubUnits == 0 ? 0 : 1);
    }


    /*
        @Description: change all balances contained by the helper address at the helper maturity to -1 * previous value
    */
    function inversePosition(bool _call) public {
        address _helperAddress = helperAddress;
        uint _helperMaturity = helperMaturity;
        uint size = strikes[_helperAddress][_helperMaturity].length;
        if (_call){
            for (uint i = 0; i < size; i++)
                callAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;
        } else {
            for (uint i = 0; i < size; i++)
                putAmounts[_helperAddress][_helperMaturity][strikes[_helperAddress][_helperMaturity][i]]*= -1;
        }
    }
    
    /*
        @Description: assign the call position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignCallPosition() public {
        int transferAmtDebtor;
        int transferAmtHolder;
        address _debtor = debtor;   //gas savings
        address _holder = holder;   //gas savings
        if (msg.sender == trustedAddress){
            int _premium = premium; //gas savings
            transferAmtHolder += _premium;
            transferAmtDebtor -= _premium;
        }
        uint _maturity = maturity; //gas savings
        combinePosition(_holder, _maturity, true);
        (uint minCollateral, uint liabilities) = collateralCalls(_holder, _maturity);

        if (minCollateral > internalUnderlyingAssetCollateral[_holder][_maturity])
            transferAmtHolder += int(minCollateral - internalUnderlyingAssetCollateral[_holder][_maturity]);
        else 
            internalUnderlyingAssetDeposits[_holder] += internalUnderlyingAssetCollateral[_holder][_maturity] - minCollateral;
        assert(transferAmtHolder <= int(maxHolderTransfer));
        if (msg.sender == trustedAddress && !useDebtorInternalFunds) {
            if (transferAmtHolder > 0){
                assert(internalUnderlyingAssetDeposits[_holder] >= uint(transferAmtHolder));
                internalUnderlyingAssetDeposits[_holder] -= uint(transferAmtHolder);
            } else {
                internalUnderlyingAssetDeposits[_holder] += uint(-transferAmtHolder);
            }
        }
        internalUnderlyingAssetCollateral[_holder][_maturity] = minCollateral;
        internalUnderlyingAssetDeduction[_holder][_maturity] = liabilities - minCollateral;
        
        inversePosition(true);

        combinePosition(_debtor, _maturity, true);
        (minCollateral, liabilities) = collateralCalls(_debtor, _maturity);

        if (minCollateral > internalUnderlyingAssetCollateral[_debtor][_maturity])
            transferAmtDebtor += int(minCollateral - internalUnderlyingAssetCollateral[_debtor][_maturity]);
        else
            internalUnderlyingAssetDeposits[_debtor] += internalUnderlyingAssetCollateral[_debtor][_maturity] - minCollateral;
        assert(transferAmtDebtor <= int(maxDebtorTransfer));
        if (msg.sender == trustedAddress && useDebtorInternalFunds) {
            if (transferAmtDebtor > 0){
                assert(internalUnderlyingAssetDeposits[_debtor] >= uint(transferAmtDebtor));
                internalUnderlyingAssetDeposits[_debtor] -= uint(transferAmtDebtor);
            } else {
                internalUnderlyingAssetDeposits[_debtor] += uint(-transferAmtDebtor);
            }
        }
        internalUnderlyingAssetCollateral[_debtor][_maturity] = minCollateral;
        internalUnderlyingAssetDeduction[_debtor][_maturity] = liabilities - minCollateral;
        int senderTransfer = (msg.sender == trustedAddress ? (useDebtorInternalFunds? transferAmtHolder: transferAmtDebtor) : transferAmtHolder+transferAmtDebtor);
        //fetch collateral
        if (internalUseDeposits[msg.sender]){
            assert(senderTransfer < 0 || int(internalUnderlyingAssetDeposits[msg.sender]) >= senderTransfer);
            internalUnderlyingAssetDeposits[msg.sender] = uint(int(internalUnderlyingAssetDeposits[msg.sender]) - senderTransfer);
        } else {
            if (senderTransfer > 0){
                IERC20(internalUnderlyingAssetAddress).transferFrom(msg.sender, address(this), uint(senderTransfer));
                underlyingAssetReserves += uint(senderTransfer);
            }
            else if (senderTransfer < 0){
                IERC20(internalUnderlyingAssetAddress).transfer(msg.sender, uint(-senderTransfer));            
                underlyingAssetReserves -= uint(-senderTransfer);
            }
        }
        internalTransferAmountDebtor = transferAmtDebtor;
        internalTransferAmountHolder = transferAmtHolder;
    }


    /*
        @Description: assign the put position stored at helperAddress at helperMaturity to a specitied address
            and assign the inverse to another specified address
    */
    function assignPutPosition() public {
        int transferAmtDebtor;
        int transferAmtHolder;
        address _debtor = debtor;   //gas savings
        address _holder = holder;   //gas savings
        if (msg.sender == trustedAddress){
            int _premium = premium; //gas savings
            transferAmtHolder += _premium;
            transferAmtDebtor -= _premium;
        }
        uint _maturity = maturity; //gas savings
        combinePosition(_holder, _maturity, false);
        (uint minCollateral, uint liabilities) = collateralPuts(_holder, _maturity);
        
        if (minCollateral > internalStrikeAssetCollateral[_holder][_maturity])
            transferAmtHolder += int(minCollateral - internalStrikeAssetCollateral[_holder][_maturity]);
        else
            internalStrikeAssetDeposits[_holder] += internalStrikeAssetCollateral[_holder][_maturity] - minCollateral;
        assert(transferAmtHolder <= int(maxHolderTransfer));
        if (msg.sender == trustedAddress && !useDebtorInternalFunds) {
            if (transferAmtHolder > 0){
                assert(internalStrikeAssetDeposits[_holder] >= uint(transferAmtHolder));
                internalStrikeAssetDeposits[_holder] -= uint(transferAmtHolder);
            } else {
                internalStrikeAssetDeposits[_holder] += uint(-transferAmtHolder);
            }
        }
        internalStrikeAssetCollateral[_holder][_maturity] = minCollateral;
        internalStrikeAssetDeduction[_holder][_maturity] = liabilities - minCollateral;

        //inverse positions for debtor
        inversePosition(false);

        combinePosition(_debtor, _maturity, false);
        (minCollateral, liabilities) = collateralPuts(_debtor, _maturity);

        if (minCollateral > internalStrikeAssetCollateral[_debtor][_maturity])
            transferAmtDebtor += int(minCollateral - internalStrikeAssetCollateral[_debtor][_maturity]);
        else
            internalStrikeAssetDeposits[_debtor] += internalStrikeAssetCollateral[_debtor][_maturity] - minCollateral;
        assert(transferAmtDebtor <= int(maxDebtorTransfer));
        if (msg.sender == trustedAddress && useDebtorInternalFunds) {
            if (transferAmtDebtor > 0){
                assert(internalStrikeAssetDeposits[_debtor] >= uint(transferAmtDebtor));
                internalStrikeAssetDeposits[_debtor] -= uint(transferAmtDebtor);
            } else {
                internalStrikeAssetDeposits[_debtor] += uint(-transferAmtDebtor);
            }
        }
        internalStrikeAssetCollateral[_debtor][_maturity] = minCollateral;
        internalStrikeAssetDeduction[_debtor][_maturity] = liabilities - minCollateral;
        int senderTransfer = (msg.sender == trustedAddress ? (useDebtorInternalFunds? transferAmtHolder: transferAmtDebtor) : transferAmtHolder+transferAmtDebtor);
        //fetch collateral
        if (internalUseDeposits[msg.sender]) {
            assert(senderTransfer < 0 || int(internalStrikeAssetDeposits[msg.sender]) >= senderTransfer);
            internalStrikeAssetDeposits[msg.sender] = uint(int(internalStrikeAssetDeposits[msg.sender]) - senderTransfer);
        } else {
            if (senderTransfer > 0){
                IERC20(internalStrikeAssetAddress).transferFrom(msg.sender, address(this), uint(senderTransfer));
                strikeAssetReserves += uint(senderTransfer);
            }
            else if (senderTransfer < 0){
                IERC20(internalStrikeAssetAddress).transfer(msg.sender, uint(-senderTransfer));
                strikeAssetReserves -= uint(-senderTransfer);
            }
        }
        internalTransferAmountDebtor = transferAmtDebtor;
        internalTransferAmountHolder = transferAmtHolder;
    }

    /*
        @Description:finds the maximum amount of collateral needed to take on a position

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function transferAmount(bool _call) public {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity;  //gas savings
        (uint result, ) = _call ? collateralCalls(_helperAddress, _helperMaturity) : collateralPuts(_helperAddress, _helperMaturity);
        internalTransferAmountHolder = int(result);
        inversePosition(_call);
        (result, ) = _call ? collateralCalls(_helperAddress, _helperMaturity) : collateralPuts(_helperAddress, _helperMaturity);
        internalTransferAmountDebtor = int(result);
    }

}