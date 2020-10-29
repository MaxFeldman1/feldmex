const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("options");
const multiCallExchange = artifacts.require("multiCallExchange");
const mCallHelper = artifacts.require("mCallHelper");
const mOrganizer = artifacts.require("mOrganizer");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");

const helper = require("../helper/helper.js");


const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
var maturity = 100;
var amount = 10;
var maxIterations = 5;



contract('multi call exchange', function(accounts){

	var deployerAccount = accounts[0];

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		mCallHelperInstance = await mCallHelper.new(feeOracleInstance.address);
		mOrganizerInstance = await mOrganizer.new(mCallHelperInstance.address, /*this param does not matter so we will just add the default address*/accounts[0], accounts[0]);
		optionsInstance = await options.new(oracleInstance.address, asset1.address, asset2.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
		await mOrganizerInstance.deployCallExchange(optionsInstance.address);
		multiCallExchangeInstance = await multiCallExchange.at(await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 0));
		asset1SubUnits = Math.pow(10, await asset1.decimals());
	});

	async function depositFunds(to, amount, exchange){
		if (amount > 0)
			await asset1.transfer(exchange ? multiCallExchangeInstance.address : optionsInstance.address, amount, {from: deployerAccount});
		if (exchange)
			return multiCallExchangeInstance.depositFunds(to);
		else
			await optionsInstance.depositFunds(to);
	}

	async function postOrder(maturity, legsHash, price, amount, index, params) {
		var balance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		if (typeof params.gasPrice === "undefined") params.gasPrice = 20000000000; //20 gwei
		var postOrderFee = new web3.utils.BN(await feeOracleInstance.multiLegExchangeFlatEtherFee());
		params.value = postOrderFee.toNumber();
		var rec = await multiCallExchangeInstance.postOrder(maturity, legsHash, price, amount, index, params);
		var txFee = new web3.utils.BN(rec.receipt.gasUsed * params.gasPrice);
		var newBalance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		var result = txFee.add(newBalance);
		assert.equal(result.cmp(balance.sub(postOrderFee)), 0, "correct fees paid");
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

		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+price), true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-price), false);
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
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+secondPrice), true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 0, {from: deployerAccount});

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		
		await multiCallExchangeInstance.marketSell(maturity, legsHash, price, amount-5, maxIterations, {from: accounts[1]});
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

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetDebtor-price)+ amount*(maxUnderlyingAssetDebtor-secondPrice), "correct underlying asset balance after market sell");

		await multiCallExchangeInstance.marketSell(maturity, legsHash, secondPrice, 5+amount, maxIterations, {from: accounts[1]});

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
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-price), true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+price), false);
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
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-secondPrice), true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 1, {from: deployerAccount});

		assert.equal((await multiCallExchangeInstance.viewClaimed({from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		
		await multiCallExchangeInstance.marketBuy(maturity, legsHash, price, amount-5, maxIterations, {from: accounts[1]});
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

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetHolder+price)+ amount*(maxUnderlyingAssetHolder+secondPrice), "correct underlying asset balance after market sell");

		await multiCallExchangeInstance.marketBuy(maturity, legsHash, secondPrice, 5+amount, maxIterations, {from: accounts[1]});

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


	it('uses max iterations limit', async () => {
		maturity++;
		price = 6;
		maxIterations = 5;
		amount = maxIterations+2;
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+price), true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-price), false);

		for (let i = 0; i < amount; i++)
			await postOrder(maturity, legsHash, price, 1, 0, {from: deployerAccount});

		await multiCallExchangeInstance.marketSell(maturity, legsHash, price, maxIterations+2, maxIterations, {from: accounts[1]});

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), maxIterations*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -maxIterations*callAmounts[i], "correct call balance first account");
		}
	});

});