var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");

var strike = 100;
var finalSpot = 198;
var amount = 10;

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
			return web3.eth.getAccounts();
		}).then((accts) => {
			accounts = accts;
			defaultAccount = accounts[0];
			reciverAccount = accounts[1];
			return tokenInstance.satUnits();
		}).then((res) => {
			satUnits = res.toNumber();
			return tokenInstance.approve(calls.address, 1000, true, {from: defaultAccount});
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
			return web3.eth.getAccounts();
		}).then((accts) => {
			accounts = accts;
			debtor = accounts[1];
			holder = accounts[2];
			payout = Math.floor(amount*satUnits*(finalSpot-strike)/finalSpot);
			return tokenInstance.satUnits();
		}).then((res) => {
			satUnits = res.toNumber();
			return callsInstance.collateral(debtor);
		}).then((res) => {
			assert.equal(res.toNumber(), satUnits*amount - (payout+1), "debtor repaid correct amount");
			return callsInstance.collateral(holder);
		}).then((res) => {
			assert.equal(res.toNumber(), payout, "holder compensated sufficiently")
			return;
		});
	});

	it('withdraws funds', function(){
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
			return web3.eth.getAccounts();
		}).then((accts) => {
			accounts = accts;
			debtor = accounts[1];
			holder = accounts[2];
			return callsInstance.withdrawFunds({from: debtor});
		}).then(() => {
			return callsInstance.withdrawFunds({from: holder});
		}).then(() => {
			return callsInstance.contractBalance();
		}).then((res) => {
			assert.equal(res.toNumber() <= 2, true, "non excessive amount of funds left");
		});
	});
});