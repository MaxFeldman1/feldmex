var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");
var stablecoin = artifacts.require("./stablecoin.sol");

var strike = 100;
var finalSpot = 198;
var amount = 10;
var satUnits;
var scUnits;
var oracleInstance;
var tokenInstance;
var callsInstance;
var stablecoinInstance;
var defaultAccount;
var debtor;
var holder;

contract('calls', function(accounts){
	it ('mints, exercizes call options', function(){
		return 	oracle.deployed().then((i) => {
			oracleInstance = i;
			return dappToken.deployed();
		}).then((i) => {
			tokenInstance = i;
			return calls.deployed();
		}).then((i) => {
			callsInstance = i;
			return collateral.deployed();
		}).then((i) => {
			collateralInstance = i;
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
			return tokenInstance.approve(calls.address, 1000, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(calls.address, 1000, true, {from: defaultAccount});
		}).then(() => {
			return oracleInstance.height();
		}).then((res) => {
			height = res.toNumber();
			debtor = accounts[1];
			holder = accounts[2];
			maturity = height+2;
			return callsInstance.mintCall(debtor, holder, maturity, strike, amount, {from: defaultAccount});
		}).then(() => {
			return callsInstance.callAmounts(debtor, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), -amount, "debtor holds negative amount of contracts");
			return callsInstance.callAmounts(holder, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), amount, "holder holds positive amount of contracts");
		}).then(() => {
			return oracleInstance.set(finalSpot);
		}).then(() => {
			return callsInstance.claim(maturity, strike, {from: debtor});
		}).then(async (res) => {
			return callsInstance.claim(maturity, strike, {from: holder});
		}).then(() => {
			return callsInstance.callAmounts(debtor, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "debtor's contracts have been exerciced");
			return callsInstance.callAmounts(holder, maturity, strike);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "holder's contracts have been exerciced");
		});
	});

	it('distributes funds correctly', function(){
		return callsInstance.claimedTokens(debtor).then((res) => {
			payout = Math.floor(amount*satUnits*(finalSpot-strike)/finalSpot);
			assert.equal(res.toNumber(), satUnits*amount - (payout+1), "debtor repaid correct amount");
			return callsInstance.claimedTokens(holder);
		}).then((res) => {
			assert.equal(res.toNumber(), payout, "holder compensated sufficiently")
			return;
		});
	});

	it('withdraws funds', function(){
		return callsInstance.withdrawFunds({from: debtor}).then(() => {
			return callsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return callsInstance.contractTokenBalance();
		}).then((res) => {
			assert.equal(res.toNumber() <= 2, true, "non excessive amount of funds left");
		});
	});

	it('mints and exercizes put options', function() {
		return oracleInstance.height().then((res) => {
			maturity = res.toNumber() + 2;
			return callsInstance.mintPut(debtor, holder, maturity, strike, amount, {from: defaultAccount});
		}).then(() => {
			difference = 30;
			return oracleInstance.set(strike - difference);
		}).then(() => {
			return callsInstance.claim(maturity, strike, {from: debtor});
		}).then(() => {
			return callsInstance.claim(maturity, strike, {from: holder});
		}).then(() => {
			return callsInstance.withdrawFunds({from: debtor});
		}).then(() => {
			return callsInstance.withdrawFunds({from: holder});
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