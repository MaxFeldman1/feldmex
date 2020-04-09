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
var feeDenominator = 5000;
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

	it('before each', async() => {
		return oracle.new().then((i) => {
			oracleInstance = i;
			return dappToken.new(0);
		}).then((i) => {
			tokenInstance = i;
			return stablecoin.new(0);
		}).then((i) => {
			stablecoinInstance = i;
			return options.new(oracleInstance.address, tokenInstance.address, stablecoinInstance.address);
		}).then((i) => {
			optionsInstance = i;
			return exchange.new(tokenInstance.address, stablecoinInstance.address, optionsInstance.address);
		}).then((i) => {
			exchangeInstance = i;
			return optionsInstance.setExchangeAddress(exchangeInstance.address);
		});
	});

	it('can post and take buy orders of calls', function(){
		originAccount = accounts[0]
		defaultAccount = accounts[1];
		receiverAccount = accounts[2];
		return tokenInstance.satUnits().then((res) => {
			satUnits = res.toNumber();
			return stablecoinInstance.scUnits();
		}).catch((err) => {
			console.log("Hei du tar feil på linje sektien");
			console.log(err.message);
			assert.equal(false, true, "sektien");
		}).then((res) => {
			scUnits = res.toNumber();
			return tokenInstance.transfer(defaultAccount, 21000000*satUnits, {from: originAccount});
		}).catch((err) => {
			console.log("Hei du tar feil på linje sektiåtte");
			console.log(err.message);
			console.log("Toekn address "+tokenInstance.address);
			assert.equal(false, true, "sektiåtte");
		}).then(() => {
			return stablecoinInstance.transfer(defaultAccount, 21000000*scUnits, {from: originAccount});
		}).catch((err) => {
			console.log("Hei du tar feil på linje syttitre");
			console.log(err.message);
			assert.equal(false, true, "syttitre");
		}).then(() => {
			return tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: defaultAccount});
		}).then((res) => {
			return tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: receiverAccount});
		}).then((res) => {
			return stablecoinInstance.transfer(receiverAccount, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(10*transferAmount*satUnits, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(10*transferAmount*satUnits, 10*transferAmount*strike*scUnits, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.viewClaimed(true, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 10*satUnits*transferAmount, "correct amount of collateral claimed for " + receiverAccount);
			receiverAccountBalance = res.toNumber();
			defaultAccountBalance -= amount*price;
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
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
			//account for the fees
			fee = Math.floor((firstSellAmount*price)/feeDenominator) + Math.floor(((amount-firstSellAmount)*price)/feeDenominator)
				+ Math.floor((price-10000)/feeDenominator) + Math.floor((amount-1)*(price-10000)/feeDenominator);
			receiverAccountBalance-=fee;
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
			return exchangeInstance.viewClaimed(true, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default Account balance is correct");
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver Account balance is correct");
			return;
		});
	});

	it('can post and take sell orders of calls', function(){
		return exchangeInstance.viewClaimed(true, {from: defaultAccount}).then((res) => {
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});			
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
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
			return exchangeInstance.viewClaimed(true, {from: defaultAccount});
		}).then((res) => {
			defaultTotal = res.toNumber();
			return optionsInstance.viewClaimedTokens({from: receiverAccount});
		}).then((res) => {
			optRecTotal = res.toNumber();
			assert.equal(defaultTotal, 10*transferAmount*satUnits - fee, "defaultAccount has correct balance");
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			recTotal = res.toNumber();
			return optionsInstance.viewClaimedTokens({from: receiverAccount});
		}).then((res) => {
			recTotal += res.toNumber();			
			assert.equal(recTotal, 10*transferAmount*satUnits - fee, "recieverAccount has the correct balance");
			return;
		});
	});

	it('can post and take buy orders of puts', function(){
		return exchangeInstance.viewClaimed(false, {from: defaultAccount}).then((res) => {
			receiverAccountPosition = 0;
			defaultAccountPosition = 0;
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
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
			return exchangeInstance.cancelOrder(head, {from: defaultAccount});
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
			//account for fees
			fee = Math.floor((6*(price+5000))/feeDenominator)+Math.floor((4*(price+5000))/feeDenominator)+Math.floor(7*price/feeDenominator);
			receiverAccountBalance -= fee;
			return exchangeInstance.viewClaimed(false, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), defaultAccountBalance, "default account balance is correct");
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiver account balance is correct");
			return optionsInstance.balanceOf(defaultAccount, maturity, strike, false);
		}).then((res) => {
			halfPutAmount = res.toNumber();
			return;
		});
	});

	it('can post and take sell orders of puts', function(){
		return exchangeInstance.viewClaimed(false, {from: defaultAccount}).then((res) => {
			defaultAccountBalance = res.toNumber();
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
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
			return optionsInstance.balanceOf(defaultAccount, maturity, strike, false);
		}).then((res) => {
			//aggregate impact of market orders on both accounts
			defaultAccountBalance += amount*(price-5000) + (firstBuyAmount+1)*price;
			receiverAccountBalance -= amount*(price-5000) + (firstBuyAmount+1)*price;
			return exchangeInstance.viewClaimed(false, {from: defaultAccount});
		}).then((res) => {
			defaultTotal = res.toNumber();
			return optionsInstance.viewClaimedStable({from: defaultAccount});
		}).then((res) => {
			defaultTotal += res.toNumber();
			fee = Math.floor((6*(price-5000))/feeDenominator)+Math.floor((4*(price-5000))/feeDenominator)+Math.floor(7*price/feeDenominator);
			//add (halfPutAmount*strike*scUnits) to make up for the amount that was bought and then sold as we subtracted it out when puts were sold
			defaultAccountBalance += (halfPutAmount*strike*scUnits) - fee;
			assert.equal(defaultTotal, defaultAccountBalance, "defaultAccount has the correct balance");
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), receiverAccountBalance, "receiverAccount has the correct balance");
		});
	});

	it('inserts orders', function(){
		altMaturity = maturity+5;
		//we start wtith call buys
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
			//now test for put sells
			strike = 1;
			return exchangeInstance.postOrder(altMaturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(altMaturity, strike, price+10, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(altMaturity, strike, price+20, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(altMaturity, strike, 3);
		}).then((res) => {
			head = res;
			return exchangeInstance.insertOrder(altMaturity, strike, price+15, amount, false, false, head, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			node = res
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "correct Price first");		
			return exchangeInstance.linkedNodes(node.next);
		}).then((res) => {
			return exchangeInstance.insertOrder(altMaturity, strike, price+5, amount, false, false, res.next, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(altMaturity, strike, 3);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price, "correct price on the first order in list");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+5, "correct price on the second order in list");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+10, "correct price on the third order in list");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+15, "correct price on the fourth order in list");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			name = res.name
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+20, "correct price on the fifth order in list");
			return exchangeInstance.insertOrder(altMaturity, strike, price+30, amount, false, false, name, {from: defaultAccount})
		}).then(() => {
			return exchangeInstance.linkedNodes(name);
		}).then((res) => {
			return exchangeInstance.linkedNodes(res.next);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.price.toNumber(), price+30, "correct price on the sixth order in list");
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
		return exchangeInstance.viewClaimed(true, {from: defaultAccount}).then((res) => {
			defTokens = res.toNumber();
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			recTokens = res.toNumber();
			return tokenInstance.balanceOf(defaultAccount);
		}).then((res) => {
			defBalance = res.toNumber();
			return tokenInstance.balanceOf(receiverAccount);
		}).then((res) => {
			recBalance = res.toNumber();
			return exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		}).then(() => {
			return tokenInstance.balanceOf(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defTokens+defBalance, "awarded correct amount");
			return tokenInstance.balanceOf(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), recTokens+recBalance, "awarded correct amount");
			return exchangeInstance.viewClaimed(true, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			return exchangeInstance.viewClaimed(true, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			//now test for the same for stablecoin
			return exchangeInstance.viewClaimed(false, {from: defaultAccount});
		}).then((res) => {
			defStable = res.toNumber();
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
		}).then((res) => {
			recStable = res.toNumber();
			return stablecoinInstance.balanceOf(defaultAccount);
		}).then((res) => {
			defBalance = res.toNumber();
			return stablecoinInstance.balanceOf(receiverAccount);
		}).then((res) => {
			recBalance = res.toNumber();
			return exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		}).then((res) => {
			return exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.balanceOf(defaultAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), defStable+defBalance, "awarded correct amount");
			return stablecoinInstance.balanceOf(receiverAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), recStable+recBalance, "awarded correct amount");
			return exchangeInstance.viewClaimed(false, {from: defaultAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			return exchangeInstance.viewClaimed(false, {from: receiverAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "funds correctly deducted when withdrawing funds");
			//now witdraw all funds from options smart contract for tidyness
			return optionsInstance.withdrawFunds({from: receiverAccount});
		});
	});

	it('does not require excessive amount of collateral for calls', function(){
		newMaturity = 2*maturity;
		return tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount}).then(() => {
			return tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.transfer(receiverAccount, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: receiverAccount});
		}).then(() => {
		//------------------------------------------------------test with calls-------------------------------------
			return exchangeInstance.depositFunds(price*amount, 0, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(amount*satUnits + Math.floor(price*amount/feeDenominator), 0, {from: receiverAccount});
		}).then(() => {
			//fist defaultAccount buys from receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketSell(newMaturity, strike, 0, amount, true, {from: receiverAccount});
		}).then(() => {		
			//second defaultAccount sells back to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, true, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.marketSell(newMaturity, strike, 0, amount, true, {from: defaultAccount});
		}).then(() => {
			//default account has funds in exchange contract while receiver account has funds in the options smart contract
			return exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.withdrawFunds({from: receiverAccount});
		}).then(() => {
			/*
				note that we need to deposit more collateral here because to post an order it must be fully collateralised
			*/
			return exchangeInstance.depositFunds(amount*(price+satUnits), 0, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(amount*(price+satUnits), 0, {from: receiverAccount});
		}).then(() => {
			//fist defaultAccount sells to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, true, {from: receiverAccount});
		}).then(() => {		
			//second defaultAccount sells back to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, false, true, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, true, {from: defaultAccount});
		});
	});

	it('does not require excessive amount of collateral for puts', function(){
		//----------------------------------------------test with puts--------------------------------------------
		return exchangeInstance.depositFunds(0, price*amount, {from: defaultAccount}).then(() => {
			return exchangeInstance.depositFunds(0, amount*strike*scUnits + Math.floor(price*amount/feeDenominator), {from: receiverAccount});
		}).then(() => {
			//fist defaultAccount buys from receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, true, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketSell(newMaturity, strike, 0, amount, false, {from: receiverAccount});
		}).then(() => {		
			//second defaultAccount sells back to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, true, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.marketSell(newMaturity, strike, 0, amount, false, {from: defaultAccount});
		}).then(() => {
			//default account has funds in exchange contract while receiver account has funds in the options smart contract
			return exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		}).then(() => {
			return optionsInstance.withdrawFunds({from: receiverAccount});
		}).then(() => {
			/*
				note that we need to deposit more collateral here because to post an order it must be fully collateralised
			*/
			return exchangeInstance.depositFunds(0, amount*(price+scUnits*strike), {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(0, amount*(price+scUnits*strike), {from: receiverAccount});
		}).then(() => {
			//fist defaultAccount sells to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, false, {from: receiverAccount});
		}).then(() => {		
			//second defaultAccount sells back to receiver account
			return exchangeInstance.postOrder(newMaturity, strike, price, amount, false, false, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, false, {from: defaultAccount});
		});
	});

	it ('changes the fee', function(){
		deployer = originAccount;
		nonDeployer = defaultAccount;
		return exchangeInstance.setFee(1000, {from: deployer}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OK", "Successfully changed the fee");
			return exchangeInstance.setFee(400, {from: deployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because fee was too high");
			return exchangeInstance.setFee(800, {from: nonDeployer});
		}).then(() => {
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because the sender was not the deployer");
		});
	});

	it('prioritises older orders', function(){
		strike = 3;
		return tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount}).then(() => {
			return stablecoinInstance.transfer(receiverAccount, strike*10*transferAmount*satUnits, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.balanceOf(defaultAccount);
		}).then((res) => {
			satBal = res.toNumber();
			return stablecoinInstance.balanceOf(defaultAccount);
		}).then((res) => {
			scBal = res.toNumber();
			return tokenInstance.approve(exchangeInstance.address, satBal, {from: defaultAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, scBal, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.depositFunds(satBal, scBal, {from: defaultAccount});
		}).then(() => {
			return tokenInstance.balanceOf(receiverAccount);
		}).then((res) => {
			satBal = res.toNumber();
			return stablecoinInstance.balanceOf(receiverAccount);
		}).then((res) => {
			scBal = res.toNumber();
			return tokenInstance.approve(exchangeInstance.address, satBal, {from: receiverAccount});
		}).then(() => {
			return stablecoinInstance.approve(exchangeInstance.address, scBal, {from: receiverAccount});
		}).then((res) => {
			return exchangeInstance.depositFunds(satBal, scBal, {from: receiverAccount});
		}).then(() => {
			//test for index 0 calls buys
			return exchangeInstance.postOrder(maturity, strike, price, 1, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(maturity, strike, price, 2, true, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 0);
		}).then((res) => {
			head = res
			return exchangeInstance.insertOrder(maturity, strike, price, 3, true, true, head, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 1, "the first account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 2, "the second account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 3, "last account is correct");
			//test for index 1 calls sells
			return exchangeInstance.postOrder(maturity, strike, price, 1, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(maturity, strike, price, 2, false, true, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 1);
		}).then((res) => {
			head = res
			return exchangeInstance.insertOrder(maturity, strike, price, 3, false, true, head, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 1, "the first account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 2, "the second account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 3, "last account is correct");
			//test for index 2 puts buys
			return exchangeInstance.postOrder(maturity, strike, price, 1, true, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(maturity, strike, price, 2, true, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 2);
		}).then((res) => {
			head = res
			return exchangeInstance.insertOrder(maturity, strike, price, 3, true, false, head, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 1, "the first account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 2, "the second account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 3, "last account is correct");
			//test for index 3 puts sells
			return exchangeInstance.postOrder(maturity, strike, price, 1, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.postOrder(maturity, strike, price, 2, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.listHeads(maturity, strike, 3);
		}).then((res) => {
			head = res
			return exchangeInstance.linkedNodes(head);
		}).then((res) => {
			next = res.next;
			headNode = res;
			return exchangeInstance.insertOrder(maturity, strike, price, 3, false, false, next, {from: receiverAccount});
		}).then(() => {
			return exchangeInstance.offers(headNode.hash);
		}).then((res) => {
			assert.equal(res.amount, 1, "the first account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			next = res.next;
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 2, "the second account is correct");
			return exchangeInstance.linkedNodes(next);
		}).then((res) => {
			return exchangeInstance.offers(res.hash);
		}).then((res) => {
			assert.equal(res.amount, 3, "last account is correct");
		});
	});
});