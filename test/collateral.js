var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");
var stablecoin = artifacts.require("./stablecoin.sol");

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
	it('can post and take buy orders of calls', function(){
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
			return tokenInstance.transfer(reciverAccount, 10*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 10*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 10*transferAmount, true, {from: reciverAccount});
		}).then(() => {
			return stablecoinInstance.transfer(reciverAccount, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(collateral.address, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(collateral.address, 10*transferAmount*strike, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.postCollateral(10*transferAmount, true, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.postCollateral(10*transferAmount, true, 10*transferAmount*strike, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
			return collateralInstance.claimedToken(reciverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + reciverAccount);
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
			return collateralInstance.marketSell(maturity, strike, firstSellAmount, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstSellAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketSell(maturity, strike, amount-firstSellAmount+1, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketSell is correct");
			return collateralInstance.marketSell(maturity, strike, amount-1, true, {from:reciverAccount});
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

	it('can post and take sell orders of calls', function(){
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
			assert.equal(res.maturity.toNumber(), maturity, "the maturity of the option contract is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike of the option contract is correct");
			assert.equal(res.price.toNumber(), price, "the price of the option contract is correct");
			assert.equal(res.amount.toNumber(), amount, "the amount of the option contract is correct");
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			firstBuyAmount = 5;
			return collateralInstance.marketBuy(maturity, strike, firstBuyAmount, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstBuyAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketBuy(maturity, strike, amount-firstBuyAmount+1, true, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketBuy is correct");
			return collateralInstance.marketBuy(maturity, strike, amount-1, true, {from: reciverAccount});
		}).then((res) => {
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

	it('can post and take buy orders of puts', function(){
		return collateralInstance.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount}).then(() => {
			return collateralInstance.postOrder(maturity, strike, price+10000, amount, true, false, {from: defaultAccount})
		}).then(() => {
			return collateralInstance.postOrder(maturity, strike, price+5000, amount, true, false, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			head = res;
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
			assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
			assert.equal(res.price.toNumber(), price+10000, "the price in the list head order is correct");
			assert.equal(res.buy, true, "the head order in the long puts linked list is classified as a buy order")
			assert.equal(res.call, false, "the head order in the long puts linked list is classified as a put order")			
			return collateralInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+5000, "the price is correct in the second node in the linkedList");
			return collateralInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "the price is correct in the third node in the linkedList");
			return collateralInstance.cancelOrder(head);
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			assert.equal(res != head, true, "the of the list updates when the order is removed");
			head = res
			firstSellAmount = amount-4;
			return collateralInstance.marketSell(maturity, strike, firstSellAmount, false, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.linkedNodes(head);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-firstSellAmount, "the amount left in the list head has decreaced the correct amount");
			return collateralInstance.marketSell(maturity, strike, amount+1, false, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			assert.equal(head != res, true, "head updates again");
			head = res;
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-firstSellAmount-1, "the amount in the orders after three orders is still correct");
		});
	});

	it('can post and take sell orders of puts', function(){
		return collateralInstance.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount}).then(() => {
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.postOrder(maturity, strike, price-5000, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			head = res;
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
			assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
			assert.equal(res.price.toNumber(), price-10000, "the price in the list head order is correct");
			assert.equal(res.buy, false, "the head order in the long puts linked list is classified as a sell order");
			assert.equal(res.call, false, "the head order in the long puts linked list is classified as a put order");			
			return collateralInstance.cancelOrder(head);
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			assert.equal(res, next, "the list head updates to the next node");
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			current = res.hash;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price-5000, "the new list head has the correct price");
			firstBuyAmount = amount-4;
			return collateralInstance.marketBuy(maturity, strike, firstBuyAmount, false, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.offers(current);
		}).then((res)  => {
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount, "the amount has been decremented correctly");
			return collateralInstance.marketBuy(maturity, strike, amount+1, false, {from: reciverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "the price of the last node order is correct");
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount-1, "the amount has decremented correctly");
			return;
		});
	});
});