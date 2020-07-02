pragma solidity >=0.5.0;
import "./interfaces/ERC20.sol";
import "./FeldmexERC20Helper.sol";
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
                    address ERC20WrapperAddress = FeldmexERC20Helper(feldmexERC20HelperAddress).callERC20s(address(this), _maturity, strike);
                    assert(msg.sender == ERC20WrapperAddress);
                }
                callAmounts[_addr][_maturity][strike] += amount;
            }
        } else {
            for (uint i; i < size; i++) {
                uint strike = strikes[_helperAddress][_helperMaturity][i];
                int amount = putAmounts[_helperAddress][_helperMaturity][strike];
                if (!containedStrikes[_addr][_maturity][strike] && amount <= 0) {
                    address ERC20WrapperAddress = FeldmexERC20Helper(feldmexERC20HelperAddress).putERC20s(address(this), _maturity, strike);
                    assert(msg.sender == ERC20WrapperAddress);
                }
                putAmounts[_addr][_maturity][strike] += amount;
            }
        }
    }


    /*
        @Description: used to find the minimum amount of collateral that is required to to support call positions for a certain user at a given maturity
            also takes into account an extra position that is entered in the last two parameters
            The purpose of adding having the extra position in the last two parameters is that it allows for 

        @param address _addr: address in question
        @param uint _maturity: maturity in question
        @param int _amount: the amount of the added position
        @param uint _strike: the strike price of the added position

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in the underlying
        @return uint: sum of all short call positions multiplied by satUnits
    */
    function minSats(address _addr, uint _maturity) internal view returns (uint minCollateral, uint liabilities) {
        uint _satUnits = satUnits; //gas savings
        int delta = 0;
        int value = 0;
        int cumulativeStrike;
        for (uint i = 0; i < strikes[_addr][_maturity].length; i++){
            int strike = int(strikes[_addr][_maturity][i]);
            int amt = callAmounts[_addr][_maturity][uint(strike)];
            /*
                value = satUnits * sigma((delta*strike-cumulativeStrike)/strike)
            */
            int numerator = int(satUnits) * (delta*strike-cumulativeStrike);
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
        value = int(_satUnits)*delta;
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
        liabilities *= _satUnits;
    }

    /*
        @Description: used to find the minimum amount of collateral that is required to to support put positions for a certain user at a given maturity
            also takes into account an extra position that is entered in the last two parameters

        @param address _addr: address in question
        @param uint _maturity: maturity in question
        @param int _amount: the amount of the added position
        @param uint _strike: the strike price of the added position

        @return uint: the minimum amount of collateral that must be locked up by the address at the maturity denominated in strike asset
        @return uint: negative value denominated in scUnits of all short put postions at a spot price of 0
    */
    function minSc(address _addr, uint _maturity) internal view returns(uint minCollateral, uint liabilities){
        int delta = 0;
        int value = 0;
        uint prevStrike;
        uint lastIndex = strikes[_addr][_maturity].length-1;
        for(uint i = lastIndex; i != uint(-1); i--) {
            uint strike = strikes[_addr][_maturity][i];
            int amt = putAmounts[_addr][_maturity][strike];
            value += delta * int(prevStrike-strike);
            delta += amt;
            prevStrike = strike;
            if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
            if (amt < 0) liabilities+=uint(-amt)*strike;
        }
        //value at 0
        value += delta * int(prevStrike);
        if (value < 0 && uint(-value) > minCollateral) minCollateral = uint(-value);
    }


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
        (uint minCollateral, uint liabilities) = minSats(_holder, _maturity);

        if (minCollateral > satCollateral[_holder][_maturity])
            transferAmtHolder += int(minCollateral - satCollateral[_holder][_maturity]);
        else 
            claimedTokens[_holder] += satCollateral[_holder][_maturity] - minCollateral;
        assert(transferAmtHolder <= int(maxHolderTransfer));
        if (msg.sender == trustedAddress && !useDebtorInternalFunds) {
            if (transferAmtHolder > 0){
                assert(claimedTokens[_holder] >= uint(transferAmtHolder));
                claimedTokens[_holder] -= uint(transferAmtHolder);
            } else {
                claimedTokens[_holder] += uint(-transferAmtHolder);
            }
        }
        satCollateral[_holder][_maturity] = minCollateral;
        satDeduction[_holder][_maturity] = liabilities - minCollateral;
        
        inversePosition(true);

        combinePosition(_debtor, _maturity, true);
        (minCollateral, liabilities) = minSats(_debtor, _maturity);

        if (minCollateral > satCollateral[_debtor][_maturity])
            transferAmtDebtor += int(minCollateral - satCollateral[_debtor][_maturity]);
        else
            claimedTokens[_debtor] += satCollateral[_debtor][_maturity] - minCollateral;
        assert(transferAmtDebtor <= int(maxDebtorTransfer));
        if (msg.sender == trustedAddress && useDebtorInternalFunds) {
            if (transferAmtDebtor > 0){
                assert(claimedTokens[_debtor] >= uint(transferAmtDebtor));
                claimedTokens[_debtor] -= uint(transferAmtDebtor);
            } else {
                claimedTokens[_debtor] += uint(-transferAmtDebtor);
            }
        }
        satCollateral[_debtor][_maturity] = minCollateral;
        satDeduction[_debtor][_maturity] = liabilities - minCollateral;
        int senderTransfer = (msg.sender == trustedAddress ? (useDebtorInternalFunds? transferAmtHolder: transferAmtDebtor) : transferAmtHolder+transferAmtDebtor);
        //fetch collateral
        if (useDeposits[msg.sender]){
            assert(senderTransfer < 0 || int(claimedTokens[msg.sender]) >= senderTransfer);
            claimedTokens[msg.sender] = uint(int(claimedTokens[msg.sender]) - senderTransfer);
        } else {
            if (senderTransfer > 0){
                ERC20(underlyingAssetAddress).transferFrom(msg.sender, address(this), uint(senderTransfer));
                satReserves += uint(senderTransfer);
            }
            else{
                ERC20(underlyingAssetAddress).transfer(msg.sender, uint(-senderTransfer));            
                satReserves -= uint(-senderTransfer);
            }
        }
        transferAmountDebtor = transferAmtDebtor;
        transferAmountHolder = transferAmtHolder;
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
        (uint minCollateral, uint liabilities) = minSc(_holder, _maturity);
        
        if (minCollateral > scCollateral[_holder][_maturity])
            transferAmtHolder += int(minCollateral - scCollateral[_holder][_maturity]);
        else
            claimedStable[_holder] += scCollateral[_holder][_maturity] - minCollateral;
        assert(transferAmtHolder <= int(maxHolderTransfer));
        if (msg.sender == trustedAddress && !useDebtorInternalFunds) {
            if (transferAmtHolder > 0){
                assert(claimedStable[_holder] >= uint(transferAmtHolder));
                claimedStable[_holder] -= uint(transferAmtHolder);
            } else {
                claimedStable[_holder] += uint(-transferAmtHolder);
            }
        }
        scCollateral[_holder][_maturity] = minCollateral;
        scDeduction[_holder][_maturity] = liabilities - minCollateral;

        //inverse positions for debtor
        inversePosition(false);

        combinePosition(_debtor, _maturity, false);
        (minCollateral, liabilities) = minSc(_debtor, _maturity);

        if (minCollateral > scCollateral[_debtor][_maturity])
            transferAmtDebtor += int(minCollateral - scCollateral[_debtor][_maturity]);
        else
            claimedStable[_debtor] += scCollateral[_debtor][_maturity] - minCollateral;
        assert(transferAmtDebtor <= int(maxDebtorTransfer));
        if (msg.sender == trustedAddress && useDebtorInternalFunds) {
            if (transferAmtDebtor > 0){
                assert(claimedStable[_debtor] >= uint(transferAmtDebtor));
                claimedStable[_debtor] -= uint(transferAmtDebtor);
            } else {
                claimedStable[_debtor] += uint(-transferAmtDebtor);
            }
        }
        scCollateral[_debtor][_maturity] = minCollateral;
        scDeduction[_debtor][_maturity] = liabilities - minCollateral;
        int senderTransfer = (msg.sender == trustedAddress ? (useDebtorInternalFunds? transferAmtHolder: transferAmtDebtor) : transferAmtHolder+transferAmtDebtor);
        //fetch collateral
        if (useDeposits[msg.sender]) {
            assert(senderTransfer < 0 || int(claimedStable[msg.sender]) >= senderTransfer);
            claimedStable[msg.sender] = uint(int(claimedStable[msg.sender]) - senderTransfer);
        } else {
            if (senderTransfer > 0){
                ERC20(strikeAssetAddress).transferFrom(msg.sender, address(this), uint(senderTransfer));
                scReserves += uint(senderTransfer);
            }
            else{
                ERC20(strikeAssetAddress).transfer(msg.sender, uint(-senderTransfer));
                scReserves -= uint(-senderTransfer);
            }
        }
        transferAmountDebtor = transferAmtDebtor;
        transferAmountHolder = transferAmtHolder;
    }

    /*
        @Description:finds the maximum amount of collateral needed to take on a position

        @param bool _call: true if the position is for calls false if it is for puts
    */
    function transferAmount(bool _call) public {
        address _helperAddress = helperAddress; //gas savings
        uint _helperMaturity = helperMaturity;  //gas savings
        (uint result, ) = _call ? minSats(_helperAddress, _helperMaturity) : minSc(_helperAddress, _helperMaturity);
        transferAmountHolder = int(result);
        inversePosition(_call);
        (result, ) = _call ? minSats(_helperAddress, _helperMaturity) : minSc(_helperAddress, _helperMaturity);
        transferAmountDebtor = int(result);
    }

}