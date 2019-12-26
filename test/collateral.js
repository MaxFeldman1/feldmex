var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");

const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';

var maturity = 100;
var price = 177777;
var amount = 10;
var strike = 100;
var amount = 10;
var transferAmount = 1000;
var satUnits;
var scUnits;
var oracleInstance;
var tokenInstance;
var callsInstance;
var stablecoinInstance;
var defaultAccount;

contract('collateral', function(accounts) {
	it('can post and take buy orders', function(){
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
			return tokenInstance.transfer(reciverAccount, 2*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 2*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 2*transferAmount, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.postCollateral(2*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.postCollateral(2*transferAmount, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 2*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
			return collateralInstance.claimedToken(reciverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 2*satUnits*transferAmount, "correct amount of collateral claimed for " + reciverAccount);
			return collateralInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
			//return collateralInstance.postBuy(maturity, strike, price, amount, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			//return ret;
			return collateralInstance.linkedNodes(res);
		}).catch((err) => {console.log(err); assert.equal(false, true, "error thorwn this is the catch block!");}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Buy order");
			assert.equal(res.maturity, maturity, "the maturity of the option contract is correct");
			assert.equal(res.strike, strike, "the strike of the option contract is correct");
			assert.equal(res.price, price, "the price of the option contract is correct");
			assert.equal(res.amount, amount, "the amount of the option contract is correct");
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			firstSellAmount = 5;
			return collateralInstance.marketSell(maturity, strike, firstSellAmount, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstSellAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketSell(maturity, strike, amount-firstSellAmount+1, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketSell is correct");
			return collateralInstance.marketSell(maturity, strike, amount-1, {from:reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
			return collateralInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
			return collateralInstance.cancelOrder(res.name, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
		});
	});


	it('can post and take sell orders', function(){
		return collateralInstance.claimedToken(defaultAccount).then((res) => {
			assert.equal(res.toNumber() >= satUnits*transferAmount, true, "correct amount of collateral claimed for " + defaultAccount);
			return collateralInstance.claimedToken(reciverAccount);
		}).then((res) => {
			assert.equal(res.toNumber() >= satUnits*transferAmount, true, "correct amount of collateral claimed for " + reciverAccount);
			return collateralInstance.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});			
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).catch((err) => {console.log(err); assert.equal(false, true, "error thorwn this is the catch block!");}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Sell order");
			assert.equal(res.maturity, maturity, "the maturity of the option contract is correct");
			assert.equal(res.strike, strike, "the strike of the option contract is correct");
			assert.equal(res.price, price, "the price of the option contract is correct");
			assert.equal(res.amount, amount, "the amount of the option contract is correct");
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			firstSellAmount = 5;
			return collateralInstance.marketBuy(maturity, strike, firstSellAmount, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstSellAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketBuy(maturity, strike, amount-firstSellAmount+1, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketSell is correct");
			return collateralInstance.marketBuy(maturity, strike, amount-1, {from:reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
			return collateralInstance.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
			return collateralInstance.cancelOrder(res.name, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
		});
	});

});