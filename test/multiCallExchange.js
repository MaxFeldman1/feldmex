var oracle = artifacts.require("./oracle.sol");
var token = artifacts.require("./UnderlyingAsset.sol");
var options = artifacts.require("./options.sol");
var multiCallExchange = artifacts.require("./multiLeg/multiCallExchange.sol");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");

const helper = require("../helper/helper.js");


const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
var maturity = 100;
var amount = 10;



contract('multi call exchange', function(accounts){

	var deployerAccount = accounts[0];

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		optionsInstance = await options.new(oracleInstance.address, asset1.address, asset2.address, feldmexERC20HelperInstance.address);
		multiCallExchangeInstance = await multiCallExchange.new(asset1.address, optionsInstance.address);
		asset1SubUnits = Math.pow(10, await asset1.decimals());
		inflator = await oracleInstance.inflator();
	});

	async function depositFunds(to, amount){
		if (amount > 0)
			await asset1.transfer(multiCallExchangeInstance.address, amount, {from: deployerAccount});
		return multiCallExchangeInstance.depositFunds(to);
	}

	async function postOrder(maturity, legsHash, price, amount, index, params) {
		return multiCallExchangeInstance.postOrder(maturity, legsHash, price, amount, index, params);
	}


	it('creates positions with the correct collateral requirements', async () => {
		callStrikes = [10, 20];
		callAmounts = [1, -2];
		//these calculations would be different if we had different values in the above arrays
		maxUnderlyingAssetDebtor = (-1*(callAmounts[0] + callAmounts[1])) * Math.floor(asset1SubUnits * ((callStrikes[1]-callStrikes[0])/callStrikes[1]));
		maxUnderlyingAssetHolder = -1 * asset1SubUnits * (callAmounts[0] + callAmounts[1]);
		rec = await multiCallExchangeInstance.addLegHash(callStrikes, callAmounts);
		assert.equal(rec.logs[0].event, "legsHashCreated", "correct event emmited");
		legsHash = rec.logs[0].args.legsHash;
		position = await multiCallExchangeInstance.positions(legsHash);
		positionInfo = await multiCallExchangeInstance.positionInfo(legsHash);
		// convert position and positionInfo member vars to number
		var keys = Object.getOwnPropertyNames(position);
		for (var i = 0; i < keys.length; i++) {
			var key = keys[i];
			position[key] = position[key].toNumber();
		}
		keys = Object.getOwnPropertyNames(positionInfo);
		for (var i = 0; i < keys.length; i++){
			var key = keys[i];
			for (var j = 0; j < positionInfo[key].length; j++)
				positionInfo[key][j] = positionInfo[key][j].toNumber();
			position[key] = positionInfo[key];
		}
		//check value of arrays
		assert.equal(position.callStrikes+'', callStrikes+'', "correct call strikes in position info");
		assert.equal(position.callAmounts+'', callAmounts+'', "correct call amounts in position info")
		//check value of collateral requirements
		assert.equal(position.maxUnderlyingAssetDebtor, maxUnderlyingAssetDebtor, "correct value for maxUnderlyingAssetDebtor");
		assert.equal(position.maxUnderlyingAssetHolder, maxUnderlyingAssetHolder, "correct value for maxUnderlyingAssetHolder");
	});

	it('posts orders with correct collateral requirements index 0', async () => {
		price = 6;
		//add strikes
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});

		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+price));
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-price));
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");

		//cancels order correctly
		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 0);
		await multiCallExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), amount*(maxUnderlyingAssetHolder+price), "correct underlying asset balance after canceling order");


		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = -2;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+secondPrice));
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-secondPrice));
		await postOrder(maturity, legsHash, secondPrice, amount, 0, {from: deployerAccount});

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		
		await multiCallExchangeInstance.marketSell(maturity, legsHash, price, amount-5, {from: accounts[1]});
		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 0);
		headNode = await multiCallExchangeInstance.linkedNodes(listHead);
		headOffer = await multiCallExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market sell");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance first account");
		}

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetDebtor-price)+ amount*(maxUnderlyingAssetDebtor-secondPrice), "correct underlying asset balance after market sell");

		await multiCallExchangeInstance.marketSell(maturity, legsHash, secondPrice, 5+amount, {from: accounts[1]});

		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 0);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance first account");
		}

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");

	});

	it('posts orders with correct collateral requirements index 1', async () => {
		maturity++;
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});
		price = -2;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-price));
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+price));
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");

		//cancels order correctly
		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 1);
		await multiCallExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), amount*(maxUnderlyingAssetDebtor-price), "correct underlying asset balance after canceling order");


		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = 6;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-secondPrice));
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+secondPrice));
		await postOrder(maturity, legsHash, secondPrice, amount, 1, {from: deployerAccount});

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		
		await multiCallExchangeInstance.marketBuy(maturity, legsHash, price, amount-5, {from: accounts[1]});
		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 1);
		headNode = await multiCallExchangeInstance.linkedNodes(listHead);
		headOffer = await multiCallExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market buy");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance first account");
		}

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetHolder+price)+ amount*(maxUnderlyingAssetHolder+secondPrice), "correct underlying asset balance after market sell");

		await multiCallExchangeInstance.marketBuy(maturity, legsHash, secondPrice, 5+amount, {from: accounts[1]});

		listHead = await multiCallExchangeInstance.listHeads(maturity, legsHash, 1);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance first account");
		}

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");
	});

});