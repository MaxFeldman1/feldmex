const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const mOrganizer = artifacts.require("mOrganizer");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const mLegHelper = artifacts.require("mLegHelper");
const mLegDelegate = artifacts.require("mLegDelegate");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");

const BN = web3.utils.BN;
const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';

var maturity = 100;
var price = 177777;
var strike = 100;
var amount = 10;
var transferAmount = 1000;
var maxIterations = 5;
var underlyingAssetSubUnits;
var strikeAssetSubUnits;
var underlyingAssetSubUnitsBN;
var strikeAssetSubUnitsBN;
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
		tokenInstance = await token.new(0);
		strikeAssetInstance = await token.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		mCallHelperInstance = await mCallHelper.new(feeOracleInstance.address);
		mPutHelperInstance = await mPutHelper.new(feeOracleInstance.address);
		mLegDelegateInstance = await mLegDelegate.new();
		mLegHelperInstance = await mLegHelper.new(mLegDelegateInstance.address, feeOracleInstance.address);
		mOrganizerInstance = await mOrganizer.new(mCallHelperInstance.address, mPutHelperInstance.address, mLegHelperInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
		exchangeInstance = await exchange.new(tokenInstance.address, strikeAssetInstance.address, optionsInstance.address, feeOracleInstance.address);
		await optionsInstance.setExchangeAddress(exchangeInstance.address);

		underlyingAssetSubUnitsBN = (new BN("10")).pow(await tokenInstance.decimals());
		underlyingAssetSubUnits = Math.pow(10, (await tokenInstance.decimals()).toNumber());
		strikeAssetSubUnitsBN = (new BN("10")).pow(await strikeAssetInstance.decimals());
		strikeAssetSubUnits = Math.pow(10, (await strikeAssetInstance.decimals()).toNumber());
		amtBN = (new BN(amount)).mul(underlyingAssetSubUnitsBN);
		amt = amtBN.toString();
		originAccount = accounts[0]
		defaultAccount = accounts[1];
		receiverAccount = accounts[2];

		mintHandler.postOrder = async (maturity, strike, price, amount, buy, call, params) => {
			if (typeof(strikes[maturity]) === 'undefined') strikes[maturity] = {};
			if (typeof(strikes[maturity][strike]) === 'undefined'){
				strikes[maturity][strike] = true;
				await addStrike(accounts[1], maturity, strike);
				await addStrike(accounts[2], maturity, strike);
			}
			amount = (new BN(amount)).mul(call ? underlyingAssetSubUnitsBN : strikeAssetSubUnitsBN).toString();
			var balance = new web3.utils.BN(await web3.eth.getBalance(params.from));
			if (typeof params.gasPrice === "undefined") params.gasPrice = 20000000000; //20 gwei
			var postOrderFee = new web3.utils.BN(await feeOracleInstance.exchangeFlatEtherFee());
			params.value = postOrderFee.toNumber();
			var rec = await exchangeInstance.postOrder(maturity, strike, price, amount, buy, call, params);
			var txFee = new web3.utils.BN(rec.receipt.gasUsed * params.gasPrice);
			var newBalance = new web3.utils.BN(await web3.eth.getBalance(params.from));
			var result = txFee.add(newBalance);
			assert.equal(result.cmp(balance.sub(postOrderFee)), 0, "correct fees paid");
		};

		mintHandler.insertOrder = async (maturity, strike, price, amount, buy, call, name, params) => {
			if (typeof(strikes[maturity]) === 'undefined') strikes[maturity] = {};
			if (typeof(strikes[maturity][strike]) === 'undefined'){
				strikes[maturity][strike] = true;
				await addStrike(accounts[1], maturity, strike);
				await addStrike(accounts[2], maturity, strike);
			}
			amount = (new BN(amount)).mul(call ? underlyingAssetSubUnitsBN : strikeAssetSubUnitsBN).toString();
			var balance = new web3.utils.BN(await web3.eth.getBalance(params.from));
			if (typeof params.gasPrice === "undefined") params.gasPrice = 20000000000; //20 gwei
			var postOrderFee = new web3.utils.BN(await feeOracleInstance.exchangeFlatEtherFee());
			params.value = postOrderFee.toNumber();
			var rec = await exchangeInstance.insertOrder(maturity, strike, price, amount, buy, call, name, params);
			var txFee = new web3.utils.BN(rec.receipt.gasUsed * params.gasPrice);
			var newBalance = new web3.utils.BN(await web3.eth.getBalance(params.from));
			var result = txFee.add(newBalance);
			assert.equal(result.cmp(balance.sub(postOrderFee)), 0, "correct fees paid");
		};
	});

	async function addStrike(addr, maturity, strike) {
		strikes = await optionsInstance.viewStrikes(addr, maturity);
		var index = 0;
		for (;index < strikes.length; index++){ 
			if (strikes[index] == strike) return;
			if (strikes[index] > strike) break;
		}
		await optionsInstance.addStrike(maturity, strike, index, {from: addr});
	}

	async function depositFunds(underlyingAssetAmt, strikeAssetAmt, exchange, params) {
		await tokenInstance.transfer(exchange ? exchangeInstance.address : optionsInstance.address, underlyingAssetAmt, {from: accounts[0]});
		await strikeAssetInstance.transfer(exchange ? exchangeInstance.address : optionsInstance.address, strikeAssetAmt, {from: accounts[0]});
		if (exchange)
			return exchangeInstance.depositFunds(params.from);
		else
			return optionsInstance.depositFunds(params.from);
	}


	it('can post and take buy orders of calls', async () => {
		await tokenInstance.transfer(defaultAccount, 2100000*underlyingAssetSubUnits, {from: originAccount});
		await strikeAssetInstance.transfer(defaultAccount, 2100000*strikeAssetSubUnits, {from: originAccount});
		await tokenInstance.transfer(receiverAccount, 10*transferAmount*underlyingAssetSubUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(receiverAccount, 10*transferAmount*strike*strikeAssetSubUnits, {from: defaultAccount});
		await depositFunds(10*transferAmount*underlyingAssetSubUnits, 10*transferAmount*strike*strikeAssetSubUnits, true, {from: defaultAccount});
		await depositFunds(10*transferAmount*underlyingAssetSubUnits, 10*transferAmount*strike*strikeAssetSubUnits, false, {from: receiverAccount});
		res = (await exchangeInstance.underlyingAssetDeposits(defaultAccount)).toNumber();
		assert.equal(res, 10*underlyingAssetSubUnits*transferAmount, "correct amount of collateral claimed for " + defaultAccount);
		defaultAccountBalance = res;
		res = (await optionsInstance.underlyingAssetDeposits(receiverAccount)).toNumber();
		assert.equal(res, 10*underlyingAssetSubUnits*transferAmount, "correct amount of collateral claimed for " + receiverAccount);
		receiverAccountBalance = res;
		defaultAccountBalance -= amount*price;
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 0));
		assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Buy order");
		assert.equal(res.maturity, maturity, "the maturity of the option contract is correct");
		assert.equal(res.strike, strike, "the strike of the option contract is correct");
		assert.equal(res.price, price, "the price of the order is correct");
		assert.equal(res.amount, amt, "the amount of the order is correct");
		defaultAccountBalance -= (price-10000)*amount;
		await mintHandler.postOrder(maturity, strike, price-10000, amount, true, true, {from: defaultAccount});
		firstSellAmount = "5";
		fsamtBN = (new BN(firstSellAmount)).mul(underlyingAssetSubUnitsBN);
		fsamt = fsamtBN.toString();
		receiverAccountPosition -= firstSellAmount;
		defaultAccountPosition += firstSellAmount;
		await exchangeInstance.marketSell(maturity, strike, 0, fsamt, maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 0);
		res = await exchangeInstance.linkedNodes(res);
		res = (await exchangeInstance.offers(res.hash)).amount.toString();
		assert.equal(res, fsamt, "the amount of the head order has decreaced the correct amount");
		receiverAccountPosition -= amount-firstSellAmount+1;
		defaultAccountPosition += amount-firstSellAmount+1;
		var nextAmt = amtBN.sub(fsamtBN).add(underlyingAssetSubUnitsBN).toString();
		await exchangeInstance.marketSell(maturity, strike, 0, nextAmt, maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 0);
		res = await exchangeInstance.linkedNodes(res);
		res = (await exchangeInstance.offers(res.hash)).amount.toString();
		assert.equal(res, amtBN.sub(underlyingAssetSubUnitsBN).toString(), "amount of second order after marketSell is correct");
		receiverAccountPosition -= amount-1;
		defaultAccountPosition += amount-1;
		nextAmt = (new BN("2")).mul(amtBN).sub(underlyingAssetSubUnitsBN).toString();
		await exchangeInstance.marketSell(maturity, strike, 0, nextAmt, maxIterations, true, {from:receiverAccount});
		//we have not updated the receiverAccountBalance yet so we will aggregate the impact of all orders here
		receiverAccountBalance -= (underlyingAssetSubUnits*2*amount) - (amount*(2*price-10000));
		assert.equal(await exchangeInstance.listHeads(maturity, strike, 0), defaultBytes32, "after orderbook has been emptied there are no orders");
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 0));
		assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
		await exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		assert.equal(await exchangeInstance.listHeads(maturity, strike, 0), defaultBytes32, "the order cancellation has been recognized");
		//now we make sure the balances of each user are correct
		assert.equal((await exchangeInstance.underlyingAssetDeposits(defaultAccount)).toNumber(), defaultAccountBalance, "default Account balance is correct");
		assert.equal((await optionsInstance.underlyingAssetDeposits(receiverAccount)).toNumber(), receiverAccountBalance, "receiver Account balance is correct");
	});

	it('can post and take sell orders of calls', async () => {
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		//await exchangeInstance.listHeads(maturity, strike, 1);
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		assert.notEqual(res.hash, defaultBytes32, "likedNodes[name] is not null");
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.offerer, defaultAccount, "offerer is the same as the address that posted Sell order");
		assert.equal(res.maturity.toNumber(), maturity, "the maturity of the option contract is correct");
		assert.equal(res.strike.toNumber(), strike, "the strike of the option contract is correct");
		assert.equal(res.price.toNumber(), price, "the price of the option contract is correct");
		assert.equal(res.amount.toString(), amt, "the amount of the option contract is correct");
		await mintHandler.postOrder(maturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		firstBuyAmount = "5";
		fbamtBN = (new BN(firstBuyAmount)).mul(underlyingAssetSubUnitsBN);
		fbamt = fbamtBN.toString();
		await exchangeInstance.marketBuy(maturity, strike, price+100000, fbamt, maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount.toString(), fbamt, "the amount of the contract has decreaced the correct amount");
		await exchangeInstance.marketBuy(maturity, strike, price+100000, amtBN.sub(fbamtBN).add(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		res = await exchangeInstance.offers(res.hash);
		assert.equal(res.amount.toString(), amtBN.sub(strikeAssetSubUnitsBN).toString(), "amount of second order after marketBuy is correct");
		await exchangeInstance.marketBuy(maturity, strike, price+100000, amtBN.mul(new BN("2")).sub(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 1);
		assert.equal(res, defaultBytes32, "after orderbook has been emptied there are no orders");
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		res = await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 1));
		assert.notEqual(res.hash, defaultBytes32, "the buy order has been recognized");
		await exchangeInstance.cancelOrder(res.name, {from: defaultAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 1);
		assert.equal(res, defaultBytes32, "the order cancellation has been recognized");
		defaultTotal = (await exchangeInstance.underlyingAssetDeposits(defaultAccount)).add(await optionsInstance.underlyingAssetDeposits(defaultAccount)).toString();
		assert.equal(defaultTotal, 10*transferAmount*underlyingAssetSubUnits+"", "defaultAccount has correct balance");
		recTotal = (await exchangeInstance.underlyingAssetDeposits(receiverAccount)).add(await optionsInstance.underlyingAssetDeposits(receiverAccount)).toString();
		assert.equal(recTotal, 10*transferAmount*underlyingAssetSubUnits+"", "receiverAccount has the correct balance");
	});

	it('can post and take buy orders of puts', async () => {
		//price must be lower than strike
		strike = Math.floor(strikeAssetSubUnits*0.7);
		price = strike - Math.floor(strike/2);
		defaultAccountBalance = (await exchangeInstance.strikeAssetDeposits(defaultAccount)).toNumber();
		receiverAccountPosition = 0;
		defaultAccountPosition = 0;
		receiverAccountBalance = (await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber();
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
		assert.equal(res.amount.toString(), amt, "the amount in the list head order is correct");
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
		firstSellAmount = (amount-4);
		fsamtBN = (new BN(firstSellAmount+"")).mul(strikeAssetSubUnitsBN);
		fsamt = fsamtBN.toString();
		receiverAccountPosition -= firstSellAmount;
		defaultAccountPosition += firstSellAmount;
		await exchangeInstance.marketSell(maturity, strike, 0, fsamt, maxIterations, false, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(head)).hash);
		assert.equal(res.amount.toString(), amtBN.sub(fsamtBN).toString(), "the amount left in the list head has decreaced the correct amount");
		receiverAccountPosition -= amount+1;
		defaultAccountPosition += amount+1;
		rec = await exchangeInstance.marketSell(maturity, strike, 0, amtBN.add(strikeAssetSubUnitsBN).toString(), maxIterations, false, {from: receiverAccount});
		res = await exchangeInstance.listHeads(maturity, strike, 2);
		assert.equal(head != res, true, "head updates again");
		head = res;
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(head)).hash);
		assert.equal(res.amount.toString(), amtBN.sub(fsamtBN).sub(strikeAssetSubUnitsBN).toString(), "the amount in the orders after three orders is still correct");
		receiverAccountBalance -= (amount+firstSellAmount+1)*strike -(amount*(price+5000)+(1+firstSellAmount)*price);
		assert.equal((await exchangeInstance.strikeAssetDeposits(defaultAccount)).toNumber(), defaultAccountBalance, "default account balance is correct");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber(), receiverAccountBalance, "receiver account balance is correct");
		halfPutAmount = (await optionsInstance.balanceOf(defaultAccount, maturity, strike, false)).toNumber();
	});

	it('can post and take sell orders of puts', async () => {
		defaultAccountBalance = (await exchangeInstance.strikeAssetDeposits(defaultAccount)).toNumber();
		receiverAccountBalance = (await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber();
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
		assert.equal(res.amount.toString(), amt, "the amount in the list head order is correct");
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
		fbamtBN = (new BN(firstBuyAmount+"")).mul(strikeAssetSubUnitsBN);
		fbamt = fbamtBN.toString();
		receiverAccountPosition += firstBuyAmount;
		defaultAccountPosition -= firstBuyAmount;
		await exchangeInstance.marketBuy(maturity, strike, price+100000, fbamt, maxIterations, false, {from: receiverAccount});
		assert.equal((await exchangeInstance.offers(current)).amount.toString(), amtBN.sub(fbamtBN).toString(), "the amount has been decremented correctly");
		receiverAccountPosition += amount+1;
		defaultAccountPosition -= amount+1;
		await exchangeInstance.marketBuy(maturity, strike, price+100000, amtBN.add(strikeAssetSubUnitsBN), maxIterations, false, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(maturity, strike, 3))).hash);
		assert.equal(res.price.toNumber(), price, "the price of the last node order is correct");
		assert.equal(res.amount.toString(), amtBN.sub(fbamtBN).sub(strikeAssetSubUnitsBN).toString(), "the amount has decremented correctly");
		//aggregate impact of market on receiverAccount
		receiverAccountBalance -= amount*(price-5000) + (firstBuyAmount+1)*price;
		receiverAccountBalance += strike*(amount+firstBuyAmount+1); //account for unlocked collateral
		//add (halfPutAmount*strike) to make up for the amount that was bought and then sold as we subtracted it out when puts were sold
		defaultAccountBalance += (new BN(halfPutAmount)).mul(new BN(strike)).div(strikeAssetSubUnitsBN).toNumber();
		defaultTotal = (await exchangeInstance.strikeAssetDeposits(defaultAccount)).add(await optionsInstance.strikeAssetDeposits(defaultAccount)).toString();
		assert.equal(defaultTotal, defaultAccountBalance, "defaultAccount has the correct balance");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber(), receiverAccountBalance, "receiverAccount has the correct balance");
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
		await exchangeInstance.marketSell(otherMaturity, strike, price-5000, amtBN.mul(new BN("5")).toString(), maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.listHeads(otherMaturity, strike, 0);
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(otherMaturity, strike, 0))).hash);
		assert.equal(res.price.toNumber(), price-10000, "the limit price stopped further selling at prices lower than the limit price");
		//now we will test the same for posting Sell orders and making market Buy orders
		await mintHandler.postOrder(otherMaturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-10000, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price+10000, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(otherMaturity, strike, price-5000, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(otherMaturity, strike, price, amtBN.mul(new BN("5")).toString(), maxIterations, true, {from: receiverAccount});
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(await exchangeInstance.listHeads(otherMaturity, strike, 1))).hash);
		assert.equal(res.price.toNumber(), price+10000, "the limit price stopped further buying at prices higher than the limit price");
	});

	it('withdraws funds', async () => {
		defTokens = (await exchangeInstance.underlyingAssetDeposits(defaultAccount)).toNumber();
		recTokens = (await exchangeInstance.underlyingAssetDeposits(receiverAccount)).toNumber();
		defBalance = (await tokenInstance.balanceOf(defaultAccount)).toNumber();
		recBalance = (await tokenInstance.balanceOf(receiverAccount)).toNumber();
		await exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		assert.equal((await tokenInstance.balanceOf(defaultAccount)).toNumber(), defTokens+defBalance, "awarded correct amount");
		assert.equal((await tokenInstance.balanceOf(receiverAccount)).toNumber(), recTokens+recBalance, "awarded correct amount");
		assert.equal((await exchangeInstance.underlyingAssetDeposits(defaultAccount)).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		assert.equal((await exchangeInstance.underlyingAssetDeposits(receiverAccount)).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		//now test for the same for strike asset
		defStable = (await exchangeInstance.strikeAssetDeposits(defaultAccount)).toNumber();
		recStable = (await exchangeInstance.strikeAssetDeposits(receiverAccount)).toNumber();
		defBalance = (await strikeAssetInstance.balanceOf(defaultAccount)).toNumber();
		recBalance = (await strikeAssetInstance.balanceOf(receiverAccount)).toNumber();
		await exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		assert.equal((await strikeAssetInstance.balanceOf(defaultAccount)).toNumber(), defStable+defBalance, "awarded correct amount");
		assert.equal((await strikeAssetInstance.balanceOf(receiverAccount)).toNumber(), recStable+recBalance, "awarded correct amount");
		assert.equal((await exchangeInstance.strikeAssetDeposits(defaultAccount)).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		assert.equal((await exchangeInstance.strikeAssetDeposits(receiverAccount)).toNumber(), 0, "funds correctly deducted when withdrawing funds");
		//now witdraw all funds from options smart contract for tidyness
		await optionsInstance.withdrawFunds({from: receiverAccount});
	});

	it('does not require excessive amount of collateral for calls', async () => {
		newMaturity = 2*maturity;
		strike = 100;
		await tokenInstance.transfer(receiverAccount, 10*transferAmount*underlyingAssetSubUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(receiverAccount, 10*transferAmount*strike*strikeAssetSubUnits, {from: defaultAccount});
		//------------------------------------------------------test with calls-------------------------------------
		await depositFunds(price*amount, 0, true, {from: defaultAccount});
		await depositFunds(amount*underlyingAssetSubUnits, 0, false, {from: receiverAccount});
		//Test market sells
		//fist defaultAccount buys from receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(newMaturity, strike, 0, amount, maxIterations, true, {from: receiverAccount});
		//price/underlyingAssetSubUnits == (strike-secondStrike)/strike
		//secondStrike == strike - price*strike/underlyingAssetSubUnits
		secondStrike = strike - Math.floor(price*strike/underlyingAssetSubUnits);
		await depositFunds(price*amount, 0, true, {from: receiverAccount});
		//second defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, secondStrike, price, amount, true, true, {from: receiverAccount});
		await exchangeInstance.marketSell(newMaturity, secondStrike, 0, amount, maxIterations, true, {from: defaultAccount});
		//default account has funds in exchange contract while receiver account has funds in the options smart contract
		await exchangeInstance.withdrawAllFunds(true, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		//Test market buys
		/*
			note that we need to deposit more collateral here because to post an order it must be fully collateralised
		*/
		await depositFunds(amount*(underlyingAssetSubUnits-price), 0, true, {from: defaultAccount});
		await depositFunds(amount*price, 0, false, {from: receiverAccount});
		//fist defaultAccount sells to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, maxIterations, true, {from: receiverAccount});
		//deposit funds
		await depositFunds(amount*(underlyingAssetSubUnits-price), 0, true, {from: receiverAccount});
		//second defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, true, {from: receiverAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, maxIterations, true, {from: defaultAccount});
	});

	it('does not require excessive amount of collateral for puts', async () => {
		//----------------------------------------------test with puts--------------------------------------------
		price = strike - 1;
		await depositFunds(0, price*amount, true, {from: defaultAccount});
		await depositFunds(0, amount*(strike-price), false, {from: receiverAccount});
		//Test market sell
		//fist defaultAccount buys from receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(newMaturity, strike, 0, amount, maxIterations, false, {from: receiverAccount});

		secondStrike = price+strike; 
		await depositFunds(0, amount*(secondStrike-strike), false, {from: defaultAccount});
		await depositFunds(0, amount*price, true, {from: receiverAccount});
		//next defaultAccount sells back to receiver account
		await mintHandler.postOrder(newMaturity, secondStrike, price, amount, true, false, {from: receiverAccount});
		await exchangeInstance.marketSell(newMaturity, secondStrike, 0, amount, maxIterations, false, {from: defaultAccount});
		//default account has funds in exchange contract while receiver account has funds in the options smart contract
		await exchangeInstance.withdrawAllFunds(false, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		//Test market buy
		/*
			note that we need to deposit more collateral here because to post an order it must be fully collateralised
		*/
		await depositFunds(0, amount*(strike-price), true, {from: defaultAccount});
		await depositFunds(0, amount*price, false, {from: receiverAccount});
		//fist defaultAccount sells to receiver account
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, maxIterations, false, {from: receiverAccount});	
		//second defaultAccount sells back to receiver account
		await depositFunds(0, amount*(strike-price), true, {from: receiverAccount});
		await mintHandler.postOrder(newMaturity, strike, price, amount, false, false, {from: receiverAccount});
		await exchangeInstance.marketBuy(newMaturity, strike, price+1, amount, maxIterations, false, {from: defaultAccount});
	});

	it('prioritises older orders', async () => {
		strike = 3;
		price = Math.floor(underlyingAssetSubUnits*0.05);
		await depositFunds(amount*underlyingAssetSubUnits*4, amount*strike*4, true, {from: defaultAccount});
		await depositFunds(amount*underlyingAssetSubUnits*4, amount*strike*4, true, {from: receiverAccount});

		await tokenInstance.transfer(receiverAccount, 10*transferAmount*underlyingAssetSubUnits, {from: defaultAccount});
		await strikeAssetInstance.transfer(receiverAccount, strike*10*transferAmount*underlyingAssetSubUnits, {from: defaultAccount});

		var underlyingAssetBal = (await tokenInstance.balanceOf(defaultAccount)).toNumber();
		var strikeAssetBal = (await strikeAssetInstance.balanceOf(defaultAccount)).toNumber();
		await depositFunds(underlyingAssetBal, strikeAssetBal, true, {from: defaultAccount});
		underlyingAssetBal = (await tokenInstance.balanceOf(receiverAccount)).toNumber();
		strikeAssetBal = (await strikeAssetInstance.balanceOf(receiverAccount)).toNumber();
		await depositFunds(underlyingAssetBal, strikeAssetBal, false, {from: receiverAccount});
		//test for index 0 calls buys
		await mintHandler.postOrder(maturity, strike, price, 1, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, true, true, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 0);
		await mintHandler.insertOrder(maturity, strike, price, 3, true, true, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), underlyingAssetSubUnitsBN.toString(), "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), (new BN(2)).mul(underlyingAssetSubUnitsBN).toString(), "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount.toString(), (new BN(3)).mul(underlyingAssetSubUnitsBN).toString(), "last account is correct");
		//test for index 1 calls sells
		await mintHandler.postOrder(maturity, strike, price, 1, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, false, true, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 1);
		await mintHandler.insertOrder(maturity, strike, price, 3, false, true, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), underlyingAssetSubUnitsBN.toString(), "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), (new BN(2)).mul(underlyingAssetSubUnitsBN).toString(), "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount.toString(), (new BN(3)).mul(underlyingAssetSubUnitsBN).toString(), "last account is correct");
		//test for index 2 puts buys
		//strike must be greater than price
		price = Math.floor(strike/2);
		await mintHandler.postOrder(maturity, strike, price, 1, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, true, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 2);
		await mintHandler.insertOrder(maturity, strike, price, 3, true, false, head, {from: receiverAccount});
		res = await exchangeInstance.linkedNodes(head);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), underlyingAssetSubUnitsBN.toString(), "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), (new BN(2)).mul(underlyingAssetSubUnitsBN).toString(), "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount.toString(), (new BN(3)).mul(underlyingAssetSubUnitsBN).toString(), "last account is correct");
		//test for index 3 puts sells
		await mintHandler.postOrder(maturity, strike, price, 1, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, 2, false, false, {from: defaultAccount});
		head = await exchangeInstance.listHeads(maturity, strike, 3);
		headNode = await exchangeInstance.linkedNodes(head);
		next = headNode.next;
		await mintHandler.insertOrder(maturity, strike, price, 3, false, false, next, {from: receiverAccount});
		assert.equal((await exchangeInstance.offers(headNode.hash)).amount.toString(), underlyingAssetSubUnitsBN.toString(), "the first account is correct");
		res = await exchangeInstance.linkedNodes(next);
		next = res.next;
		assert.equal((await exchangeInstance.offers(res.hash)).amount.toString(), (new BN(2)).mul(underlyingAssetSubUnitsBN).toString(), "the second account is correct");
		res = await exchangeInstance.offers((await exchangeInstance.linkedNodes(next)).hash);
		assert.equal(res.amount.toString(), (new BN(3)).mul(underlyingAssetSubUnitsBN).toString(), "last account is correct");
	});

	it('allow users to accept their own orders', async () => {
		maturity +=1;
		price = Math.floor(underlyingAssetSubUnits*0.9);
		//test taking long call offers
		balance = await exchangeInstance.underlyingAssetDeposits(defaultAccount);
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.sub((new BN(4)).mul(underlyingAssetSubUnitsBN)).toString(), maxIterations, true, {from: defaultAccount});
		res = await exchangeInstance.underlyingAssetDeposits(defaultAccount);
		assert.equal(balance.sub(res).toString(), (new BN(price)).mul(new BN(4)).toString(), "executes trades with self in marketSell of calls");
		balance = res
		rec = await exchangeInstance.marketSell(maturity, strike, price, amt, maxIterations, true, {from: defaultAccount});
		res = await exchangeInstance.underlyingAssetDeposits(defaultAccount);
		assert.equal(res.sub(balance).toString(), (new BN(price)).mul(new BN(4)).toString(), "executes trades with self in takeSellOffer of calls");
		balance = res;
		//test taking short call offers
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.sub((new BN(4)).mul(underlyingAssetSubUnitsBN)).toString(), maxIterations, true, {from: defaultAccount});
		res = await exchangeInstance.underlyingAssetDeposits(defaultAccount);
		assert.equal(balance.sub(res).toString(), (new BN(4)).mul(new BN(underlyingAssetSubUnits-price)).toString(), "executes tades with self in marketBuy of calls");
		balance = res;
		await exchangeInstance.marketBuy(maturity, strike, price, amt, maxIterations, true, {from: defaultAccount});
		res = await exchangeInstance.underlyingAssetDeposits(defaultAccount);
		assert.equal(res.sub(balance).toString(), (new BN(4)).mul(new BN(underlyingAssetSubUnits-price)).toString(), "executes  trades with self in takeBuyOffer of calls");
		res = await exchangeInstance.strikeAssetDeposits(defaultAccount);
		balance = res;
		//for puts strike must be greater than price
		price = Math.floor(0.9*strike);
		//test taking long put offers
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.sub((new BN(4)).mul(strikeAssetSubUnitsBN)).toString(), maxIterations, false, {from: defaultAccount});
		res = await exchangeInstance.strikeAssetDeposits(defaultAccount);
		assert.equal(balance.sub(res).toString(), (new BN(4)).mul(new BN(price)).toString(), "executes trades with self in marketSell of puts");
		balance = res;
		await exchangeInstance.marketSell(maturity, strike, price, amt, maxIterations, false, {from: defaultAccount});
		res = await exchangeInstance.strikeAssetDeposits(defaultAccount);
		assert.equal(res.sub(balance).toString(), (new BN(4)).mul(new BN(price)).toString(), "executes trades with self in takeSellOffer of puts");
		balance = res;
		//test taking short put offers
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.sub((new BN(4)).mul(strikeAssetSubUnitsBN)).toString(), maxIterations, false, {from: defaultAccount});
		res = await exchangeInstance.strikeAssetDeposits(defaultAccount);
		assert.equal(balance.sub(res).toString(), (new BN(4)).mul(new BN(strike-price)).toString(), "executes trades with self in marketBuy of puts");
		balance = res;
		await exchangeInstance.marketBuy(maturity, strike, price, amt, maxIterations, false, {from: defaultAccount});
		res = await exchangeInstance.strikeAssetDeposits(defaultAccount);
		assert.equal(res.sub(balance).toString(), (new BN(4)).mul(new BN(strike-price)).toString(), "executes trades with self in takeBuyOffer of puts");
	});

	it('requires strike to be added before placing order', async () => {
		await depositFunds(amount*underlyingAssetSubUnits*4, amount*strike*4, true, {from: defaultAccount});
		await depositFunds(amount*underlyingAssetSubUnits*4, amount*strike*4, true, {from: receiverAccount});

		return exchangeInstance.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount}).then(() => {
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
			return exchangeInstance.marketSell(maturity, strike, price, amount, maxIterations, true, {from: receiverAccount});
		}).then(() => {
			return "OK";
		}).catch((err) => {
			if (err.message === "missed checkpoint") throw err;
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "can't marketSell without first adding maturity strike combo on options smart contract");
			return exchangeInstance.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		}).then(() => {
			return exchangeInstance.marketBuy(maturity, strike, price, amount, maxIterations, false, {from: receiverAccount});
		}).then((rec) => {
			return optionsInstance.viewStrikes(receiverAccount, maturity);
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
		amtBN = (new BN(amount)).mul(underlyingAssetSubUnitsBN);
		amt = amtBN.toString();
		//send ample amount of funds for defaultAccount
		await optionsInstance.withdrawFunds({from: defaultAccount});
		await optionsInstance.withdrawFunds({from: receiverAccount});
		await depositFunds(10*amount*underlyingAssetSubUnits, 10*amount*strike*strikeAssetSubUnits, true, {from: defaultAccount});
		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds((2*amount-1)*(underlyingAssetSubUnits-price), 0, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		//should not revert
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.mul(new BN(2)).toString(), maxIterations, true, {from: receiverAccount});
		//correct amount of orders left
		var headName = await exchangeInstance.listHeads(maturity, strike, 0);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), amt, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.underlyingAssetDeposits(receiverAccount)).toNumber(), (amount-1)*(underlyingAssetSubUnits-price), "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
		//now try setting amount to less than the amount in the market order to less than the amount in the second order so that this acceptBuyOffer is only called once
		//we expect the second order in the linked list to not be affected
		await depositFunds(amount*(underlyingAssetSubUnits-price), 0, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, true, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.mul(new BN(2)).sub(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 0);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), underlyingAssetSubUnitsBN.toString(), "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.underlyingAssetDeposits(receiverAccount)).toString(), "0", "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

	it('fills all possible orders in exchange with posted order index 1', async () => {
		maturity++;

		await exchangeInstance.withdrawAllFunds(true, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds((2*amount-1)*price, 0, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		//should not revert
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.mul(new BN(2)).toString(), maxIterations, true, {from: receiverAccount});
		//correct amount of orders left
		var headName = await exchangeInstance.listHeads(maturity, strike, 1);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), amt, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.underlyingAssetDeposits(receiverAccount)).toNumber(), (amount-1)*price, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(amount*price, 0, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, true, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.mul(new BN(2)).sub(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 1);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), underlyingAssetSubUnitsBN.toString(), "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.underlyingAssetDeposits(receiverAccount)).toString(), "0", "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

	it('fills all possible orders in exchange with posted order index 2', async () => {
		maturity++;
		strike = 5;
		//price must be lower than strike
		price = strike-2;
		//send ample amount of funds for defaultAccount
		await optionsInstance.withdrawFunds({from: receiverAccount});
		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds(0, (2*amount-1)*(strike-price), false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.mul(new BN(2)).toString(), maxIterations, false, {from: receiverAccount});
		var headName = await exchangeInstance.listHeads(maturity, strike, 2);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), amt, "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber(), (amount-1)*(strike-price), "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(0, amount*(strike-price), false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, true, false, {from: defaultAccount});
		await exchangeInstance.marketSell(maturity, strike, price, amtBN.mul(new BN(2)).sub(underlyingAssetSubUnitsBN).toString(), maxIterations, false, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 2);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), underlyingAssetSubUnitsBN.toString(), "correct amount left after market sell");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toString(), "0", "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});


	it('fills all possible orders in exchange with posted order index 3', async () => {
		maturity++;
		strike = 5;
		//price must be lower than strike
		price = strike-2;

		await exchangeInstance.withdrawAllFunds(false, {from: receiverAccount});
		//market orders that end not able to fuffil second call to acceptBuyOffer
		await depositFunds(0, (2*amount-1)*price, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await addStrike(receiverAccount, maturity, strike);
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.mul(new BN(2)).toString(), maxIterations, false, {from: receiverAccount});
		var headName = await exchangeInstance.listHeads(maturity, strike, 3);
		var headNode = await exchangeInstance.linkedNodes(headName);
		var headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), amt, "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toNumber(), (amount-1)*price, "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});

		await depositFunds(0, amount*price, false, {from: receiverAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await mintHandler.postOrder(maturity, strike, price, amount, false, false, {from: defaultAccount});
		await exchangeInstance.marketBuy(maturity, strike, price, amtBN.mul(new BN(2)).sub(underlyingAssetSubUnitsBN).toString(), maxIterations, false, {from: receiverAccount});		
		headName = await exchangeInstance.listHeads(maturity, strike, 3);
		headNode = await exchangeInstance.linkedNodes(headName);
		headOffer = await exchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), underlyingAssetSubUnitsBN.toString(), "correct amount left after market buy");
		assert.equal(headNode.next, defaultBytes32, "no next offer");
		assert.equal((await optionsInstance.strikeAssetDeposits(receiverAccount)).toString(), "0", "correct balance for receiverAccount");
		await exchangeInstance.cancelOrder(headName, {from: defaultAccount});
	});

	it('uses max iterations limit market buy puts', async () => {
		maturity++;
		strike = 2;
		maxIterations = 5;
		for(let i = 0; i < 2; i++){
			await addStrike(receiverAccount, maturity, strike+i);
			await addStrike(defaultAccount, maturity, strike+i);
		}
		for (let i = 0; i < maxIterations+2; i++)
			await exchangeInstance.postOrder(maturity, strike, 1, 1, false, false, {from: defaultAccount});

		await depositFunds(0, 100, false, {from: receiverAccount});
		var prevBalanceRecAct = await optionsInstance.strikeAssetDeposits(receiverAccount);
		await exchangeInstance.marketBuy(maturity, strike, 1, (new BN(100)).mul(strikeAssetSubUnitsBN).toString(), maxIterations, false, {from: receiverAccount});
		assert.equal((await optionsInstance.balanceOf(receiverAccount, maturity, 2, false)).toNumber(), maxIterations, "correct balance of puts for receiver account");
		assert.equal((await optionsInstance.balanceOf(defaultAccount, maturity, 2, false)).toNumber(), -maxIterations, "correct balance of puts for default account");
		var balanceRecAct = await optionsInstance.strikeAssetDeposits(receiverAccount);
		assert.equal(prevBalanceRecAct.sub(balanceRecAct).toString(), (new BN(maxIterations)).toString(), "market taker requirement rounds up");
	});

	it('uses max iterations limit market sell puts', async () => {
		maturity++;
		strike = 2;
		maxIterations = 5;
		for(let i = 0; i < 2; i++){
			await addStrike(receiverAccount, maturity, strike+i);
			await addStrike(defaultAccount, maturity, strike+i);
		}
		for (let i = 0; i < maxIterations+2; i++)
			await exchangeInstance.postOrder(maturity, strike, 1, 1, true, false, {from: defaultAccount});

		await depositFunds(0, 100, false, {from: receiverAccount});
		var prevBalanceRecAct = await optionsInstance.strikeAssetDeposits(receiverAccount);
		await exchangeInstance.marketSell(maturity, strike, 1, (new BN(100)).mul(strikeAssetSubUnitsBN).toString(), maxIterations, false, {from: receiverAccount});
		assert.equal((await optionsInstance.balanceOf(receiverAccount, maturity, 2, false)).toNumber(), -maxIterations, "correct balance of puts for receiver account");
		assert.equal((await optionsInstance.balanceOf(defaultAccount, maturity, 2, false)).toNumber(), maxIterations, "correct balance of puts for default account");
		var balanceRecAct = await optionsInstance.strikeAssetDeposits(receiverAccount);
		//because the strike price is less than 1 full unit of the strike asset  and the amount is also a sub unit the collateral requirement is constant after the first iteration at 1 sub unit
		assert.equal(prevBalanceRecAct.sub(balanceRecAct).toString(), "1", "market taker requirement rounds up");
	});

	it('uses max iterations limit market sell calls', async () => {
		maturity++;
		strike = 2;
		maxIterations = 5;
		for(let i = 0; i < 2; i++){
			await addStrike(receiverAccount, maturity, strike+i);
			await addStrike(defaultAccount, maturity, strike+i);
		}
		for (let i = 0; i < maxIterations+2; i++)
			await exchangeInstance.postOrder(maturity, strike, 1, 1, true, true, {from: defaultAccount});
		await depositFunds(10000000, 0, false, {from: receiverAccount});
		var prevBalanceRecAct = await optionsInstance.underlyingAssetDeposits(receiverAccount);
		await exchangeInstance.marketSell(maturity, strike, 1, (new BN(100)).mul(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});
		assert.equal((await optionsInstance.balanceOf(receiverAccount, maturity, 2, true)).toNumber(), -maxIterations, "correct balance of puts for receiver account");
		assert.equal((await optionsInstance.balanceOf(defaultAccount, maturity, 2, true)).toNumber(), maxIterations, "correct balance of puts for default account");
		var balanceRecAct = await optionsInstance.underlyingAssetDeposits(receiverAccount);
		assert.equal(prevBalanceRecAct.sub(balanceRecAct).toString(), (new BN(maxIterations)).toString(), "market taker requirement rounds up");
	});

	it('uses max iterations limit market buy calls', async () => {
		maturity++;
		strike = 2;
		maxIterations = 5;
		for(let i = 0; i < 2; i++){
			await addStrike(receiverAccount, maturity, strike+i);
			await addStrike(defaultAccount, maturity, strike+i);
		}
		for (let i = 0; i < maxIterations+2; i++)
			await exchangeInstance.postOrder(maturity, strike, 1, 1, false, true, {from: defaultAccount});
		await depositFunds(10000000, 0, false, {from: receiverAccount});
		var prevBalanceRecAct = await optionsInstance.underlyingAssetDeposits(receiverAccount);
		await exchangeInstance.marketBuy(maturity, strike, 1, (new BN(100)).mul(underlyingAssetSubUnitsBN).toString(), maxIterations, true, {from: receiverAccount});
		assert.equal((await optionsInstance.balanceOf(receiverAccount, maturity, 2, true)).toNumber(), maxIterations, "correct balance of puts for receiver account");
		assert.equal((await optionsInstance.balanceOf(defaultAccount, maturity, 2, true)).toNumber(), -maxIterations, "correct balance of puts for default account");
		var balanceRecAct = await optionsInstance.underlyingAssetDeposits(receiverAccount);
		assert.equal(prevBalanceRecAct.sub(balanceRecAct).toString(), (new BN(maxIterations)).toString(), "market taker requirement rounds up");
	});

});