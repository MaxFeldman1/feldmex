var oracle = artifacts.require("./oracle.sol");
var token = artifacts.require("./UnderlyingAsset.sol");
var options = artifacts.require("./options.sol");
var multiPutExchange = artifacts.require("./multiLeg/multiPutExchange.sol");

const helper = require("../helper/helper.js");


const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
var maturity = 100;
var amount = 10;



contract('multi put exchange', function(accounts){

	var deployerAccount = accounts[0];

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		optionsInstance = await options.new(oracleInstance.address, asset1.address, asset2.address);
		multiPutExchangeInstance = await multiPutExchange.new(asset2.address, optionsInstance.address);
		asset1SubUnits = Math.pow(10, await asset1.decimals());
		asset2SubUnits = Math.pow(10, await asset2.decimals());
		inflator = await oracleInstance.inflator();
	});

	async function depositFunds(to, amount){
		if (amount > 0)
			await asset2.transfer(multiPutExchangeInstance.address, amount, {from: deployerAccount});
		return multiPutExchangeInstance.depositFunds(to);
	}

	async function postOrder(maturity, legsHash, price, amount, index, params) {
		return multiPutExchangeInstance.postOrder(maturity, legsHash, price, amount, index, params);
	}


	it('creates positions with the correct collateral requirements', async () => {
		putStrikes = [10, 20];
		putAmounts = [3, -1];
		//these calculations would be different if we had different values in the above arrays
		maxStrikeAssetDebtor = putAmounts[0] * putStrikes[0] + putAmounts[1] * putStrikes[1];
		maxStrikeAssetHolder = putAmounts[1] * (putStrikes[0]-putStrikes[1]);
		rec = await multiPutExchangeInstance.addLegHash(putStrikes, putAmounts);
		assert.equal(rec.logs[0].event, "legsHashCreated", "correct event emmited");
		legsHash = rec.logs[0].args.legsHash;
		position = await multiPutExchangeInstance.positions(legsHash);
		positionInfo = await multiPutExchangeInstance.positionInfo(legsHash);
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
		assert.equal(position.putStrikes+'', putStrikes+'', "correct put strikes in position info");
		assert.equal(position.putAmounts+'', putAmounts+'', "correct put amounts in position info");
		//check value of collateral requirements
		assert.equal(position.maxStrikeAssetDebtor, maxStrikeAssetDebtor, "correct value for maxStrikeAssetDebtor");
		assert.equal(position.maxStrikeAssetHolder, maxStrikeAssetHolder, "correct value for maxStrikeAssetHolder");
	});


	it('posts orders with correct collateral requirements index 0', async () => {
		maturity++;
		price = 6;
		//add strikes
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});

		await depositFunds(deployerAccount, amount*(maxStrikeAssetHolder+price));
		await depositFunds(accounts[1], amount*(maxStrikeAssetDebtor-price));
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		await multiPutExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), amount*(maxStrikeAssetHolder+price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = -2;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetHolder+secondPrice));
		await depositFunds(accounts[1], amount*(maxStrikeAssetDebtor-secondPrice));
		await postOrder(maturity, legsHash, secondPrice, amount, 0, {from: deployerAccount});

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiPutExchangeInstance.marketSell(maturity, legsHash, price, amount-5, {from: accounts[1]});
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		headNode = await multiPutExchangeInstance.linkedNodes(listHead);
		headOffer = await multiPutExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market sell");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 5*(maxStrikeAssetDebtor-price) + amount*(maxStrikeAssetDebtor-secondPrice) , "correct strike asset balance after market sell");

		await multiPutExchangeInstance.marketSell(maturity, legsHash, secondPrice, 5+amount, {from: accounts[1]});

		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 0, "correct strike asset balance after all orders");

	});


	it('posts orders with correct collateral requirements index 1', async () => {
		maturity++;
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});
		price = -2;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetDebtor-price));
		await depositFunds(accounts[1], amount*(maxStrikeAssetHolder+price));
		//we will attempt to trade with
		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		await multiPutExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), amount*(maxStrikeAssetDebtor-price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = 6;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetDebtor-secondPrice));
		await depositFunds(accounts[1], amount*(maxStrikeAssetHolder+secondPrice));
		await postOrder(maturity, legsHash, secondPrice, amount, 1, {from: deployerAccount});

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiPutExchangeInstance.marketBuy(maturity, legsHash, price, amount-5, {from: accounts[1]});
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		headNode = await multiPutExchangeInstance.linkedNodes(listHead);
		headOffer = await multiPutExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market buy");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), Math.max(5*(maxStrikeAssetHolder+price), 0)+Math.max((5-amount)*(maxStrikeAssetHolder+price), 0)
			+amount*(maxStrikeAssetHolder+secondPrice), "correct strike asset balance after market buy");

		await multiPutExchangeInstance.marketBuy(maturity, legsHash, secondPrice, 5+amount, {from: accounts[1]});

		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await multiPutExchangeInstance.viewClaimed({from: accounts[1]})).toNumber(), 0, "correct strike asset balance after all orders");

	});

});