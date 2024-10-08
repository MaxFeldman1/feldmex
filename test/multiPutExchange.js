const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("OptionsHandler");
const multiPutDelegate = artifacts.require("MultiPutDelegate");
const multiPutExchange = artifacts.require("MultiPutExchange");
const mPutHelper = artifacts.require("mPutHelper");
const mOrganizer = artifacts.require("mOrganizer");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");
const BN = web3.utils.BN;

const helper = require("../helper/helper.js");


const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
var maturity = 100;
var amount = 10;
var maxIterations = 5;



contract('multi put exchange', function(accounts){

	var deployerAccount = accounts[0];

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		multiPutDelegateInstance =  await multiPutDelegate.new();
		mPutHelperInstance = await mPutHelper.new(feeOracleInstance.address, multiPutDelegateInstance.address);
		mOrganizerInstance = await mOrganizer.new(/*this param does not matter so we will just add the default address*/accounts[0], mPutHelperInstance.address, accounts[0]);
		optionsInstance = await options.new(oracleInstance.address, asset1.address, asset2.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
		await mOrganizerInstance.deployPutExchange(optionsInstance.address);
		multiPutExchangeInstance = await multiPutExchange.at(await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 1));

		asset2SubUnitsBN = (new BN("10")).pow(await asset2.decimals());
		asset2SubUnits = asset2SubUnitsBN.toString();
	});

	async function depositFunds(to, amount, exchange){
		if (amount > 0)
			await asset2.transfer(exchange ? multiPutExchangeInstance.address : optionsInstance.address, amount, {from: deployerAccount});
		if (exchange)
			return multiPutExchangeInstance.depositFunds(to);
		else
			return optionsInstance.depositFunds(to);
	}

	async function postOrder(maturity, legsHash, price, amount, index, params) {
		var balance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		if (typeof params.gasPrice === "undefined") params.gasPrice = 20000000000; //20 gwei
		var postOrderFee = new web3.utils.BN(await feeOracleInstance.multiLegExchangeFlatEtherFee());
		params.value = postOrderFee.toNumber();
		amount = asset2SubUnitsBN.mul(new BN(amount)).toString();
		var rec = await multiPutExchangeInstance.postOrder(maturity, legsHash, price, amount, index, params);
		var txFee = new web3.utils.BN(rec.receipt.gasUsed * params.gasPrice);
		var newBalance = new web3.utils.BN(await web3.eth.getBalance(params.from));
		var result = txFee.add(newBalance);
		assert.equal(result.cmp(balance.sub(postOrderFee)), 0, "correct fees paid");
	}


	it('creates positions with the correct collateral requirements', async () => {
		putStrikes = [asset2SubUnitsBN.mul(new BN(10)), asset2SubUnitsBN.mul(new BN(20))];
		putAmounts = [3, -1];
		//these calculations would be different if we had different values in the above arrays
		maxStrikeAssetDebtor = (new BN(putAmounts[0])).mul(putStrikes[0]).add((new BN(putAmounts[1])).mul(putStrikes[1]));
		maxStrikeAssetHolder = (new BN(putAmounts[1])).mul(putStrikes[0].sub(putStrikes[1]));
		//reflate putStrikes
		putStrikes = putStrikes.map(x => x.toString());

		rec = await multiPutExchangeInstance.addLegHash(putStrikes, putAmounts);
		assert.equal(rec.logs[0].event, "legsHashCreated", "correct event emmited");
		legsHash = rec.logs[0].args.legsHash;
		position = await multiPutExchangeInstance.positions(legsHash);
		//check value of arrays
		assert.equal(position.putStrikes+'', putStrikes+'', "correct put strikes in position info");
		assert.equal(position.putAmounts+'', putAmounts+'', "correct put amounts in position info");
		//check value of collateral requirements
		assert.equal(position.maxStrikeAssetDebtor, maxStrikeAssetDebtor.toString(), "correct value for maxStrikeAssetDebtor");
		assert.equal(position.maxStrikeAssetHolder, maxStrikeAssetHolder.toString(), "correct value for maxStrikeAssetHolder");
		maxStrikeAssetDebtor = maxStrikeAssetDebtor.toNumber();
		maxStrikeAssetHolder = maxStrikeAssetHolder.toNumber();
	});


	it('posts orders with correct collateral requirements index 0', async () => {
		maturity++;
		price = 6;
		//add strikes
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});

		await depositFunds(deployerAccount, amount*(maxStrikeAssetHolder+price), true);
		await depositFunds(accounts[1], amount*(maxStrikeAssetDebtor-price), false);
		//we will attempt to trade with 
		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		await multiPutExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), amount*(maxStrikeAssetHolder+price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 0, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = -2;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetHolder+secondPrice), true);
		await depositFunds(accounts[1], amount*(maxStrikeAssetDebtor-secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 0, {from: deployerAccount});

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiPutExchangeInstance.marketSell(maturity, legsHash, price, asset2SubUnitsBN.mul(new BN(amount-5)).toString(), maxIterations, {from: accounts[1]});
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		headNode = await multiPutExchangeInstance.linkedNodes(listHead);
		headOffer = await multiPutExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), asset2SubUnitsBN.mul(new BN(5)).toString(), "correct amount left after market sell");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN((amount-5)*putAmounts[i])).toString(), "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN(-(amount-5)*putAmounts[i])).toString(), "correct put balance first account");
		}

		assert.equal((await optionsInstance.strikeAssetDeposits(accounts[1])).toNumber(), 5*(maxStrikeAssetDebtor-price) + amount*(maxStrikeAssetDebtor-secondPrice) , "correct strike asset balance after market sell");

		await multiPutExchangeInstance.marketSell(maturity, legsHash, secondPrice, asset2SubUnitsBN.mul(new BN(5+amount)).toString(), maxIterations, {from: accounts[1]});

		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 0);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(), 
				asset2SubUnitsBN.mul(new BN(2*amount*putAmounts[i])).toString(), "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN(-2*amount*putAmounts[i])).toString(), "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toString(), "0", "correct strike asset balance after all orders");

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(accounts[1])).toString(), "0", "correct strike asset balance after all orders");

	});


	it('posts orders with correct collateral requirements index 1', async () => {
		maturity++;
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});
		price = -2;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetDebtor-price), true);
		await depositFunds(accounts[1], amount*(maxStrikeAssetHolder+price), false);
		//we will attempt to trade with
		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), 0, "correct strike asset balance after posting order");

		//cancels order correctly
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		await multiPutExchangeInstance.cancelOrder(listHead, {from: deployerAccount});
		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), amount*(maxStrikeAssetDebtor-price), "correct strike asset balance after cancling order");


		await postOrder(maturity, legsHash, price, amount, 1, {from: deployerAccount});
		//deposit more funds to load a second order
		secondPrice = 6;
		await depositFunds(deployerAccount, amount*(maxStrikeAssetDebtor-secondPrice), true);
		await depositFunds(accounts[1], amount*(maxStrikeAssetHolder+secondPrice), false);
		await postOrder(maturity, legsHash, secondPrice, amount, 1, {from: deployerAccount});

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toNumber(), 0, "correct strike asset balance after posting second order");
		
		await multiPutExchangeInstance.marketBuy(maturity, legsHash, price, asset2SubUnitsBN.mul(new BN(amount-5)).toString(), maxIterations, {from: accounts[1]});
		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		headNode = await multiPutExchangeInstance.linkedNodes(listHead);
		headOffer = await multiPutExchangeInstance.offers(headNode.hash);
		assert.equal(headOffer.amount.toString(), asset2SubUnitsBN.mul(new BN(5)).toString(), "correct amount left after market buy");
		assert.equal(headOffer.price.toNumber(), price, "correct price of the head offer");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN(-(amount-5)*putAmounts[i])).toString(), "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN((amount-5)*putAmounts[i])).toString(), "correct put balance first account");
		}

		assert.equal((await optionsInstance.strikeAssetDeposits(accounts[1])).toNumber(), Math.max(5*(maxStrikeAssetHolder+price), 0)+Math.max((5-amount)*(maxStrikeAssetHolder+price), 0)
			+amount*(maxStrikeAssetHolder+secondPrice), "correct strike asset balance after market buy");

		await multiPutExchangeInstance.marketBuy(maturity, legsHash, secondPrice, asset2SubUnitsBN.mul(new BN(5+amount)).toString(), maxIterations, {from: accounts[1]});

		listHead = await multiPutExchangeInstance.listHeads(maturity, legsHash, 1);
		assert.equal(listHead, defaultBytes32, "correct list head");

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN(-2*amount*putAmounts[i])).toString(), "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				asset2SubUnitsBN.mul(new BN(2*amount*putAmounts[i])).toString(), "correct put balance first account");
		}

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(deployerAccount)).toString(), "0", "correct strike asset balance after all orders");

		assert.equal((await multiPutExchangeInstance.strikeAssetDeposits(accounts[1])).toString(), "0", "correct strike asset balance after all orders");

	});

	it('uses max iterations limit index 0', async () => {
		maturity++;
		price = 300000;
		maxIterations = 5;
		amount = maxIterations+2;
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});
		await depositFunds(deployerAccount, amount*(maxStrikeAssetHolder+price), true);
		await depositFunds(accounts[1], amount*(maxStrikeAssetDebtor-price), false);

		for (let i = 0; i < amount; i++)
			await multiPutExchangeInstance.postOrder(maturity, legsHash, price, 1, 0, {from: deployerAccount});

		var prevBalanceAct1 = await optionsInstance.strikeAssetDeposits(accounts[1]);

		await multiPutExchangeInstance.marketSell(maturity, legsHash, price, asset2SubUnitsBN.mul(new BN(maxIterations+2)).toString(), maxIterations, {from: accounts[1]});

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(),
				maxIterations*putAmounts[i] + "" , "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				-maxIterations*putAmounts[i] + "", "correct put balance first account");
		}
		var balanceAct1 = await optionsInstance.strikeAssetDeposits(accounts[1]);
		var totalReq = Math.ceil(maxStrikeAssetDebtor/asset2SubUnits) + Math.ceil(maxStrikeAssetHolder/asset2SubUnits);
		var reqHolder = Math.floor( (maxStrikeAssetHolder + price) / asset2SubUnits);
		var reqDebtor = totalReq - reqHolder;
		reqHolder *= maxIterations;
		reqDebtor *= maxIterations;
		reqDebtor -= Math.floor(maxIterations * (maxStrikeAssetDebtor%asset2SubUnits) / asset2SubUnits);
		assert.equal(prevBalanceAct1.sub(balanceAct1).toString(), reqDebtor, "corrected change account 1 in claimed Tokens in options handler contract");
	});

	it('uses max iterations limit index 1', async () => {
		maturity++;
		price = 6;
		maxIterations = 5;
		amount = maxIterations+2;
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[0], 0, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: deployerAccount});
		await optionsInstance.addStrike(maturity, putStrikes[1], 1, {from: accounts[1]});
		await depositFunds(accounts[1], amount*(maxStrikeAssetHolder+price), true);
		await depositFunds(deployerAccount, amount*(maxStrikeAssetDebtor-price), false);

		for (let i = 0; i < amount; i++)
			await multiPutExchangeInstance.postOrder(maturity, legsHash, price, 1, 1, {from: deployerAccount});

		var prevBalanceAct1 = await optionsInstance.strikeAssetDeposits(accounts[1]);

		await multiPutExchangeInstance.marketBuy(maturity, legsHash, price, asset2SubUnitsBN.mul(new BN(maxIterations+2)).toString(), maxIterations, {from: accounts[1]});

		//check put balances
		for (var i = 0; i < putStrikes.length; i++){
			assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, putStrikes[i], false)).toString(),
				-maxIterations*putAmounts[i] + "" , "correct put balance deployer account");
			assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, putStrikes[i], false)).toString(),
				maxIterations*putAmounts[i] + "", "correct put balance first account");
		}
		var balanceAct1 = await optionsInstance.strikeAssetDeposits(accounts[1]);
		var totalReq = Math.ceil(maxStrikeAssetDebtor/asset2SubUnits) + Math.ceil(maxStrikeAssetHolder/asset2SubUnits);
		var reqDebtor = Math.floor( (maxStrikeAssetDebtor - price) / asset2SubUnits);
		var reqHolder = totalReq - reqDebtor;
		reqHolder *= maxIterations;
		reqDebtor *= maxIterations;
		reqHolder -= Math.floor(maxIterations * (maxStrikeAssetHolder%asset2SubUnits) / asset2SubUnits);
		assert.equal(prevBalanceAct1.sub(balanceAct1).toString(), reqHolder, "corrected change account 1 in claimed Tokens in options handler contract");
	});

});