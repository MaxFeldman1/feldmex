var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var options = artifacts.require("./options.sol");
var exchange = artifacts.require("./exchange.sol");
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
var exchangeInstance;
var defaultAccount;
var receiverAccount;
var defaultAccountBalance;
var receiverAccountBalance;

var defaultAccountPosition = 0;
var receiverAccountPosition = 0;

contract('exchange', function(accounts) {
	it('can post and take buy orders of calls', function(){
		return 	oracle.deployed().then((i) => {
			oracleInstance = i;
			return dappToken.deployed();
		}).then((i) => {
			tokenInstance = i;
			return options.deployed();
		}).then((i) => {
			optionsInstance = i;
			return exchange.deployed();
		}).then((i) => {
			exchangeInstance = i;
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
			return tokenInstance.approve(exchange.address, 10*transferAmount, true, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(exchange.address, 10*transferAmount, true, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.transfer(receiverAccount, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchange.address, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchange.address, 10*transferAmount*strike, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(10*transferAmount, true, 10*transferAmount*strike, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(10*transferAmount, true, 10*transferAmount*strike, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + receiverAccount);
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= amount*price;
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).catch((err) => {console.log(err); assert.equal(false, true, "error thorwn this is the catch block!");}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Buy order");
			assert.equal(res.maturity, maturity, "the maturity of the option contract is correct");
			assert.equal(res.strike, strike, "the strike of the option contract is correct");
			assert.equal(res.price, price, "the price of the option contract is correct");
			assert.equal(res.amount, amount, "the amount of the option contract is correct");
			defaultAccountBalance -= (price-10000)*amount;
			return exchangeInstance.postOrder(maturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			firstSellAmount = 5;
			receiverAccountPosition -= firstSellAmount;
			defaultAccountPosition += firstSellAmount;
			return exchangeInstance.marketSell(maturity, strike, 0, firstSellAmount, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstSellAmount, "the amount of the contract has decreaced the correct amount");
			receiverAccountPosition -= amount-firstSellAmount+1;
			defaultAccountPosition += amount-firstSellAmount+1;
			return exchangeInstance.marketSell(maturity, strike, 0, amount-firstSellAmount+1, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketSell is correct");
			receiverAccountPosition -= amount-1;
			defaultAccountPosition += amount-1;
			return exchangeInstance.marketSell(maturity, strike, 0, 2*amount-1, true, {from:receiverAccount});
		}).then(() => {
			//we have not updated the receiverAccountBalance yet so we will aggregate the impact of all orders here
			receiverAccountBalance -= (satUnits*2*amount) - (amount*(2*price-10000));
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
			return exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
			//now we make sure the balances of each user are correct
			return exchangeInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default Account balance is correct");
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver Account balance is correct");
			return;
		});
	});

	it('can post and take sell orders of calls', function(){
		return exchangeInstance.claimedToken(defaultAccount).then((res) => {
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});			
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).catch((err) => {console.log(err); assert.equal(false, true, "error thorwn this is the catch block!");}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Sell order");
			assert.equal(res.maturity.toNumber(), maturity, "the maturity of the option contract is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike of the option contract is correct");
			assert.equal(res.price.toNumber(), price, "the price of the option contract is correct");
			assert.equal(res.amount.toNumber(), amount, "the amount of the option contract is correct");
			return exchangeInstance.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			firstBuyAmount = 5;
			return exchangeInstance.marketBuy(maturity, strike, price+100000, firstBuyAmount, true, {from: receiverAccount});
		}).then((res) => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, firstBuyAmount, "the amount of the contract has decreaced the correct amount");
			return exchangeInstance.marketBuy(maturity, strike, price+100000, amount-firstBuyAmount+1, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-1, "amount of second order after marketBuy is correct");
			return exchangeInstance.marketBuy(maturity, strike, price+100000, 2*amount-1, true, {from: receiverAccount});
		}).then((res) => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
			return exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
			return exchangeInstance.claimedToken(defaultAccount);
		}).then((res) => {
			defaultTotal = res.toNumber();
			return optionsInstance.claimedTokens(receiverAccount);
		}).then((res) => {
			optRecTotal = res.toNumber();
			assert.equal(defaultTotal, 10*transferAmount*satUnits, "defaultAccount has correct balance");
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			recTotal = res.toNumber();
			return optionsInstance.claimedTokens(receiverAccount);
		}).then((res) => {
			recTotal += res.toNumber();			
			assert.equal(recTotal, 10*transferAmount*satUnits, "recieverAccount has the correct balance");
			return;
		});
	});

	it('can post and take buy orders of puts', function(){
		return exchangeInstance.claimedStable(defaultAccount).then((res) => {
			receiverAccountPosition = 0;
			defaultAccountPosition = 0;
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= price*amount;
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		}).then(() => {
			defaultAccountBalance -= (price+10000)*amount;
			return exchangeInstance.postOrder(maturity, strike, price+10000, amount, true, false, {from: defaultAccount})
		}).then(() => {
			defaultAccountBalance -= (price+5000)*amount;
			return exchangeInstance.postOrder(maturity, strike, price+5000, amount, true, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			head = res;
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
			assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
			assert.equal(res.price.toNumber(), price+10000, "the price in the list head order is correct");
			assert.equal(res.buy, true, "the head order in the long puts linked list is classified as a buy order")
			assert.equal(res.call, false, "the head order in the long puts linked list is classified as a put order")			
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+5000, "the price is correct in the second node in the linkedList");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "the price is correct in the third node in the linkedList");
			defaultAccountBalance += (price+10000)*amount;
			return exchangeInstance.cancelOrder(head);
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			assert.equal(res != head, true, "the of the list updates when the order is removed");
			head = res
			firstSellAmount = amount-4;
			receiverAccountPosition -= firstSellAmount;
			defaultAccountPosition += firstSellAmount;
			return exchangeInstance.marketSell(maturity, strike, 0, firstSellAmount, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-firstSellAmount, "the amount left in the list head has decreaced the correct amount");
			receiverAccountPosition -= amount+1;
			defaultAccountPosition += amount+1;
			return exchangeInstance.marketSell(maturity, strike, 0, amount+1, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			assert.equal(head != res, true, "head updates again");
			head = res;
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, amount-firstSellAmount-1, "the amount in the orders after three orders is still correct");
			receiverAccountBalance -= (amount+firstSellAmount+1)*strike*scUnits -(amount*(price+5000)+(1+firstSellAmount)*price);
			return exchangeInstance.claimedStable(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default account balance is correct");
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver account balance is correct");
			return optionsInstance.putAmounts(defaultAccount, maturity, strike);
		}).then((res) => {
			halfPutAmount = res.toNumber();
			return;
		});
	});

	it('can post and take sell orders of puts', function(){
		return exchangeInstance.claimedStable(defaultAccount).then((res) => {
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= strike*amount*scUnits;
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {
			defaultAccountBalance -= strike*amount*scUnits;
			return exchangeInstance.postOrder(maturity, strike, price-10000, amount, false, false, {from: defaultAccount});
		}).then(() => {
			defaultAccountBalance -= strike*amount*scUnits;
			return exchangeInstance.postOrder(maturity, strike, price-5000, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			head = res;
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
			assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
			assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
			assert.equal(res.price.toNumber(), price-10000, "the price in the list head order is correct");
			assert.equal(res.buy, false, "the head order in the long puts linked list is classified as a sell order");
			assert.equal(res.call, false, "the head order in the long puts linked list is classified as a put order");			
			defaultAccountBalance += strike*amount*scUnits;
			return exchangeInstance.cancelOrder(head, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			assert.equal(res, next, "the list head updates to the next node");
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			current = res.hash;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price-5000, "the new list head has the correct price");
			firstBuyAmount = amount-4;
			receiverAccountPosition += firstBuyAmount;
			defaultAccountPosition -= firstBuyAmount;
			return exchangeInstance.marketBuy(maturity, strike, price+100000, firstBuyAmount, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.offers(current);
		}).then((res)  => {
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount, "the amount has been decremented correctly");
			receiverAccountPosition += amount+1;
			defaultAccountPosition -= amount+1;
			return exchangeInstance.marketBuy(maturity, strike, price+100000, amount+1, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "the price of the last node order is correct");
			assert.equal(res.amount.toNumber(), amount-firstBuyAmount-1, "the amount has decremented correctly");
			//return exchangeInstance.cancelOrder(head, {from: defaultAccount})
			return optionsInstance.putAmounts(defaultAccount, maturity, strike);
		}).then((res) => {
			//aggregate impact of market orders on both accounts
			defaultAccountBalance += amount*(price-5000) + (firstBuyAmount+1)*price;
			receiverAccountBalance -= amount*(price-5000) + (firstBuyAmount+1)*price;
			return exchangeInstance.claimedStable(defaultAccount);
		}).then((res) => {
			defaultTotal = res.toNumber();
			return optionsInstance.claimedStable(defaultAccount);
		}).then((res) => {
			defaultTotal += res.toNumber();
			//add (halfPutAmount*strike*scUnits) to make up for the amount that was bought and then sold as we subtracted it out when puts were sold
			defaultAccountBalance += (halfPutAmount*strike*scUnits);
			assert.equal(defaultTotal, defaultAccountBalance, "defaultAccount has the correct balance");
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiverAccount has the correct balance");
		});
	});

	it('inserts orders', function(){
		altMaturity = maturity+5;
		return exchangeInstance.postOrder(altMaturity, strike, price, amount, true, true, {from: defaultAccount}).then(() => {
			return exchangeInstance.postOrder(altMaturity, strike, price+10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(altMaturity, strike, 0);
		}).then((res) => {
			prevHead = res;
			return exchangeInstance.insertOrder(altMaturity, strike, price+20000, amount, true, true, prevHead, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(altMaturity, strike, 0);
		}).then((res) => {
			assert.notEqual(res, prevHead);
			newHead = res;
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			thirdAddNode = res.next;
			assert.equal(thirdAddNode, prevHead, "The next node is the previous head node");
			assert.equal(res.previous, defaultBytes32, "The head node has no previous node");
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.maturity, altMaturity, "The head has the correct maturity");
			assert.equal(res.price, price+20000, "The price is correct");
			assert.equal(res.strike, strike, "the strike is correct");
			return exchangeInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.equal(res.previous, newHead, "The previous of the previous head has been updated");
			thirdAddNode = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price+10000, "The price of the second offer is correct");
			return exchangeInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.equal(res.next, defaultBytes32, "The last node in the list has no next node");
			assert.equal(res.previous, prevHead, "The previous of the last node is correct");
			return exchangeInstance.insertOrder(altMaturity, strike, price+5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.insertOrder(altMaturity, strike, price-5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		}).then(() => {
			//now the second to last node in the list
			return exchangeInstance.linkedNodes(thirdAddNode);
		}).then((res) => {
			assert.notEqual(res.previous, prevHead, "The previous of the last node has updated");
			assert.notEqual(res.next, defaultBytes32, "The next of the node has updated")
			frem = res.next;
			tilbake = res.previous;
			return exchangeInstance.linkedNodes(frem);
		}).then((res) => {
			assert.equal(res.next, defaultBytes32, "The next of the last node is null");
			assert.equal(res.previous, thirdAddNode, "The previous of the last node is correct");
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price-5000, "The price of the last node is correct");
			return exchangeInstance.linkedNodes(tilbake);
		}).then((res) => {
			assert.equal(res.next, thirdAddNode, "The next of the node is correct");
			assert.equal(res.previous, prevHead, "The precious of the node is correct");
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+5000, "The price of the node is correct");
			return;
		});
	});

	it('conducts limit orders', function(){
		otherMaturity = maturity*2;
		return exchangeInstance.postOrder(otherMaturity, strike, price, amount, true, true, {from: defaultAccount}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price+10000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price-5000, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketSell(otherMaturity, strike, price-5000, amount*5, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(otherMaturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price-10000, "the limit price stopped further selling at prices lower than the limit price");
			//now we will test the same for posting Sell orders and making market Buy orders
			return exchangeInstance.postOrder(otherMaturity, strike, price, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price+10000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(otherMaturity, strike, price-5000, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(otherMaturity, strike, price, amount*5, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.listHeads(otherMaturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price, price+10000, "the limit price stopped further buying at prices higher than the limit price");
		});
	});

	it('withdraws funds', function(){
		return exchangeInstance.claimedToken(defaultAccount).then((res) => {
			defTokens = res.toNumber();
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			recTokens = res.toNumber();
			return tokenInstance.addrBalance(defaultAccount, false);
		}).then((res) => {
			defBalance = res.toNumber();
			return tokenInstance.addrBalance(receiverAccount, false);
		}).then((res) => {
			recBalance = res.toNumber();
			return exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		}).then(() => {
			return tokenInstance.addrBalance(defaultAccount, false);
		}).then((res) => {
			assert.equal(res.toNumber(), defTokens+defBalance, "awarded correct amount");
			return tokenInstance.addrBalance(receiverAccount, false);
		}).then((res) => {
			assert.equal(res.toNumber(), recTokens+recBalance, "awarded correct amount");
			return exchangeInstance.claimedToken(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			return exchangeInstance.claimedToken(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			//now test for the same for stablecoin
			return exchangeInstance.claimedStable(defaultAccount);
		}).then((res) => {
			defStable = res.toNumber();
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			recStable = res.toNumber();
			return stablecoinInstance.addrBalance(defaultAccount, false);
		}).then((res) => {
			defBalance = res.toNumber();
			return stablecoinInstance.addrBalance(receiverAccount, false);
		}).then((res) => {
			recBalance = res.toNumber();
			return exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		}).then((res) => {
			return exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.addrBalance(defaultAccount, false);
		}).then((res) => {
			assert.equal(res.toNumber(), defStable+defBalance, "awarded correct amount");
			return stablecoinInstance.addrBalance(receiverAccount, false);
		}).then((res) => {
			assert.equal(res.toNumber(), recStable+recBalance, "awarded correct amount");
			return exchangeInstance.claimedStable(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			return exchangeInstance.claimedStable(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
		});
	});
});