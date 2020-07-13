const oracle = artifacts.require("./oracle.sol");
const token = artifacts.require("./UnderlyingAsset.sol");
const options = artifacts.require("./options.sol");
const multiLegExchange = artifacts.require("./multiLeg/multiLegExchange.sol");
const mOrganizer = artifacts.require("mOrganizer");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const mLegHelper = artifacts.require("mLegHelper");
const mLegDelegate = artifacts.require("mLegDelegate");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");

const helper = require("../helper/helper.js");


const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
var maturity = 100;
var amount = 10;



contract('multi leg exchange', function(accounts){

	var deployerAccount = accounts[0];

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		mLegDelegateInstance = await mLegDelegate.new();
		mLegHelperInstance = await mLegHelper.new(mLegDelegate.address, feeOracleInstance.address);
		mOrganizerInstance = await mOrganizer.new(accounts[0], accounts[0], mLegHelperInstance.address); //the params here do not matter
		mLegDelegateInstance = await mLegDelegate.new();
		optionsInstance = await options.new(oracleInstance.address, asset1.address, asset2.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
		await mOrganizerInstance.deployMultiLegExchange(optionsInstance.address);
		multiLegExchangeInstance = await multiLegExchange.at(await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 2));
		asset1SubUnits = Math.pow(10, await asset1.decimals());
		asset2SubUnits = Math.pow(10, await asset2.decimals());
		inflator = await oracleInstance.inflator();
		await feeOracleInstance.setSpecificFees(optionsInstance.address, 0, 10000, 20000);
	});

	async function depositFunds(to, asset1Amount, asset2Amount, exchange){
		var address = exchange ? multiLegExchangeInstance.address : optionsInstance.address;
		if (asset1Amount > 0)
			await asset1.transfer(address, asset1Amount, {from: deployerAccount});
		if (asset2Amount > 0)
			await asset2.transfer(address, asset2Amount, {from: deployerAccount});
		if (exchange)
			return multiLegExchangeInstance.depositFunds(to);
		else
			return optionsInstance.depositFunds(to);
	}

	async function postOrder(maturity, legsHash, price, amount, index, params) {
		var balance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		if (typeof params.gasPrice === "undefined") params.gasPrice = 20000000000; //20 gwei
		var postOrderFee = new web3.utils.BN(await feeOracleInstance.multiLegExchangeFlatEtherFee());
		params.value = postOrderFee.toNumber();
		var rec = await multiLegExchangeInstance.postOrder(maturity, legsHash, price, amount, index, params);
		var txFee = new web3.utils.BN(rec.receipt.gasUsed * params.gasPrice);
		var newBalance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		var result = txFee.add(newBalance);
		assert.equal(result.cmp(balance.sub(postOrderFee)), 0, "correct fees paid");
	}


	it('creates positions with the correct collateral requirements', async () => {
		callStrikes = [10, 20];
		callAmounts = [1, -2];
		putStrikes = [10];
		putAmounts = [1];
		//these calculations would be different if we had different values in the above arrays
		maxUnderlyingAssetDebtor = (-1*(callAmounts[0] + callAmounts[1])) * Math.floor(asset1SubUnits * ((callStrikes[1]-callStrikes[0])/callStrikes[1]));
		maxUnderlyingAssetHolder = -1 * asset1SubUnits * (callAmounts[0] + callAmounts[1]);
		maxStrikeAssetDebtor = putAmounts[0] * putStrikes[0];
		maxStrikeAssetHolder = 0;
		rec = await multiLegExchangeInstance.addLegHash(callStrikes, callAmounts, putStrikes, putAmounts);
		assert.equal(rec.logs[0].event, "legsHashCreated", "correct event emmited");
		legsHash = rec.logs[0].args.legsHash;
		position = await multiLegExchangeInstance.positions(legsHash);
		positionInfo = await multiLegExchangeInstance.positionInfo(legsHash);
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
		assert.equal(position.putStrikes+'', putStrikes+'', "correct put strikes in position info");
		assert.equal(position.putAmounts+'', putAmounts+'', "correct put amounts in position info")
		//check value of collateral requirements
		assert.equal(position.maxUnderlyingAssetDebtor, maxUnderlyingAssetDebtor, "correct value for maxUnderlyingAssetDebtor");
		assert.equal(position.maxUnderlyingAssetHolder, maxUnderlyingAssetHolder, "correct value for maxUnderlyingAssetHolder");
		assert.equal(position.maxStrikeAssetDebtor, maxStrikeAssetDebtor, "correct value for maxStrikeAssetDebtor");
		assert.equal(position.maxStrikeAssetHolder, maxStrikeAssetHolder, "correct value for maxStrikeAssetHolder");
	});

	it('posts orders with correct collateral requirements index 0', async () => {
		price = 6;
		//add strikes
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});

		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+price), amount*maxStrikeAssetHolder, true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-price), amount*maxStrikeAssetDebtor, false);
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 0);
		await multiLegExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), amount*(maxUnderlyingAssetHolder+price), "correct underlying asset balance after canceling order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), amount*maxStrikeAssetHolder, "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = -2;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetHolder+secondPrice), amount*maxStrikeAssetHolder, true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetDebtor-secondPrice), amount*maxStrikeAssetDebtor, false);
		await postOrder(maturity, legsHash, secondPrice, amount, 0, {from: deployerAccount});

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiLegExchangeInstance.marketSell(maturity, legsHash, price, amount-5, true, {from: accounts[1]});
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 0);
		headNode = await multiLegExchangeInstance.linkedNodes(listHead);
		headOffer = await multiLegExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market sell");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetDebtor-price)+ amount*(maxUnderlyingAssetDebtor-secondPrice), "correct underlying asset balance after market sell");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), (amount+5)*maxStrikeAssetDebtor, "correct strike asset balance after market sell");

		await multiLegExchangeInstance.marketSell(maturity, legsHash, secondPrice, 5+amount, true, {from: accounts[1]});

		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 0);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await asset1.balanceOf(multiLegExchangeInstance.address)).toNumber(), 0, "correct asset1 balance of contract");
		assert.equal((await asset2.balanceOf(multiLegExchangeInstance.address)).toNumber(), 0, "correct asset2 balance of contract");

		assert.equal((await multiLegExchangeInstance.satReserves()).toNumber(), 0, "correct sat reserves");
		assert.equal((await multiLegExchangeInstance.scReserves()).toNumber(), 0, "correct sc reserves");		
	});

	it('posts orders with correct collateral requirements index 1', async () => {
		maturity++;
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});
		price = -2;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-price), amount*maxStrikeAssetDebtor, true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+price), amount*maxStrikeAssetHolder, false);
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 1);
		await multiLegExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), amount*(maxUnderlyingAssetDebtor-price), "correct underlying asset balance after canceling order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), amount*maxStrikeAssetDebtor, "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = 6;
		await depositFunds(deployerAccount, amount*(maxUnderlyingAssetDebtor-secondPrice), amount*maxStrikeAssetDebtor, true);
		await depositFunds(accounts[1], amount*(maxUnderlyingAssetHolder+secondPrice), amount*maxStrikeAssetHolder, false);
		await postOrder(maturity, legsHash, secondPrice, amount, 1, {from: deployerAccount});

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");

		await multiLegExchangeInstance.marketBuy(maturity, legsHash, price, amount-5, true, {from: accounts[1]});
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 1);
		headNode = await multiLegExchangeInstance.linkedNodes(listHead);
		headOffer = await multiLegExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market buy");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 5*(maxUnderlyingAssetHolder+price)+ amount*(maxUnderlyingAssetHolder+secondPrice), "correct underlying asset balance after market sell");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), (amount+5)*maxStrikeAssetHolder, "correct strike asset balance after market buy");

		await multiLegExchangeInstance.marketBuy(maturity, legsHash, secondPrice, 5+amount, true, {from: accounts[1]});

		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 1);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), 0, "correct strike asset balance after all orders");

	});

	it('posts orders with correct collateral requirements index 2', async () => {
		maturity++;
		price = 6;
		//add strikes
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});

		await depositFunds(deployerAccount, amount*maxUnderlyingAssetHolder, amount*(maxStrikeAssetHolder+price), true);
		await depositFunds(accounts[1], amount*maxUnderlyingAssetDebtor, amount*(maxStrikeAssetDebtor-price), false);
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 2, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 2);
		await multiLegExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), amount*maxUnderlyingAssetHolder, "correct underlying asset balance after canceling order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), amount*(maxStrikeAssetHolder+price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 2, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = -2;
		await depositFunds(deployerAccount, amount*maxUnderlyingAssetHolder, amount*(maxStrikeAssetHolder+secondPrice), true);
		await depositFunds(accounts[1], amount*maxUnderlyingAssetDebtor, amount*(maxStrikeAssetDebtor-secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 2, {from: deployerAccount});

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiLegExchangeInstance.marketSell(maturity, legsHash, price, amount-5, false, {from: accounts[1]});
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 2);
		headNode = await multiLegExchangeInstance.linkedNodes(listHead);
		headOffer = await multiLegExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market sell");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), (amount+5)*maxUnderlyingAssetDebtor, "correct underlying asset balance after market sell");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), 5*(maxStrikeAssetDebtor-price) + amount*(maxStrikeAssetDebtor-secondPrice) , "correct strike asset balance after market sell");

		await multiLegExchangeInstance.marketSell(maturity, legsHash, secondPrice, 5+amount, false, {from: accounts[1]});

		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 2);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), 0, "correct strike asset balance after all orders");

	});


	it('posts orders with correct collateral requirements index 3', async () => {
		maturity++;
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, callStrikes[1], 1, {from: accounts[1]});
		price = -2;
		await depositFunds(deployerAccount, amount*maxUnderlyingAssetDebtor, amount*(maxStrikeAssetDebtor-price), true);
		await depositFunds(accounts[1], amount*maxUnderlyingAssetHolder, amount*(maxStrikeAssetHolder+price), false);
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 3, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 3);
		await multiLegExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), amount*maxUnderlyingAssetDebtor, "correct underlying asset balance after canceling order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), amount*(maxStrikeAssetDebtor-price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 3, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = 6;
		await depositFunds(deployerAccount, amount*maxUnderlyingAssetDebtor, amount*(maxStrikeAssetDebtor-secondPrice), true);
		await depositFunds(accounts[1], amount*maxUnderlyingAssetHolder, amount*(maxStrikeAssetHolder+secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 3, {from: deployerAccount});

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after posting second order");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiLegExchangeInstance.marketBuy(maturity, legsHash, price, amount-5, false, {from: accounts[1]});
		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 3);
		headNode = await multiLegExchangeInstance.linkedNodes(listHead);
		headOffer = await multiLegExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toNumber(), 5, "correct amount left after market buy");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -(amount-5)*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), (amount-5)*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -(amount-5)*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), (amount-5)*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), (amount+5)*maxUnderlyingAssetHolder, "correct underlying asset balance after market sell");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), Math.max(5*(maxStrikeAssetHolder+price), 0)+Math.max((5-amount)*(maxStrikeAssetHolder+price), 0)
			+amount*(maxStrikeAssetHolder+secondPrice), "correct strike asset balance after market buy");

		await multiLegExchangeInstance.marketBuy(maturity, legsHash, secondPrice, 5+amount, false, {from: accounts[1]});

		listHead = await multiLegExchangeInstance.listHeads(maturity, legsHash, 3);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check call balances
		for (var i = 0; i < callStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, callStrikes[i], true)).toNumber(), -2*amount*callAmounts[i], "correct call balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, callStrikes[i], true)).toNumber(), 2*amount*callAmounts[i], "correct call balance first account");
		}
		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toNumber(), -2*amount*putAmounts[i], "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toNumber(), 2*amount*putAmounts[i], "correct put balance first account");
		}

		assert.equal((await multiLegExchangeInstance.viewClaimed(true, {from: deployerAccount})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await multiLegExchangeInstance.viewClaimed(false, {from: deployerAccount})).toNumber(), 0, "correct strike asset balance after all orders");

		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), 0, "correct underlying asset balance after all orders");
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), Math.max(-amount*(maxStrikeAssetHolder+price),0)+Math.max(-amount*(maxStrikeAssetHolder+secondPrice),0),
			"correct strike asset balance after all orders");

	});

});