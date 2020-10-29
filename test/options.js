const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("options");
const strikeAsset = artifacts.require("strikeAsset");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");
const BN = web3.utils.BN;
const helper = require("../helper/helper.js");

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
var allMaturities = [];

contract('options', async function(accounts){

	async function setFee(denominator, params) {
		//only set fee in only the options instance
		await feeOracleInstance.setBaseFee(denominator, params);
	}

	it('before each', async () => {
		tokenInstance = await token.new(0);
		strikeAssetInstance = await strikeAsset.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address, accounts[0], assignOptionsDelegateInstance.address, feeOracleInstance.address);
		assert.equal(await feeOracleInstance.specificFeeImmunity(optionsInstance.address, accounts[0]), true, "owner of optionsContract is feeImmune");
		feeDenominator = 1000;
		await setFee(1000, {from: accounts[0]});
		defaultAccount = accounts[0];
		reciverAccount = accounts[1];
		satUnits = (new web3.utils.BN("10")).pow(await tokenInstance.decimals());
		scUnits = (new web3.utils.BN("10")).pow(await strikeAssetInstance.decimals());
		inflator = scUnits;
		satUnits = satUnits.toNumber();
		scUnits = scUnits.toNumber();
		inflatorObj = {};
		//setWithInflator sets spot and adjusts for the inflator
		setWithInflator = async (_spot) => {
			_spot = (new BN(_spot)).mul(inflator).toString();
			//because median of last 3 is returned by oracle we must set spot 2 times
			await oracleInstance.set(_spot);
			await oracleInstance.set(_spot);
		};
		inflatorObj.mintCall = async (debtor, holder, maturity, strike, amount, limit, params) => {
			await addStrike(debtor, maturity, strike);
			await addStrike(holder, maturity, strike);
			await optionsInstance.setUseDeposits(false);
			await optionsInstance.clearPositions();
			var str = (new BN(strike)).mul(new BN(scUnits)).toString();
			await optionsInstance.addPosition(str, amount, true);
			await optionsInstance.setParams(debtor, holder, maturity);
			await optionsInstance.setLimits(limit, 0);
			return optionsInstance.assignCallPosition(params);
		};
		inflatorObj.mintPut = async (debtor, holder, maturity, strike, amount, limit, params) => {
			await addStrike(debtor, maturity, strike);
			await addStrike(holder, maturity, strike);
			await optionsInstance.setUseDeposits(false);
			await optionsInstance.clearPositions();
			var str = (new BN(strike)).mul(new BN(scUnits)).toString();
			await optionsInstance.addPosition(str, amount, false);
			await optionsInstance.setParams(debtor, holder, maturity);
			await optionsInstance.setLimits(limit, 0);
			return optionsInstance.assignPutPosition(params);
		};
		inflatorObj.balanceOf = (address, maturity, strike, callPut) => {
			return optionsInstance.balanceOf(address, maturity, (new BN(strike)).mul((new BN(scUnits))).toString(), callPut);
		};
	});

	async function addStrike(from, maturity, strike) {
		strike*=scUnits;
		strikes = await optionsInstance.viewStrikes(maturity, {from});
		var index = 0;
		for (;index < strikes.length; index++){ 
			if (strikes[index] == strike) return;
			if (strikes[index] > strike) break;
		}
		await optionsInstance.addStrike(maturity, strike, index, {from});
	}

	async function depositFunds(sats, sc, params) {
		await tokenInstance.transfer(optionsInstance.address, sats, params);
		await strikeAssetInstance.transfer(optionsInstance.address, sc, params);
		return optionsInstance.depositFunds(params.from);
	}

	it ('mints, exercizes call options', async () => {
		await tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		await strikeAssetInstance.approve(optionsInstance.address, 1000*scUnits, {from: defaultAccount});
		await setWithInflator(finalSpot);
		debtor = accounts[1];
		holder = accounts[2];
		maturity = (await web3.eth.getBlock('latest')).timestamp;
		allMaturities.push(maturity);
		await helper.advanceTime(2);
		//add strikes to allow for minting of options
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		res = await optionsInstance.viewStrikes(maturity, {from: debtor});
		assert.equal(res[0].toNumber(), strike*scUnits, "the correct strike is added");
		await inflatorObj.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount});
		assert.equal((await inflatorObj.balanceOf(debtor, maturity, strike, true)).toNumber(), -amount, "debtor holds negative amount of contracts");
		assert.equal((await inflatorObj.balanceOf(holder, maturity, strike, true)).toNumber(), amount, "holder holds positive amount of contracts");
		await optionsInstance.claim(maturity, {from: debtor});
		await optionsInstance.claim(maturity, {from: holder});
		await inflatorObj.balanceOf(debtor, maturity, strike, true);
		assert.equal((await inflatorObj.balanceOf(debtor, maturity, strike, true)).toNumber(), 0, "debtor's contracts have been exerciced");
		assert.equal((await inflatorObj.balanceOf(holder, maturity, strike, true)).toNumber(), 0, "holder's contracts have been exerciced");
	});

	it('distributes funds correctly', async () => {
		payout = Math.floor(amount*satUnits*(finalSpot-strike)/finalSpot);
		debtorExpected = satUnits*amount - (payout+1);
		//account for fee
		fee =  Math.floor(debtorExpected/feeDenominator);
		totalFees = fee;
		assert.equal((await optionsInstance.viewClaimedTokens({from: debtor})).toNumber(), debtorExpected - fee, "debtor repaid correct amount");
		fee = Math.floor(payout/feeDenominator);
		totalFees += fee;
		assert.equal((await optionsInstance.viewClaimedTokens({from: holder})).toNumber(), payout - fee, "holder compensated sufficiently")
	});

	//note that this test will likely fail if the test above fails
	it('withdraws funds', async () => {
		await optionsInstance.withdrawFunds({from: debtor});
		await optionsInstance.withdrawFunds({from: holder});
		//we add 1 to total fees because we always subtract 1 from payout from sellers of calls
		assert.equal((await tokenInstance.balanceOf(optionsInstance.address)).toNumber(), 1+totalFees, "non excessive amount of funds left");
	});

	it('mints and exercizes put options', async () => {
		difference = 30;
		await setWithInflator(strike-difference);
		maturity = (await web3.eth.getBlock('latest')).timestamp+1;
		allMaturities.push(maturity);
		//add strikes to allow for minting of options
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		await inflatorObj.mintPut(debtor, holder, maturity, strike, amount, strike*amount*scUnits, {from: defaultAccount});
		await helper.advanceTime(2);
		await optionsInstance.claim(maturity, {from: debtor});
		await optionsInstance.claim(maturity, {from: holder});
		await optionsInstance.withdrawFunds({from: debtor});
		claimedSc = (await optionsInstance.viewClaimedStable({from: holder})).toNumber();
		await optionsInstance.withdrawFunds({from: holder});
		debtorExpected = amount*scUnits*(strike-difference);
		//account for the fee
		debtorExpected -= Math.floor(debtorExpected/feeDenominator);
		assert.equal((await strikeAssetInstance.balanceOf(debtor)).toNumber(), debtorExpected, "correct amount sent to debtor of the put contract");
		holderExpected = difference*amount*scUnits;
		holderExpected -= Math.floor(holderExpected/feeDenominator);
		assert.equal((await strikeAssetInstance.balanceOf(holder)).toNumber(), holderExpected, "correct amount sent to the holder of the put contract");
	});

	it('sets exchange address only once', async () => {
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

	it('Correct collateral requirements with multi leg option positions', async () => {
		maturity *= 2;
		allMaturities.push(maturity);
		strike = 50;
		//here we will use funds alreay deposited in the options smart contract
		async function optionTransfer(to, amount, maturity, strike, maxTransfer, call, params) {
			await addStrike(to, maturity, strike);
			await addStrike(params.from, maturity, strike);
			await optionsInstance.setUseDeposits(true, params);
			await optionsInstance.clearPositions();
			await optionsInstance.addPosition(strike*scUnits, amount, call);
			await optionsInstance.setParams(params.from, to, maturity);
			await optionsInstance.setLimits(maxTransfer, 0);
			if (call) await optionsInstance.assignCallPosition(params);
			else await optionsInstance.assignPutPosition(params);
		}

		await tokenInstance.transfer(debtor, 1000*satUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(debtor, 1000*strike*scUnits, {from: defaultAccount});
		await tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		await strikeAssetInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: defaultAccount});
		await tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: debtor});
		await strikeAssetInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: debtor});
		await depositFunds(900*satUnits, 1000*strike*scUnits, {from: defaultAccount});
		await depositFunds(1000*satUnits, 1000*strike*scUnits, {from: debtor});
		amount = 10;
		//debtor must accept transfers on a strike before recieving them
		await optionTransfer(debtor, amount, maturity, strike, amount*satUnits, true, {from: defaultAccount});
		assert.equal((await inflatorObj.balanceOf(debtor, maturity, strike, true)).toNumber(), amount, "correct amount for the debtor");
		assert.equal((await inflatorObj.balanceOf(defaultAccount, maturity, strike, true)).toNumber(), -amount, "correct amount for the defaultAccount");
		assert.equal((await optionsInstance.viewSatCollateral(maturity, {from: defaultAccount})).toNumber(), amount*satUnits, "correct amount of collateral required for "+defaultAccount);
		assert.equal((await optionsInstance.viewSatCollateral(maturity, {from: debtor})).toNumber(), 0, "correct amount of collateral required from "+debtor);
		assert.equal((await optionsInstance.viewSatDeduction(maturity, {from: defaultAccount})).toNumber(), 0, "correct sat deduction for "+defaultAccount);
		assert.equal((await optionsInstance.viewSatDeduction(maturity, {from: debtor})).toNumber(), 0, "correct sat deduction for "+debtor);
		await optionTransfer(debtor, amount, maturity, strike, amount*strike*scUnits, false, {from: defaultAccount});
		newStrike = strike+10;
		//defaultAccount must accept transfers on a strike before recieving them
		await optionTransfer(defaultAccount, amount, maturity, newStrike, amount*newStrike*scUnits, false, {from: debtor});
		assert.equal((await inflatorObj.balanceOf(debtor, maturity, strike, false)).toNumber(), amount, "correct put balance at strike "+strike+" for "+debtor);
		assert.equal((await inflatorObj.balanceOf(debtor, maturity, newStrike, false)).toNumber(), -amount, "correct put balance at strike "+newStrike+" for "+debtor);
		assert.equal((await inflatorObj.balanceOf(defaultAccount, maturity, strike, false)).toNumber(), -amount, "correct put balance at strike "+strike+" for "+defaultAccount);
		assert.equal((await inflatorObj.balanceOf(defaultAccount, maturity, newStrike, false)).toNumber(), amount, "correct put balance at strike "+newStrike+" for "+defaultAccount);
		assert.equal((await optionsInstance.viewScCollateral(maturity, {from: defaultAccount})).toNumber(), 0, "correct amount of collateral for "+defaultAccount);
		assert.equal((await optionsInstance.viewScCollateral(maturity, {from: debtor})).toNumber(), (newStrike-strike)*amount*scUnits, "correct amount of collateral for "+debtor);
		assert.equal((await optionsInstance.viewScDeduction(maturity, {from: defaultAccount})).toNumber(), strike*amount*scUnits, "correct SC Deduction for "+defaultAccount);
		assert.equal((await optionsInstance.viewScDeduction(maturity, {from: debtor})).toNumber(), strike*amount*scUnits, "correct SC deduction for "+debtor);
		//debtor ---- short 50 long 60 ---- liabilities 50 minSc 0 minVal 50
		//default --- long 50 short 60 ---- liabilities 60 minSc 10 minVal 50
	});

	it('changes the fee', async () => {
		deployer = defaultAccount;
		nonDeployer = reciverAccount;
		return setFee(1500, {from: deployer}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OK", "Successfully changed the fee");
			return setFee(400, {from: deployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because fee was too high");
			return setFee(800, {from: nonDeployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because the sender was not the deployer");
		});
	});

	it('requires strike to be added before minting contract', async () => {
		//get new maturity strike combination that has not been added
		maturity++;
		allMaturities.push(maturity);
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
			return addStrike(debtor, maturity, strike);
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
			maturity++;
			allMaturities.push(maturity);
			//test for calls with only holder adding the maturity strike combo
			return addStrike(holder, maturity, strike);
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

	it('mints 4+ leg put positions with correct collateral requirements', async () => {
		//get new maturity
		maturity++;
		allMaturities.push(maturity);
		await optionsInstance.clearPositions();
		//iorn condor made of puts
		await optionsInstance.addPosition(strike*scUnits, amount, false);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, -amount, false);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, -amount, false);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, amount, false);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);

		var expectedCollateralRequirement = 10*amount*scUnits;
		var expectedDebtorRequirement = expectedCollateralRequirement;
		var expectedHolderRequirement = 0;
		//hold exactly the correct amount of collateral in the options smart contract
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await depositFunds(0 , expectedCollateralRequirement, {from: defaultAccount});
		await optionsInstance.setUseDeposits(true, {from: defaultAccount});
		await optionsInstance.setParams(debtor, holder, maturity);
		await optionsInstance.setLimits(expectedDebtorRequirement, expectedHolderRequirement);
		await optionsInstance.assignPutPosition({from: defaultAccount});
		assert.equal((await optionsInstance.viewClaimedStable({from: defaultAccount})).toNumber(), 0, "correct amount of funds left over");
		assert.equal((await optionsInstance.transferAmountDebtor()).toNumber(), expectedDebtorRequirement, "correct debtor fund requirement");
		assert.equal((await optionsInstance.viewScCollateral(maturity, {from: debtor})).toNumber(), expectedDebtorRequirement, "correct debtor fund requirement");
		assert.equal((await optionsInstance.transferAmountHolder()).toNumber(), expectedHolderRequirement, "correct holder fund requirement");
		assert.equal((await optionsInstance.viewScCollateral(maturity, {from: holder})).toNumber(), expectedHolderRequirement, "correct holder fund requirement");
	});

	it('mints 4+ leg call positions with correct collateral requirements', async () => {
		//get new maturity
		maturity++;
		allMaturities.push(maturity);
		await optionsInstance.clearPositions();
		//iorn condor made of calls
		await optionsInstance.addPosition(strike*scUnits, amount, true);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, -amount, true);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, -amount, true);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);
		strike+=10;
		await optionsInstance.addPosition(strike*scUnits, amount, true);
		await addStrike(debtor, maturity, strike);
		await addStrike(holder, maturity, strike);

		var expectedCollateralRequirement = Math.ceil(amount*satUnits*10/(strike-20));
		var expectedDebtorRequirement = expectedCollateralRequirement;
		var expectedHolderRequirement = 0;
		//hold exactly the correct amount of collateral in the options smart contract
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await depositFunds(expectedCollateralRequirement, 0, {from: defaultAccount});
		await optionsInstance.setUseDeposits(true, {from: defaultAccount});
		await optionsInstance.setParams(debtor, holder, maturity);
		await optionsInstance.setLimits(expectedDebtorRequirement, expectedHolderRequirement);
		await optionsInstance.assignCallPosition({from: defaultAccount});
		assert.equal((await optionsInstance.viewClaimedTokens({from: defaultAccount})).toNumber(), 0, "correct amount of funds left over");
		assert.equal((await optionsInstance.transferAmountDebtor()).toNumber(), expectedDebtorRequirement, "correct debtor fund requirement");
		assert.equal((await optionsInstance.viewSatCollateral(maturity, {from: debtor})).toNumber(), expectedDebtorRequirement, "correct debtor fund requirement");
		assert.equal((await optionsInstance.transferAmountHolder()).toNumber(), expectedHolderRequirement, "correct holder fund requirement");
		assert.equal((await optionsInstance.viewSatCollateral(maturity, {from: holder})).toNumber(), expectedHolderRequirement, "correct holder fund requirement");
	});

	it('withdraws funds sucessfully after asigning complex orders', async () => {
		await helper.advanceTime(allMaturities[allMaturities.length-1]);
		for (let i = 0; i < allMaturities.length; i++){
			await optionsInstance.claim(allMaturities[i], {from: accounts[0]});
			await optionsInstance.claim(allMaturities[i], {from: accounts[1]});
			await optionsInstance.claim(allMaturities[i], {from: accounts[2]});
		}
		allMaturities.push(maturity);
		await optionsInstance.withdrawFunds({from: accounts[1]});
		await optionsInstance.withdrawFunds({from: accounts[2]});
		//withdraw fees with owner key
		await optionsInstance.withdrawFunds({from: accounts[0]});
		assert.equal((await tokenInstance.balanceOf(optionsInstance.address)).toNumber(), 4, "non excessive amount of funds left");
	});
});