var oracle = artifacts.require("./oracle.sol");
var underlyingAsset = artifacts.require("./UnderlyingAsset.sol");
var options = artifacts.require("./options.sol");
var strikeAsset = artifacts.require("./strikeAsset.sol");

var strike = 100;
var finalSpot = 198;
var amount = 10;
var satUnits;
var scUnits;
var oracleInstance;
var tokenInstance;
var optionsInstance;
var strikeAssetInstance;
var defaultAccount;
var debtor;
var holder;
var feeDenominator = 0x4000000000000000000000000000000000000000000000000000000000000000;
var inflator;
var strikes = {};
var inflatorObj = {};
var setWithInflator;

contract('options', function(accounts){

	it('before each', async() => {
		return oracle.new().then((i) => {
			oracleInstance = i;
			return underlyingAsset.new(0);
		}).then((i) => {
			tokenInstance = i;
			return strikeAsset.new(0);
		}).then((i) => {
			strikeAssetInstance = i;
			return options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address);
		}).then((i) => {
			optionsInstance = i;
			inflatorObj = {};
			//setWithInflator sets spot and adjusts for the inflator
			setWithInflator = (_spot) => {return oracleInstance.set(_spot * inflator);};
			inflatorObj.addStrike = (maturity, strike, params) => {return optionsInstance.addStrike(maturity, strike*inflator, params);};
			inflatorObj.mintCall = (debtor, holder, maturity, strike, amount, limit, params) => {
				inflatorObj.addStrike(maturity, strike, {from: debtor});
				return inflatorObj.addStrike(maturity, strike, {from: holder}).then(() => {
					return optionsInstance.mintCall(debtor, holder, maturity, strike*inflator, amount, limit, params);
				});
			};
			inflatorObj.mintPut = (debtor, holder, maturity, strike, amount, limit, params) => {
				inflatorObj.addStrike(maturity, strike, {from: debtor});
				return inflatorObj.addStrike(maturity, strike, {from: holder}).then(() => {
					return optionsInstance.mintPut(debtor, holder, maturity, strike*inflator, amount, limit, params);
				});
			};
			inflatorObj.balanceOf = (address, maturity, strike, callPut) => {return optionsInstance.balanceOf(address, maturity, strike*inflator, callPut);};
			inflatorObj.transfer = (to, value, maturity, strike, maxTransfer, callPut, params) => {return optionsInstance.transfer(to, value, maturity, strike*inflator, maxTransfer, callPut, params);};
			inflatorObj.transferFrom = (from, to, value, maturity, strike, maxTransfer, callPut, params) => {return optionsInstance.transferFrom(from, to, value, maturity, strike*inflator, maxTransfer, callPut, params);};
			inflatorObj.approve = (spender, value, maturity, strike, callPut, params) => {return optionsInstance.approve(spender, value, maturity, strike*inflator, callPut, params);};
			feeDenominator = 1000;
			return optionsInstance.setFee(1000, {from: accounts[0]});
		});
	});


	it ('mints, exercizes call options', function(){
		defaultAccount = accounts[0];
		reciverAccount = accounts[1];
		return tokenInstance.decimals().then((res) => {
			satUnits = Math.pow(10, res);
			return strikeAssetInstance.decimals();
		}).then((res) => {
			scUnits = Math.pow(10, res);
			return optionsInstance.inflator()
		}).then((res) => {
			inflator = res.toNumber();			
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		}).then(() => {
			return strikeAssetInstance.approve(optionsInstance.address, 1000*scUnits, {from: defaultAccount});
		}).then(() => {
			return setWithInflator(finalSpot);
		}).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			debtor = accounts[1];
			holder = accounts[2];
			maturity = res.timestamp;
			return new Promise(resolve => setTimeout(resolve, 2000));
		}).then(() => {
			//add strikes to allow for minting of options
			return inflatorObj.addStrike(maturity, strike, {from: debtor});
		}).then(() => {
			return inflatorObj.addStrike(maturity, strike, {from: holder});
		}).then(() => {
			return optionsInstance.viewStrikes(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res[0].toNumber(), strike*inflator, "the correct strike is added");
			return inflatorObj.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount});
		}).then(() => {
			return inflatorObj.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "debtor holds negative amount of contracts");
			return inflatorObj.balanceOf(holder, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "holder holds positive amount of contracts");
		}).then(() => {
			return optionsInstance.claim(maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: holder});
		}).then(() => {
			return inflatorObj.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "debtor's contracts have been exerciced");
			return inflatorObj.balanceOf(holder, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "holder's contracts have been exerciced");
		});
	});

	it('distributes funds correctly', function(){
		return optionsInstance.viewClaimedTokens({from: debtor}).then((res) => {
			payout = Math.floor(amount*satUnits*(finalSpot-strike)/finalSpot);
			debtorExpected = satUnits*amount - (payout+1);
			//account for fee
			fee =  Math.floor(debtorExpected/feeDenominator);
			totalFees = fee;
			assert.equal(res.toNumber(), debtorExpected - fee, "debtor repaid correct amount");
			return optionsInstance.viewClaimedTokens({from: holder});
		}).then((res) => {
			fee = Math.floor(payout/feeDenominator);
			totalFees += fee;
			assert.equal(res.toNumber(), payout - fee, "holder compensated sufficiently")
			return;
		});
	});

	//note that this test will likely fail if the test above fails
	it('withdraws funds', function(){
		return optionsInstance.withdrawFunds({from: debtor}).then(() => {
			return optionsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return tokenInstance.balanceOf(optionsInstance.address);
		}).then((res) => {
			//we add 1 to total fees because we always subtract 1 from payout from sellers of calls
			assert.equal(res.toNumber() == 1+totalFees, true, "non excessive amount of funds left");
		});
	});

	it('mints and exercizes put options', function() {
		difference = 30;
		return setWithInflator(strike-difference).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			maturity = res.timestamp+1;
			//add strikes to allow for minting of options
			return inflatorObj.addStrike(maturity, strike, {from: debtor});
		}).then(() => {
			return inflatorObj.addStrike(maturity, strike, {from: holder});
		}).then(() => {
			return inflatorObj.mintPut(debtor, holder, maturity, strike, amount, strike*amount*scUnits, {from: defaultAccount});
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 2000));
		}).then(() => {
			return optionsInstance.claim(maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: holder});
		}).then(() => {
			return optionsInstance.withdrawFunds({from: debtor});
		}).then(() => {
			return optionsInstance.viewClaimedStable({from: holder});
		}).then((res) => {
			claimedSc = res.toNumber();
			return optionsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return strikeAssetInstance.balanceOf(debtor);
		}).then((res) => {
			debtorExpected = amount*scUnits*(strike-difference);
			//account for the fee
			debtorExpected -= Math.floor(debtorExpected/feeDenominator);
			assert.equal(res.toNumber(), debtorExpected, "correct amount sent to debtor of the put contract");
			return strikeAssetInstance.balanceOf(holder);
		}).then((res) => {
			holderExpected = difference*amount*scUnits;
			holderExpected -= Math.floor(holderExpected/feeDenominator);
			assert.equal(res.toNumber(), holderExpected, "correct amount sent to the holder of the put contract");
			return;
		});
	});

	it('sets exchange address only once', function(){
		//it does not matter what we set it to because we are not interacting with the exchange while testing
		return optionsInstance.setExchangeAddress(oracleInstance.address).catch((err) => {
			//res will only be defined if the above call fails
			return "Caught";
		}).then((res) => {
			assert.equal(res, "Caught", "cannot set exchange address multiple times");
			return optionsInstance.transferAmount(true, holder, maturity, amount, strike, {from: debtor});
		}).catch((err) => {
			//res will only be defined if the above call fails
			return "Caught";
		}).then((res) => {
			assert.equal(res, "Caught", "users cannot see the collateral requirements of other users");
		});
	})

	it('Implenents ERC 20', function(){
		maturity *= 2;
		strike = 50;
		return tokenInstance.transfer(debtor, 1000*satUnits, {from: defaultAccount}).then(() => {
			return strikeAssetInstance.transfer(debtor, 1000*strike*scUnits, {from: defaultAccount})
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		}).then(() => {
			return strikeAssetInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: debtor});
		}).then(() => {
			return strikeAssetInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: debtor});
		}).then(() => {
			return optionsInstance.depositFunds(900*satUnits, 1000*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.depositFunds(1000*satUnits, 1000*strike*scUnits, {from: debtor});
		}).then(() => {
			amount = 10;
			//debtor must accept transfers on a strike before recieving them
			return inflatorObj.addStrike(maturity, strike, {from: debtor});
		}).then(() => {
			return inflatorObj.transfer(debtor, amount, maturity, strike, amount*satUnits, true, {from: defaultAccount});
		}).then(() => {
			return inflatorObj.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "correct amount for the debtor");
			return inflatorObj.balanceOf(defaultAccount, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "correct amount for the defaultAccount");
			return optionsInstance.viewSatCollateral(maturity, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), amount*satUnits, "correct amount of collateral required for "+defaultAccount);
			return optionsInstance.viewSatCollateral(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct amount of collateral required from "+debtor);
			return optionsInstance.viewSatDeduction(maturity, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct sat deduction for "+defaultAccount);
			return optionsInstance.viewSatDeduction(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct sat deduction for "+debtor);
			return inflatorObj.transfer(debtor, amount, maturity, strike, amount*strike*scUnits, false, {from: defaultAccount});
		}).then(() => {
			newStrike = strike+10;
			return inflatorObj.approve(defaultAccount, amount, maturity, newStrike, false, {from: debtor});
		}).then(() => {
			//defaultAccount must accept transfers on a strike before recieving them
			return inflatorObj.addStrike(maturity, newStrike, {from: defaultAccount});
		}).then(() => {
			return inflatorObj.transferFrom(debtor, defaultAccount, amount, maturity, newStrike, amount*newStrike*scUnits, false, {from: defaultAccount});
		}).then(() => {
			return inflatorObj.balanceOf(debtor, maturity, strike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "correct put balance at strike "+strike+" for "+debtor);
			return inflatorObj.balanceOf(debtor, maturity, newStrike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "correct put balance at strike "+newStrike+" for "+debtor);
			return inflatorObj.balanceOf(defaultAccount, maturity, strike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "correct put balance at strike "+strike+" for "+defaultAccount);
			return inflatorObj.balanceOf(defaultAccount, maturity, newStrike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "correct put balance at strike "+newStrike+" for "+defaultAccount);
			return optionsInstance.viewScCollateral(maturity, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct amount of collateral for "+defaultAccount);
			return optionsInstance.viewScCollateral(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res.toNumber(), (newStrike-strike)*amount*scUnits, "correct amount of collateral for "+debtor);
			return optionsInstance.viewScDeduction(maturity, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), strike*amount*scUnits, "correct SC Deduction for "+defaultAccount);
			return optionsInstance.viewScDeduction(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res.toNumber(), strike*amount*scUnits, "correct SC deduction for "+debtor);
		});
		//debtor ---- short 50 long 60 ---- liabilities 50 minSc 0 minVal 50
		//default --- long 50 short 60 ---- liabilities 60 minSc 10 minVal 50
	});

	it('changes the fee', function(){
		deployer = defaultAccount;
		nonDeployer = reciverAccount;
		return optionsInstance.setFee(1500, {from: deployer}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OK", "Successfully changed the fee");
			return optionsInstance.setFee(400, {from: deployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because fee was too high");
			return optionsInstance.setFee(800, {from: nonDeployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because the sender was not the deployer");
		});
	});

	it('requires strike to be added before minting contract', function(){
		//get new maturity strike combination that has not been added
		maturity += 1;
		//test for calls with neither adding the maturity strike combo
		return inflatorObj.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint call without adding the maturity strike combo for either account');
			//test for puts with neither adding the maturity strike combo
			return inflatorObj.mintPut(debtor, holder, maturity, strike, amount, scUnits*amount*strike, {from: defaultAccount});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint put without adding the maturity strike combo for either account');
			return optionsInstance.addStrike(maturity, strike, {from: debtor});
		}).then(() => {
			//test for calls with only debtor adding the maturity strike combo
			return inflatorObj.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint call without adding maturity strike combo for holder account');
			//test for puts with only debtor adding the maturity strike combo
			return inflatorObj.mintPut(debtor, holder, maturity, strike, amount, scUnits*amount*strike, {from: defaultAccount});			
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint put without adding maturity strike combo for holder account');
			maturity +=1;
			//test for calls with only holder adding the maturity strike combo
			return optionsInstance.addStrike(maturity, strike, {from: holder});			
		}).then(() => {
			return inflatorObj.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount});			
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint call without adding maturity strike combo for debtor account');
			//test for puts with only debtor adding the maturity strike combo
			return inflatorObj.mintPut(debtor, holder, maturity, strike, amount, scUnits*amount*strike, {from: defaultAccount});			
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", 'could not mint put without adding maturity strike combo for debtor account');
			//if there were a problem with minting calls or puts after adding the strikes for both users it would have shown up earlier
		});
	});

	it('approves and exempts addresses from fees', function(){
		spot = strike+10;
		return setWithInflator(spot).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			maturity = res.timestamp;
			maxTransfer = satUnits*amount;
			//wait one second to allow for maturity to pass
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, maxTransfer, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.balanceOf(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber() >= maxTransfer, true, "balance is large enough");
			return inflatorObj.mintCall(defaultAccount, reciverAccount, maturity, strike, amount, maxTransfer, {from: defaultAccount});
		}).then(() => {
			feeDenominator = 1000;
			return optionsInstance.setFee(1000, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.viewClaimedTokens({from: reciverAccount});
		}).then((res) => {
			prevBalance = res.toNumber();
			return optionsInstance.changeFeeStatus(reciverAccount, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.feeImmunity(reciverAccount);
		}).then((res) => {
			assert.equal(res, true, "fee immunity granted to receiver account");
			return optionsInstance.claim(maturity, {from: reciverAccount});
		}).then(() => {
			return optionsInstance.viewClaimedTokens({from: reciverAccount});
		}).then((res) => {
			//note that there is no fee present when calculating balance
			assert.equal(res.toNumber(), prevBalance + Math.floor(satUnits*amount*(spot-strike)/spot), "No fee charged on reciverAccount's call to options.claim");
			return optionsInstance.changeFeeStatus(reciverAccount, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.feeImmunity(reciverAccount);			
		}).then((res) => {
			assert.equal(res, false, "fee immunity revoked for receiver account");
			maturity++;
			maxTransfer = scUnits*amount*strike;
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return strikeAssetInstance.approve(optionsInstance.address, maxTransfer, {from: defaultAccount});
		}).then(() => {
			return inflatorObj.mintPut(reciverAccount, defaultAccount, maturity, strike, amount, maxTransfer, {from: defaultAccount});
		}).then((res) => {
			return optionsInstance.viewClaimedStable({from: reciverAccount});
		}).then((res) => {
			prevBalance = res.toNumber();
			//option expired worthless reciverAccount gets back all collateral
			return optionsInstance.claim(maturity, {from: reciverAccount});
		}).then(() => {
			return optionsInstance.viewClaimedStable({from: reciverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), prevBalance+maxTransfer-Math.floor(maxTransfer/feeDenominator), "fee is now charged again");
		});
	});
});