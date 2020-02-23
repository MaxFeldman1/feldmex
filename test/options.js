var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
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

contract('options', function(accounts){
	it ('mints, exercizes call options', function(){
		return 	oracle.deployed().then((i) => {
			oracleInstance = i;
			return dappToken.deployed();
		}).then((i) => {
			tokenInstance = i;
			return options.deployed();
		}).then((i) => {
			optionsInstance = i;
			return stablecoin.deployed();
		}).then((i) => {
			stablecoinInstance = i;
			return web3.eth.getAccounts();
		}).then((accts) => {
			accounts = accts;
			defaultAccount = accounts[0];
			reciverAccount = accounts[1];
			return tokenInstance.satUnits();
		}).then((res) => {
			satUnits = res.toNumber();
			return stablecoinInstance.scUnits();
		}).then((res) => {
			scUnits = res.toNumber()
			return tokenInstance.approve(options.address, 1000, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(options.address, 1000, true, {from: defaultAccount});
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
			return optionsInstance.strikes(debtor, maturity, 0);
		}).then((res) => {
			assert.equal(res.toNumber(), strike, "the correct strike is added");
			return optionsInstance.callAmounts(debtor, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "debtor holds negative amount of contracts");
			return optionsInstance.callAmounts(holder, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "holder holds positive amount of contracts");
		}).then(() => {
			return optionsInstance.claim(maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: holder});
		}).then(() => {
			return optionsInstance.callAmounts(debtor, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "debtor's contracts have been exerciced");
			return optionsInstance.callAmounts(holder, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "holder's contracts have been exerciced");
		});
	});

	it('distributes funds correctly', function(){
		return optionsInstance.claimedTokens(debtor).then((res) => {
			payout = Math.floor(amount*satUnits*(finalSpot-strike)/finalSpot);
			assert.equal(res.toNumber(), satUnits*amount - (payout+1), "debtor repaid correct amount");
			return optionsInstance.claimedTokens(holder);
		}).then((res) => {
			assert.equal(res.toNumber(), payout, "holder compensated sufficiently")
			return;
		});
	});

	//note that this test will likely fail if the test above fails
	it('withdraws funds', function(){
		return optionsInstance.withdrawFunds({from: debtor}).then(() => {
			return optionsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return optionsInstance.contractTokenBalance();
		}).then((res) => {
			assert.equal(res.toNumber() <= 2, true, "non excessive amount of funds left");
		});
	});

	it('mints and exercizes put options', function() {
		return web3.eth.getBlock('latest').then((res) => {
			maturity = res.timestamp+1;
			return optionsInstance.mintPut(debtor, holder, maturity, strike, amount, strike*scUnits*amount, {from: defaultAccount});
		}).then(() => {
			difference = 30;
			return oracleInstance.set(strike - difference);
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 2000));
		}).then(() => {
			return optionsInstance.claim(maturity, {from: debtor});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: holder});
		}).then(() => {
			return optionsInstance.withdrawFunds({from: debtor});
		}).then(() => {
			return optionsInstance.claimedStable(holder);
		}).then((res) => {
			claimedSc = res.toNumber();
			return optionsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return stablecoinInstance.addrBalance(debtor, false);
		}).then((res) => {
			assert.equal(res.toNumber(), amount*strike*scUnits-difference*scUnits*amount, "correct amount sent to debtor of the put contract");
			return stablecoinInstance.addrBalance(holder, false);
		}).then((res) => {
			assert.equal(res.toNumber(), difference*scUnits*amount, "correct amount sent to the holder of the put contract");
			return;
		});
	});
});