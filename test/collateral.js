var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");

contract('oracle', function(accounts){

	const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';

	it('can post orders', function(){
		return oracle.deployed().then((i) => {
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
			return tokenInstance.transfer(reciverAccount, 1000, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 1000, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.postCollateral(1000, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.claimed(defaultAccount);
		}).then((res) => {
			assert.equal(1000*satUnits, res.toNumber(), "the posted collateral is equal to what the contract states");
			maturity = 100;
			strike = 100;
			price = 177777;
			amount = 10;
			node = {};
			node.name = defaultBytes32;
			node.hash = defaultBytes32;
			node.next = defaultBytes32;
			node.previous = defaultBytes32;
			return collateralInstance.postBuy(maturity, strike, price, amount, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, stike, 0);
		}).then((res) => {
			node = res;
		}).catch((res) => {assert.notEqual(res.name, defaultBytes32, "listHeads mapping returned valid value");
		}).then(() => {
			return collateralInstance.offers(node.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the poster");
			assert.equal(res.maturity, maturity, "maturity is correct");
			assert.equal(res.strike, strike, "strike is correct");
			assert.equal(res.price, price, "price is correct");
			assert.equal(res.amount, amount, "amount is correct");
			return collateralInstance.postSell(maturity, strike, price, amount, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, stike, 1);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the poster");
			assert.equal(res.maturity, maturity, "maturity is correct");
			assert.equal(res.strike, strike, "strike is correct");
			assert.equal(res.price, price, "price is correct");
			assert.equal(res.amount, amount, "amount is correct");
		});
	});
});