var oracle = artifacts.require("./oracle.sol");
var underlyingAsset = artifacts.require("./UnderlyingAsset.sol");
var options = artifacts.require("./options.sol");
var stablecoin = artifacts.require("./stablecoin.sol");

var strike = 100;
var finalSpot = 198;
var amount = 10;
var satUnits;
var scUnits;
var oracleInstance;
var tokenInstance;
var optionsInstance;
var stablecoinInstance;
var defaultAccount;
var debtor;
var holder;
var feeDenominator = 0x4000000000000000000000000000000000000000000000000000000000000000;

contract('options', function(accounts){

	it('before each', async() => {
		return oracle.new().then((i) => {
			oracleInstance = i;
			return underlyingAsset.new(0);
		}).then((i) => {
			tokenInstance = i;
			return stablecoin.new(0);
		}).then((i) => {
			stablecoinInstance = i;
			return options.new(oracleInstance.address, tokenInstance.address, stablecoinInstance.address);
		}).then((i) => {
			optionsInstance = i;
			feeDenominator = 1000;
			return optionsInstance.setFee(1000, {from: accounts[0]});
		});
	});


	it ('mints, exercizes call options', function(){
		defaultAccount = accounts[0];
		reciverAccount = accounts[1];
		return tokenInstance.satUnits().then((res) => {
			satUnits = res.toNumber();
			return stablecoinInstance.scUnits();
		}).then((res) => {
			scUnits = res.toNumber()
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(optionsInstance.address, 1000*scUnits, {from: defaultAccount});
		}).then(() => {
			return oracleInstance.set(finalSpot);
		}).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			debtor = accounts[1];
			holder = accounts[2];
			maturity = res.timestamp;
			return new Promise(resolve => setTimeout(resolve, 2000));
		}).then((res) => {
			return optionsInstance.mintCall(debtor, holder, maturity, strike, amount, satUnits*amount, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.viewStrikes(maturity, {from: debtor});
		}).then((res) => {
			assert.equal(res[0].toNumber(), strike, "the correct strike is added");
			return optionsInstance.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "debtor holds negative amount of contracts");
			return optionsInstance.balanceOf(holder, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "holder holds positive amount of contracts");
		}).then(() => {
			return optionsInstance.claim(maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: holder});
		}).then(() => {
			return optionsInstance.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "debtor's contracts have been exerciced");
			return optionsInstance.balanceOf(holder, maturity, strike, true);
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
		return oracleInstance.set(strike-difference).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			maturity = res.timestamp+1;
			return optionsInstance.mintPut(debtor, holder, maturity, strike, amount, strike*scUnits*amount, {from: defaultAccount});
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
			return stablecoinInstance.balanceOf(debtor);
		}).then((res) => {
			debtorExpected = amount*strike*scUnits-difference*scUnits*amount;
			//account for fee
			debtorExpected -= Math.floor(debtorExpected/feeDenominator);
			assert.equal(res.toNumber(), debtorExpected, "correct amount sent to debtor of the put contract");
			return stablecoinInstance.balanceOf(holder);
		}).then((res) => {
			holderExpected = difference*scUnits*amount;
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
			return stablecoinInstance.transfer(debtor, 1000*strike*scUnits, {from: defaultAccount})
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, 1000*satUnits, {from: debtor});
		}).then(() => {
			return stablecoinInstance.approve(optionsInstance.address, 1000*strike*scUnits, {from: debtor});
		}).then(() => {
			return optionsInstance.depositFunds(900*satUnits, 1000*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.depositFunds(1000*satUnits, 1000*strike*scUnits, {from: debtor});
		}).then(() => {
			amount = 10;
			//debtor must accept transfers on a strike before recieving them
			return optionsInstance.addStrike(strike, maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.transfer(debtor, amount, maturity, strike, amount*satUnits, true, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.balanceOf(debtor, maturity, strike, true);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "correct amount for the debtor");
			return optionsInstance.balanceOf(defaultAccount, maturity, strike, true);
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
			return optionsInstance.transfer(debtor, amount, maturity, strike, amount*strike*scUnits, false, {from: defaultAccount});
		}).then(() => {
			newStrike = strike+10;
			return optionsInstance.approve(defaultAccount, amount, maturity, newStrike, false, {from: debtor});
		}).then(() => {
			//defaultAccount must accept transfers on a strike before recieving them
			return optionsInstance.addStrike(newStrike, maturity, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.transferFrom(debtor, defaultAccount, amount, maturity, newStrike, amount*newStrike*scUnits, false, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.balanceOf(debtor, maturity, strike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "correct put balance at strike "+strike+" for "+debtor);
			return optionsInstance.balanceOf(debtor, maturity, newStrike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "correct put balance at strike "+newStrike+" for "+debtor);
			return optionsInstance.balanceOf(defaultAccount, maturity, strike, false);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "correct put balance at strike "+strike+" for "+defaultAccount);
			return optionsInstance.balanceOf(defaultAccount, maturity, newStrike, false);
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

	it ('changes the fee', function(){
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
});