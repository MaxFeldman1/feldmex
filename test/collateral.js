var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var options = artifacts.require("./options.sol");
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
var optionsInstance;
var stablecoinInstance;
var defaultAccount;
var receiverAccount;
var defaultAccountBalance;
var receiverAccountBalance;

contract('collateral', function(accounts) {
	it('can post and take buy orders of calls', function(){
		return 	oracle.deployed().then((i) => {
			oracleInstance = i;
			return dappToken.deployed();
		}).then((i) => {
			tokenInstance = i;
			return options.deployed();
		}).then((i) => {
			optionsInstance = i;
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
			receiverAccount = accounts[1];
			return tokenInstance.satUnits();
		}).then((res) => {
			satUnits = res.toNumber();
			return stablecoinInstance.scUnits();
		}).then((res) => {
			scUnits = res.toNumber();
			return tokenInstance.transfer(receiverAccount, 10*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 10*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(collateral.address, 10*transferAmount, true, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.transfer(receiverAccount, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(collateral.address, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(collateral.address, 10*transferAmount*strike, true, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.postCollateral(10*transferAmount, true, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.postCollateral(10*transferAmount, true, 10*transferAmount*strike, true, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
			defaultAccountBalance = res.toNumber();
			return collateralInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + receiverAccount);
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= amount*price;
			return collateralInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
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
			defaultAccountBalance -= (price-10000)*amount;
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			firstSellAmount = 5;
			return collateralInstance.marketSell(maturity, strike, firstSellAmount, true, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstSellAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketSell(maturity, strike, amount-firstSellAmount+1, true, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketSell is correct");
			return collateralInstance.marketSell(maturity, strike, 2*amount-1, true, {from:receiverAccount});
		}).then(() => {
			//we have not updated the receiverAccountBalance yet so we will aggregate the impact of all orders here
			receiverAccountBalance -= (satUnits*2*amount) - (amount*(2*price-10000));
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
			//now we make sure the balances of each user are correct
			return collateralInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default Account balance is correct");
			return collateralInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver Account balance is correct");
			return;
		});
	});

	it('can post and take sell orders of calls', function(){
		return collateralInstance.claimedToken(defaultAccount).then((res) => {
			defaultAccountBalance = res.toNumber();
			return collateralInstance.claimedToken(receiverAccount);
		}).then((res) => {
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= satUnits*amount;
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
			defaultAccountBalance -= satUnits*amount;
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			firstBuyAmount = 5;
			return collateralInstance.marketBuy(maturity, strike, firstBuyAmount, true, {from: receiverAccount});
		}).then((res) => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstBuyAmount, "the amount of the contract has decreaced the correct amount");
			return collateralInstance.marketBuy(maturity, strike, amount-firstBuyAmount+1, true, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketBuy is correct");
			//make market order larges than the size of the sell book
			return collateralInstance.marketBuy(maturity, strike, 2*amount-1, true, {from: receiverAccount});
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
			//we will now aggregate the effects of all the buy orders on the account balances;
			defaultAccountBalance += amount*(2*price-10000);
			receiverAccountBalance -= amount*(2*price-10000);
			return collateralInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "defaultAccount has the correct balance");
			return collateralInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "recieverAccount has the correct balance");
			return;
		});
	});

	it('can post and take buy orders of puts', function(){
		return collateralInstance.claimedStable(defaultAccount).then((res) => {
			defaultAccountBalance = res.toNumber();
			return collateralInstance.claimedStable(receiverAccount);
		}).then((res) => {
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= price*amount;
			return collateralInstance.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		}).then(() => {
			defaultAccountBalance -= (price+10000)*amount;
			return collateralInstance.postOrder(maturity, strike, price+10000, amount, true, false, {from: defaultAccount})
		}).then(() => {
			defaultAccountBalance -= (price+5000)*amount;
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
			defaultAccountBalance += (price+10000)*amount;
			return collateralInstance.cancelOrder(head);
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			assert.equal(res != head, true, "the of the list updates when the order is removed");
			head = res
			firstSellAmount = amount-4;
			return collateralInstance.marketSell(maturity, strike, firstSellAmount, false, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.linkedNodes(head);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-firstSellAmount, "the amount left in the list head has decreaced the correct amount");
			return collateralInstance.marketSell(maturity, strike, amount+1, false, {from: receiverAccount});
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
			//aggregate impact of all market orders on the receiver account
			receiverAccountBalance -= (amount+firstSellAmount+1)*strike*scUnits -(amount*(price+5000)+(1+firstSellAmount)*price);
			return collateralInstance.claimedStable(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default account balance is correct");
			return collateralInstance.claimedStable(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver account balance is correct");
			return;
		});
	});

	it('can post and take sell orders of puts', function(){
		return collateralInstance.claimedStable(defaultAccount).then((res) => {
			defaultAccountBalance = res.toNumber();
			return collateralInstance.claimedStable(receiverAccount);
		}).then((res) => {
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= strike*amount*scUnits;
			return collateralInstance.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {512-471-2900
			defaultAccountBalance -= strike*amount*scUnits;
			return collateralInstance.postOrder(maturity, strike, price-10000, amount, false, false, {from: defaultAccount});
		}).then(() => {
			defaultAccountBalance -= strike*amount*scUnits;
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
			defaultAccountBalance += strike*amount*scUnits;
			return collateralInstance.cancelOrder(head, {from: defaultAccount});
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
			return collateralInstance.marketBuy(maturity, strike, firstBuyAmount, false, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.offers(current);
		}).then((res)  => {
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount, "the amount has been decremented correctly");
			return collateralInstance.marketBuy(maturity, strike, amount+1, false, {from: receiverAccount});
		}).then(() => {
			return collateralInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "the price of the last node order is correct");
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount-1, "the amount has decremented correctly");
			//aggregate impact of market orders on both accounts
			defaultAccountBalance += amount*(price-5000) + (firstBuyAmount+1)*price;
			receiverAccountBalance -= amount*(price-5000) + (firstBuyAmount+1)*price;
			return collateralInstance.claimedStable(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "defaultAccount has the correct balance");
			return collateralInstance.claimedStable(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiverAccount has the correct balance");
		});
	});

	it('inserts orders', function(){
		altMaturity = maturity+5;
		return collateralInstance.postOrder(altMaturity, strike, price, amount, true, true, {from: defaultAccount}).then(() => {
			return collateralInstance.postOrder(altMaturity, strike, price+10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(altMaturity, strike, 0);
		}).then((res) => {
			prevHead = res;
			return collateralInstance.insertOrder(altMaturity, strike, price+20000, amount, true, true, prevHead, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.listHeads(altMaturity, strike, 0);
		}).then((res) => {
			assert.notEqual(res, prevHead);
			newHead = res;
			return collateralInstance.linkedNodes(res);
		}).then((res) => {
			thirdAddNode = res.next;
			assert.equal(thirdAddNode, prevHead, "The next node is the previous head node");
			assert.equal(res.previous, defaultBytes32, "The head node has no previous node");
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.maturity, altMaturity, "The head has the correct maturity");
			assert.equal(res.price, price+20000, "The price is correct");
			assert.equal(res.strike, strike, "the strike is correct");
			return collateralInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.equal(res.previous, newHead, "The previous of the previous head has been updated");
			thirdAddNode = res.next;
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price+10000, "The price of the second offer is correct");
			return collateralInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.equal(res.next, defaultBytes32, "The last node in the list has no next node");
			assert.equal(res.previous, prevHead, "The previous of the last node is correct");
			return collateralInstance.insertOrder(altMaturity, strike, price+5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		}).then(() => {
			return collateralInstance.insertOrder(altMaturity, strike, price-5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		}).then(() => {
			//now the second to last node in the list
			return collateralInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.notEqual(res.previous, prevHead, "The previous of the last node has updated");
			assert.notEqual(res.next, defaultBytes32, "The next of the node has updated")
			frem = res.next;
			tilbake = res.previous;
			return collateralInstance.linkedNodes(frem);
		}).then((res) => {
			assert.equal(res.next, defaultBytes32, "The next of the last node is null");
			assert.equal(res.previous, thirdAddNode, "The previous of the last node is correct");
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price-5000, "The price of the last node is correct");
			return collateralInstance.linkedNodes(tilbake);
		}).then((res) => {
			assert.equal(res.next, thirdAddNode, "The next of the node is correct");
			assert.equal(res.previous, prevHead, "The precious of the node is correct");
			return collateralInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+5000, "The price of the node is correct");
			return;
		});
	});
});