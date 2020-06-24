var oracle = artifacts.require("./oracle.sol");
var underlyingAsset = artifacts.require("./UnderlyingAsset.sol");
var options = artifacts.require("./options.sol");
var exchange = artifacts.require("./exchange.sol");
var strikeAsset = artifacts.require("./strikeAsset.sol");

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
var strikeAssetInstance;
var exchangeInstance;
var defaultAccount;
var receiverAccount;
var defaultAccountBalance;
var receiverAccountBalance;
var strikes = {};
var mintHandler = {};

var defaultAccountPosition = 0;
var receiverAccountPosition = 0;

contract('exchange', async function(accounts) {

	it('before each', async () => {
		tokenInstance = await underlyingAsset.new(0);
		strikeAssetInstance = await strikeAsset.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address);
		mintHandler.postOrder = async (maturity, strike, price, amount, buy, call, params) => {
			if (typeof(strikes[maturity]) === 'undefined') strikes[maturity] = {};
			if (typeof(strikes[maturity][strike]) === 'undefined'){
				strikes[maturity][strike] = true;
				await addStrike(accounts[1], maturity, strike);
				await addStrike(accounts[2], maturity, strike);
			}
			return exchangeInstance.postOrder(maturity, strike, price, amount, buy, call, params);
		};

		mintHandler.insertOrder = async (maturity, strike, price, amount, buy, call, name, params) => {
			if (typeof(strikes[maturity]) === 'undefined') strikes[maturity] = {};
			if (typeof(strikes[maturity][strike]) === 'undefined'){
				strikes[maturity][strike] = true;
				await addStrike(accounts[1], maturity, strike);
				await addStrike(accounts[2], maturity, strike);
			}
			return exchangeInstance.insertOrder(maturity, strike, price, amount, buy, call, name, params);
		};
		exchangeInstance = await exchange.new(tokenInstance.address, strikeAssetInstance.address, optionsInstance.address);
		await optionsInstance.setExchangeAddress(exchangeInstance.address);
	});

	async function addStrike(from, maturity, strike) {
		strikes = await optionsInstance.viewStrikes(maturity, {from});
		var index = 0;
		for (;index < strikes.length; index++){ 
			if (strikes[index] == strike) return;
			if (strikes[index] > strike) break;
		}
		await optionsInstance.addStrike(maturity, strike, index, {from});
	}

	async function depositFunds(sats, sc, params) {
		await tokenInstance.transfer(exchangeInstance.address, sats, params);
		await strikeAssetInstance.transfer(exchangeInstance.address, sc, params);
		return exchangeInstance.depositFunds(params.from);
	}


	it('can post and take buy orders of calls', async () => {
		originAccount = accounts[0]
		defaultAccount = accounts[1];
		receiverAccount = accounts[2];
		satUnits = Math.pow(10, (await tokenInstance.decimals()).toNumber());
		scUnits = Math.pow(10, (await strikeAssetInstance.decimals()).toNumber());
		await tokenInstance.transfer(defaultAccount, 2100000*satUnits, {from: originAccount});
		await strikeAssetInstance.transfer(defaultAccount, 2100000*scUnits, {from: originAccount});
		await tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(receiverAccount, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		await depositFunds(10*transferAmount*satUnits, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		await depositFunds(10*transferAmount*satUnits, 10*transferAmount*strike*scUnits, {from: receiverAccount});
		res = (await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber();
		assert.equal(res, 10*satUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
		defaultAccountBalance = res;
		res = (await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber();
		assert.equal(res, 10*satUnits*transferAmount, "correct amount of collateral claimed for " + receiverAccount);
		receiverAccountBalance = res;
		defaultAccountBalance -= amount*price;
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 0));
		assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Buy order");
		assert.equal(res.maturity, maturity, "the maturity of the option contract is correct");
		assert.equal(res.strike, strike, "the strike of the option contract is correct");
		assert.equal(res.price, price, "the price of the option contract is correct");
		assert.equal(res.amount, amount, "the amount of the option contract is correct");
		defaultAccountBalance -= (price-10000)*amount;
		await mintHandler.postOrder(maturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		firstSellAmount = 5;
		receiverAccountPosition -= firstSellAmount;
		defaultAccountPosition += firstSellAmount;
		await exchangeInstance.marketSell(maturity, strike, 0, firstSellAmount, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 0);
		res = await exchangeInstance.linkedNodes(res);
		res = (await exchangeInstance.offers(res.hash)).amount.toNumber();
		assert.equal(res, firstSellAmount, "the amount of the contract has decreaced the correct amount");
		receiverAccountPosition -= amount-firstSellAmount+1;
		defaultAccountPosition += amount-firstSellAmount+1;
		await exchangeInstance.marketSell(maturity, strike, 0, amount-firstSellAmount+1, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 0);
		res = await exchangeInstance.linkedNodes(res);
		res = (await exchangeInstance.offers(res.hash)).amount.toNumber();
		assert.equal(res, amount-1, "amount of second order after marketSell is correct");
		receiverAccountPosition -= amount-1;
		defaultAccountPosition += amount-1;
		await exchangeInstance.marketSell(maturity, strike, 0, 2*amount-1, true, {from:receiverAccount});
		//we have not updated the receiverAccountBalance yet so we will aggregate the impact of all orders here
		receiverAccountBalance -= (satUnits*2*amount) - (amount*(2*price-10000));
		assert.equal(await exchangeInstance.listHeads(maturity, strike, 0), defaultBytes32, "after orderbook has been emptied there are no orders");
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 0));
		assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
		await exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		assert.equal(await exchangeInstance.listHeads(maturity, strike, 0), defaultBytes32, "the order cancellation has been recognized");
		//now we make sure the balances of each user are correct
		assert.equal((await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber(), defaultAccountBalance, "default Account balance is correct");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), receiverAccountBalance, "receiver Account balance is correct");
	});

	it('can post and take sell orders of calls', async () => {
		await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		await exchangeInstance.viewClaimed(true, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});			
		//await exchangeInstance.listHeads(maturity, strike, 1);
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Sell order");
		assert.equal(res.maturity.toNumber(), maturity, "the maturity of the option contract is correct");
		assert.equal(res.strike.toNumber(), strike, "the strike of the option contract is correct");
		assert.equal(res.price.toNumber(), price, "the price of the option contract is correct");
		assert.equal(res.amount.toNumber(), amount, "the amount of the option contract is correct");
		await mintHandler.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		firstBuyAmount = 5;
		await exchangeInstance.marketBuy(maturity, strike, price+100000, firstBuyAmount, true, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount.toNumber(), firstBuyAmount, "the amount of the contract has decreaced the correct amount");
		await exchangeInstance.marketBuy(maturity, strike, price+100000, amount-firstBuyAmount+1, true, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount, amount-1, "amount of second order after marketBuy is correct");
		await exchangeInstance.marketBuy(maturity, strike, price+100000, 2*amount-1, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 1);
		assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
		await exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 1);
		assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
		defaultTotal = (await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber();
		optRecTotal = (await optionsInstance.viewClaimedTokens({from: receiverAccount})).toNumber();
		assert.equal(defaultTotal, 10*transferAmount*satUnits, "defaultAccount has correct balance");
		recTotal = (await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber() + (await optionsInstance.viewClaimedTokens({from: receiverAccount})).toNumber();
		assert.equal(recTotal, 10*transferAmount*satUnits, "receiverAccount has the correct balance");
	});

	it('can post and take buy orders of puts', async () => {
		//price must be lower than strike
		strike = Math.floor(scUnits*0.7);
		price = strike - Math.floor(strike/2);
		defaultAccountBalance = (await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber();
		receiverAccountPosition = 0;
		defaultAccountPosition = 0;
		receiverAccountBalance = (await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber();
		defaultAccountBalance -= price*amount;
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		defaultAccountBalance -= (price+10000)*amount;
		await mintHandler.postOrder(maturity, strike, price+10000, amount, true, false, {from: defaultAccount})
		defaultAccountBalance -= (price+5000)*amount;
		await mintHandler.postOrder(maturity, strike, price+5000, amount, true, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 2);
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
		assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
		assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
		assert.equal(res.price.toNumber(), price+10000, "the price in the list head order is correct");
		assert.equal(res.index, 2, "the head order in the long puts linked list has the correct index");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+5000, "the price is correct in the second node in the linkedList");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price, "the price is correct in the third node in the linkedList");
		defaultAccountBalance += (price+10000)*amount;
		await exchangeInstance.cancelOrder(head, {from: defaultAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 2);
		assert.equal(res != head, true, "the of the list updates when the order is removed");
		head = res
		firstSellAmount = amount-4;
		receiverAccountPosition -= firstSellAmount;
		defaultAccountPosition += firstSellAmount;
		await exchangeInstance.marketSell(maturity, strike, 0, firstSellAmount, false, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(head)).hash);
		assert.equal(res.amount, amount-firstSellAmount, "the amount left in the list head has decreaced the correct amount");
		receiverAccountPosition -= amount+1;
		defaultAccountPosition += amount+1;
		await exchangeInstance.marketSell(maturity, strike, 0, amount+1, false, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 2);
		assert.equal(head != res, true, "head updates again");
		head = res;
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(head)).hash);
		assert.equal(res.amount, amount-firstSellAmount-1, "the amount in the orders after three orders is still correct");
		receiverAccountBalance -= (amount+firstSellAmount+1)*strike -(amount*(price+5000)+(1+firstSellAmount)*price);
		assert.equal((await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber(), defaultAccountBalance, "default account balance is correct");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), receiverAccountBalance, "receiver account balance is correct");
		halfPutAmount = (await optionsInstance.balanceOf(defaultAccount, maturity, strike, false)).toNumber();
	});

	it('can post and take sell orders of puts', async () => {
		defaultAccountBalance = (await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber();
		receiverAccountBalance = (await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber();
		defaultAccountBalance -= strike*amount - price*amount;
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		defaultAccountBalance -= strike*amount - (price-10000)*amount;
		await mintHandler.postOrder(maturity, strike, price-10000, amount, false, false, {from: defaultAccount});
		defaultAccountBalance -= strike*amount - (price-5000)*amount;
		await mintHandler.postOrder(maturity, strike, price-5000, amount, false, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 3);
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount.toNumber(), amount, "the amount in the list head order is correct");
		assert.equal(res.strike.toNumber(), strike, "the strike in the list head order is correct");
		assert.equal(res.maturity.toNumber(), maturity, "the maturity in the list head order is correct");
		assert.equal(res.price.toNumber(), price-10000, "the price in the list head order is correct");
		assert.equal(res.index, 3, "the head order in the short puts linked list has the correct index");
		defaultAccountBalance += strike*amount - (price-10000)*amount;
		await exchangeInstance.cancelOrder(head, {from: defaultAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 3);
		assert.equal(res, next, "the list head updates to the next node");
		res = await exchangeInstance.linkedNodes(res);
		next = res.next;
		current = res.hash;
		assert.equal((await exchangeInstance.offers(res.hash)).price, price-5000, "the new list head has the correct price");
		firstBuyAmount = amount-4;
		receiverAccountPosition += firstBuyAmount;
		defaultAccountPosition -= firstBuyAmount;
		await exchangeInstance.marketBuy(maturity, strike, price+100000, firstBuyAmount, false, {from: receiverAccount});
		assert.equal((await exchangeInstance.offers(current)).amount.toNumber(), amount-firstBuyAmount, "the amount has been decremented correctly");
		receiverAccountPosition += amount+1;
		defaultAccountPosition -= amount+1;
		await exchangeInstance.marketBuy(maturity, strike, price+100000, amount+1, false, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 3))).hash);
		assert.equal(res.price.toNumber(), price, "the price of the last node order is correct");
		assert.equal(res.amount.toNumber(), amount-firstBuyAmount-1, "the amount has decremented correctly");
		//aggregate impact of market on receiverAccount
		receiverAccountBalance -= amount*(price-5000) + (firstBuyAmount+1)*price;
		defaultTotal = (await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber() + (await optionsInstance.viewClaimedStable({from: defaultAccount})).toNumber();
		//add (halfPutAmount*strike) to make up for the amount that was bought and then sold as we subtracted it out when puts were sold
		defaultAccountBalance += (halfPutAmount*strike);
		assert.equal(defaultTotal, defaultAccountBalance, "defaultAccount has the correct balance");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), receiverAccountBalance, "receiverAccount has the correct balance");
	});

	it('inserts orders', async () => {
		altMaturity = maturity+5;
		await mintHandler.postOrder(altMaturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(altMaturity, strike, price+10000, amount, true, true, {from: defaultAccount});
		prevHead = await exchangeInstance.listHeads(altMaturity, strike, 0);
		await mintHandler.insertOrder(altMaturity, strike, price+20000, amount, true, true, prevHead, {from: defaultAccount});
		res = await exchangeInstance.listHeads(altMaturity, strike, 0);
		assert.notEqual(res, prevHead);
		newHead = res;
		res = await exchangeInstance.linkedNodes(res);
		thirdAddNode = res.next;
		assert.equal(thirdAddNode, prevHead, "The next node is the previous head node");
		assert.equal(res.previous, defaultBytes32, "The head node has no previous node");
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.maturity, altMaturity, "The head has the correct maturity");
		assert.equal(res.price, price+20000, "The price is correct");
		assert.equal(res.strike, strike, "the strike is correct");
		res = await exchangeInstance.linkedNodes(thirdAddNode);
		assert.equal(res.previous, newHead, "The previous of the previous head has been updated");
		thirdAddNode = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price, price+10000, "The price of the second offer is correct");
		res = await exchangeInstance.linkedNodes(thirdAddNode);
		assert.equal(res.next, defaultBytes32, "The last node in the list has no next node");
		assert.equal(res.previous, prevHead, "The previous of the last node is correct");
		await mintHandler.insertOrder(altMaturity, strike, price+5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		await mintHandler.insertOrder(altMaturity, strike, price-5000, amount, true, true, thirdAddNode, {from: defaultAccount});
		//now the second to last node in the list
		res = await exchangeInstance.linkedNodes(thirdAddNode);
		assert.notEqual(res.previous, prevHead, "The previous of the last node has updated");
		assert.notEqual(res.next, defaultBytes32, "The next of the node has updated")
		frem = res.next;
		tilbake = res.previous;
		res = await exchangeInstance.linkedNodes(frem);
		assert.equal(res.next, defaultBytes32, "The next of the last node is null");
		assert.equal(res.previous, thirdAddNode, "The previous of the last node is correct");
		assert.equal((await exchangeInstance.offers(res.hash)).price, price-5000, "The price of the last node is correct");
		res = await exchangeInstance.linkedNodes(tilbake);
		assert.equal(res.next, thirdAddNode, "The next of the node is correct");
		assert.equal(res.previous, prevHead, "The precious of the node is correct");
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+5000, "The price of the node is correct");
		//now test for put sells
		maturity += 1;
		await mintHandler.postOrder(altMaturity, strike, price, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(altMaturity, strike, price+10, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(altMaturity, strike, price+20, amount, false, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(altMaturity, strike, 3);
		await mintHandler.insertOrder(altMaturity, strike, price+15, amount, false, false, head, {from: defaultAccount});
		node = await exchangeInstance.linkedNodes(head);
		assert.equal((await exchangeInstance.offers(node.hash)).price.toNumber(), price, "correct Price first");		
		return mintHandler.insertOrder(altMaturity, strike, price+5, amount, false, false, (await exchangeInstance.linkedNodes(node.next)).next, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(altMaturity, strike, 3));
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price, "correct price on the first order in list");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+5, "correct price on the second order in list");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+10, "correct price on the third order in list");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+15, "correct price on the fourth order in list");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		name = res.name
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+20, "correct price on the fifth order in list");
		await mintHandler.insertOrder(altMaturity, strike, price+30, amount, false, false, name, {from: defaultAccount})
		res = await exchangeInstance.linkedNodes((await exchangeInstance.linkedNodes(name)).next);
		assert.equal((await exchangeInstance.offers(res.hash)).price.toNumber(), price+30, "correct price on the sixth order in list");
	});

	it('conducts limit orders', async () => {
		otherMaturity = maturity*2;
		await mintHandler.postOrder(otherMaturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price+10000, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-5000, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(otherMaturity, strike, price-5000, amount*5, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(otherMaturity, strike, 0);
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(otherMaturity, strike, 0))).hash);
		assert.equal(res.price, price-10000, "the limit price stopped further selling at prices lower than the limit price");
		//now we will test the same for posting Sell orders and making market Buy orders
		await mintHandler.postOrder(otherMaturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price+10000, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-5000, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(otherMaturity, strike, price, amount*5, true, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(otherMaturity, strike, 1))).hash);
		assert.equal(res.price, price+10000, "the limit price stopped further buying at prices higher than the limit price");
	});

	it('withdraws funds', async () => {
		defTokens = (await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber();
		recTokens = (await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber();
		defBalance = (await tokenInstance.balanceOf(defaultAccount)).toNumber();
		recBalance = (await tokenInstance.balanceOf(receiverAccount)).toNumber();
		await exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		assert.equal((await tokenInstance.balanceOf(defaultAccount)).toNumber(), defTokens+defBalance, "awarded correct amount");
		assert.equal((await tokenInstance.balanceOf(receiverAccount)).toNumber(), recTokens+recBalance, "awarded correct amount");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		//now test for the same for strike asset
		defStable = (await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber();
		recStable = (await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber();
		defBalance = (await strikeAssetInstance.balanceOf(defaultAccount)).toNumber();
		recBalance = (await strikeAssetInstance.balanceOf(receiverAccount)).toNumber();
		await exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		assert.equal((await strikeAssetInstance.balanceOf(defaultAccount)).toNumber(), defStable+defBalance, "awarded correct amount");
		assert.equal((await strikeAssetInstance.balanceOf(receiverAccount)).toNumber(), recStable+recBalance, "awarded correct amount");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		//now witdraw all funds from options smart contract for tidyness
		await optionsInstance.withdrawFunds({from: receiverAccount});
	});

	it('does not require excessive amount of collateral for calls', async () => {
		newMaturity = 2*maturity;
		strike = 100;
		await tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount});
		await tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: defaultAccount});
		await tokenInstance.approve(exchangeInstance.address, 10*transferAmount*satUnits, {from: receiverAccount});
		await strikeAssetInstance.transfer(receiverAccount, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		await strikeAssetInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: defaultAccount});
		await strikeAssetInstance.approve(exchangeInstance.address, 10*transferAmount*strike*scUnits, {from: receiverAccount});
		//------------------------------------------------------test with calls-------------------------------------
		await depositFunds(price*amount + 1, 0, {from: defaultAccount});
		await depositFunds(amount*satUnits, 0, {from: receiverAccount});
		//Test market sells
		//fist defaultAccount buys from receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(newMaturity, strike, 0, amount, true, {from: receiverAccount});
		//price/satUnits == (strike-secondStrike)/strike
		//secondStrike == strike - price*strike/sattUnits
		secondStrike = strike - Math.floor(price*strike/satUnits);
		//second defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, secondStrike, price, amount, true, true, {from: receiverAccount});
		await exchangeInstance.marketSell(newMaturity, secondStrike, 0, amount, true, {from: defaultAccount});
		//default account has funds in exchange contract while receiver account has funds in the options smart contract
		await exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		//Test market buys
		/*
			note that we need to deposit more collateral here because to post an order it must be fully collateralised
		*/
		await depositFunds(amount*(price+satUnits), 0, {from: defaultAccount});
		await depositFunds(amount*(price+satUnits), 0, {from: receiverAccount});
		//fist defaultAccount sells to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, true, {from: receiverAccount});
		//second defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, true, {from: receiverAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, true, {from: defaultAccount});
	});

	it('does not require excessive amount of collateral for puts', async () => {
		//----------------------------------------------test with puts--------------------------------------------
		price = strike - 1;
		await depositFunds(0, price*amount, {from: defaultAccount});
		await depositFunds(0, amount*strike*scUnits, {from: receiverAccount});
		//Test market sell
		//fist defaultAccount buys from receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(newMaturity, strike, 0, amount, false, {from: receiverAccount});
		//price/scunits == secondStrike-strike
		//(price+strike*scUnits)/scUnits == secondStrike
		secondStrike = Math.floor((price+strike*scUnits)/scUnits); 
		//next defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, secondStrike, price, amount, true, false, {from: receiverAccount});
		await exchangeInstance.marketSell(newMaturity, secondStrike, 0, amount, false, {from: defaultAccount});
		//default account has funds in exchange contract while receiver account has funds in the options smart contract
		await exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		//Test market buy
		/*
			note that we need to deposit more collateral here because to post an order it must be fully collateralised
		*/
		await depositFunds(0, amount*(price+scUnits*strike), {from: defaultAccount});
		await depositFunds(0, amount*(price+scUnits*strike), {from: receiverAccount});
		//fist defaultAccount sells to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, false, {from: receiverAccount});	
		//second defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, false, {from: receiverAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, false, {from: defaultAccount});
	});

	it('prioritises older orders', async () => {
		strike = 3;
		price = Math.floor(satUnits*0.05);
		await tokenInstance.transfer(receiverAccount, 10*transferAmount*satUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(receiverAccount, strike*10*transferAmount*satUnits, {from: defaultAccount});

		satBal = (await tokenInstance.balanceOf(defaultAccount)).toNumber();
		scBal = (await strikeAssetInstance.balanceOf(defaultAccount)).toNumber();
		await depositFunds(satBal, scBal, {from: defaultAccount});
		satBal = (await tokenInstance.balanceOf(receiverAccount)).toNumber();
		scBal = (await strikeAssetInstance.balanceOf(receiverAccount)).toNumber();
		await depositFunds(satBal, scBal, {from: receiverAccount});
		//test for index 0 calls buys
		await mintHandler.postOrder(maturity, strike, price, 1, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, true, true, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 0);
		await mintHandler.insertOrder(maturity, strike, price, 3, true, true, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 1, "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 2, "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount, 3, "last account is correct");
		//test for index 1 calls sells
		await mintHandler.postOrder(maturity, strike, price, 1, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, false, true, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 1);
		await mintHandler.insertOrder(maturity, strike, price, 3, false, true, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 1, "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 2, "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount, 3, "last account is correct");
		//test for index 2 puts buys
		//strike must be greater than price
		price = Math.floor(strike/2);
		await mintHandler.postOrder(maturity, strike, price, 1, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, true, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 2);
		await mintHandler.insertOrder(maturity, strike, price, 3, true, false, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 1, "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 2, "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount, 3, "last account is correct");
		//test for index 3 puts sells
		await mintHandler.postOrder(maturity, strike, price, 1, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, false, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 3);
		headNode = await exchangeInstance.linkedNodes(head);
		next = headNode.next;
		await mintHandler.insertOrder(maturity, strike, price, 3, false, false, next, {from: receiverAccount});
		assert.equal((await exchangeInstance.offers(headNode.hash)).amount, 1, "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount, 2, "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount, 3, "last account is correct");
	});

	it('allow users to accept their own orders', async () => {
		maturity +=1;
		price = Math.floor(satUnits*0.9);
		//test taking long call offers
		balance = await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amount-4, true, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		assert.equal(balance-res, price*4, "executes trades with self in marketSell of calls");
		balance = res
		await exchangeInstance.marketSell(maturity, strike, price, amount, true, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		assert.equal(res-balance, price*4, "executes trades with self in takeSellOffer of calls");
		balance = res;
		//test taking short call offers
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amount-4, true, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		assert.equal(balance-res, 4*(satUnits-price), "executes tades with self in marketBuy of calls");
		balance = res;
		await exchangeInstance.marketBuy(maturity, strike, price, amount, true, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(true, {from: defaultAccount});
		assert.equal(res-balance, 4*(satUnits-price), "executes  trades with self in takeBuyOffer of calls");
		res = await exchangeInstance.viewClaimed(false, {from: defaultAccount});
		balance = res;
		//for puts strike must be greater than price
		price = Math.floor(0.9*strike);
		//test taking long put offers
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amount-4, false, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(false, {from: defaultAccount});
		assert.equal(balance-res, price*4, "executes trades with self in marketSell of puts");
		balance = res;
		await exchangeInstance.marketSell(maturity, strike, price, amount, false, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(false, {from: defaultAccount});			
		assert.equal(res-balance, price*4, "executes trades with self in takeSellOffer of puts");
		balance = res;
		//test taking short put offers
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amount-4, false, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(false, {from: defaultAccount});
		assert.equal(balance-res, 4*(strike-price), "executes trades with self in marketBuy of puts");
		balance = res;
		await exchangeInstance.marketBuy(maturity, strike, price, amount, false, {from: defaultAccount});
		res = await exchangeInstance.viewClaimed(false, {from: defaultAccount});			
		assert.equal(res-balance, 4*(strike-price), "executes trades with self in takeBuyOffer of puts");
	});

	it('requires strike to be added before placing order', async () => {
		//please note the number I compare to below is likely an over estimate of the requirements for this test
		assert.equal((await exchangeInstance.viewClaimed(true, {from: defaultAccount})).toNumber() > amount*satUnits*4, true, "balance is great enough to do this test");
		//please note the number I compare to below is liely an over estimate of the requirements for this test
		assert.equal((await exchangeInstance.viewClaimed(false, {from: defaultAccount})).toNumber() > amount*scUnits*strike*4, true, "balance is great enough to do this test");
		//please note the number I compare to below is liely an over estimate of the requirements for this test
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber() > amount*satUnits*4, true, "balance is great enough to do this test");
		return exchangeInstance.viewClaimed(false, {from: receiverAccount}).then((res) => {
			//please note the number I compare to below is liely an over estimate of the requirements for this test
			assert.equal(res.toNumber() > amount*scUnits*strike*4, true, "balance is great enough to do this test");
		}).catch(() => {
			throw Error("missed checkpoint");
		}).then(() => {
			//get new maturity strike combo
			maturity += 1;
			//attempt to place orders and insert them without adding maturity strike maturity combo with options smart contract
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(() => {
			return "OK";
		}).catch((err) => {
			if (err.message === "missed checkpoint") throw err;
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "can't postOrder without first adding maturity strike combo on options smart contract");
			return addStrike(defaultAccount, maturity, strike);
		}).then(() => {
			return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		}).then(async () => {
			name = await exchangeInstance.listHeads(maturity, strike, 0);
			//attempt to add insertOrder with account that has not added maturity strike combo
			return exchangeInstance.insertOrder(maturity, strike, price, amount, true, true, name, {from: receiverAccount});
		}).then(() => {
			return "OK";
		}).catch((err) => {
			if (err.message === "missed checkpoint") throw err;
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "can't insertOrder without first adding maturity strike combo on options smart contract");
			//attempt to marketSell without adding maturity strike combo
			return exchangeInstance.marketSell(maturity, strike, price, amount, true, {from: receiverAccount});
		}).then(() => {
			return "OK";
		}).catch((err) => {
			if (err.message === "missed checkpoint") throw err;
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "can't marketSell without first adding maturity strike combo on options smart contract");
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(maturity, strike, price, amount, false, {from: receiverAccount});
		}).then((rec) => {
			return optionsInstance.viewStrikes(maturity, {from: receiverAccount});
		}).then((res) => {
			return "OK";
		}).catch((err) => {
			if (err.message === "missed checkpoint") throw err;
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "can't marketBuy without first adding maturity strike combo on options smart contract");
		});
	});

	it('fills all possible orders in exchange with posted order index 0', async () => {
		maturity++;
		strike = 5;
		amount = 3;
		//send ample amount of funds for defaultAccount
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		await tokenInstance.transfer(defaultAccount, (await tokenInstance.balanceOf(originAccount)).toNumber(), {from: originAccount});
		//because of 53 bit limit we cannot get strike asset balance of origin account
		await strikeAssetInstance.transfer(defaultAccount, 100*strike*amount*satUnits, {from: originAccount});
		await depositFunds(10*amount*satUnits, 10*amount*strike*scUnits, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds((2*amount-1)*(satUnits-price), 0, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		//should not revert
		await exchangeInstance.marketSell(maturity, strike, price, 2*amount, true, {from: receiverAccount});
		//correct amount of orders left
		var headName = await exchangeInstance.listHeads(maturity, strike, 0);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 1, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
		//now try setting amount to less than the amount in the market order to less than the amount in the second order so that this acceptBuyOffer is only called once
		//we expect the second order in the linked list to not be affected
		await depositFunds(amount*(satUnits-price), 0, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, 2*amount-1, true, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 0);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), amount, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

	it('fills all possible orders in exchange with posted order index 1', async () => {
		maturity++;

		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds((2*amount-1)*price, 0, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		//should not revert
		await exchangeInstance.marketBuy(maturity, strike, price, 2*amount, true, {from: receiverAccount});
		//correct amount of orders left
		var headName = await exchangeInstance.listHeads(maturity, strike, 1);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 1, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(amount*price, 0, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, 2*amount-1, true, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 1);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), amount, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(true, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

	it('fills all possible orders in exchange with posted order index 2', async () => {
		maturity++;
		strike = 5;
		//price must be lower than strike
		price = strike-2;
		//send ample amount of funds for defaultAccount
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		await strikeAssetInstance.transfer(receiverAccount, 100*strike*amount*scUnits, {from: originAccount});

		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds(0, (2*amount-1)*(strike-price), {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		await exchangeInstance.marketSell(maturity, strike, price, 2*amount, false, {from: receiverAccount});
		var headName = await exchangeInstance.listHeads(maturity, strike, 2);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 1, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(0, amount*(strike-price), {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, 2*amount-1, false, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 2);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), amount, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});


	it('fills all possible orders in exchange with posted order index 3', async () => {
		maturity++;
		strike = 5;
		//price must be lower than strike
		price = strike-2;

		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds(0, (2*amount-1)*price, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		await exchangeInstance.marketBuy(maturity, strike, price, 2*amount, false, {from: receiverAccount});
		var headName = await exchangeInstance.listHeads(maturity, strike, 3);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 1, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(0, amount*price, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, 2*amount-1, false, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 3);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), amount, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await exchangeInstance.viewClaimed(false, {from: receiverAccount})).toNumber(), 0, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

});