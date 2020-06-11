const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");
const container = artifacts.require("container");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");

const helper = require("../helper/helper.js");

contract('container', async function(accounts){

	deployerAccount = accounts[0];

	//before it is set the fee denominator has default value high enough that there is effectively no fee
	feeDenominator = Math.pow(2, 200);

	it('before each', async () => {
		tokenInstance = await underlyingAsset.new(0);
		strikeAssetInstance = await strikeAsset.new(0);
		oHelperInstance = await oHelper.new();
		eHelperInstance = await eHelper.new();
		containerInstance = await container.new(tokenInstance.address, strikeAssetInstance.address, oHelperInstance.address, eHelperInstance.address, 0, 0);
		await containerInstance.depOptions();
		await containerInstance.depExchange();
		assert.equal(await containerInstance.progress(), 2, "cotainer contract setup has been sucessfully completed");
		oracleInstance = await oracle.at(await containerInstance.oracleContract());
		optionsInstance = await options.at(await containerInstance.optionsContract());
		exchangeInstance = await exchange.at(await containerInstance.exchangeContract());
		satUnits = Math.pow(10, (await tokenInstance.decimals()).toNumber());
		scUnits = Math.pow(10, (await strikeAssetInstance.decimals()).toNumber());
	});


	it('implements erc20', async () => {
			//allows token transfer
		decimals = (await containerInstance.decimals()).toNumber()
		assert.equal(decimals, 4, "correct default decimal value");
		subUnits = Math.pow(10, decimals);
		totalSupply =  (await containerInstance.totalSupply()).toNumber();
		assert.equal(totalSupply, 1000000*subUnits, "correct default total supply");
		totalCoins = totalSupply/subUnits;
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), totalSupply, "deployerAccount initially holds all coins");
		transferAmount = 10 * subUnits;
		await containerInstance.transfer(accounts[1], transferAmount, {from: deployerAccount});
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), totalSupply-transferAmount, "sender balance reduced on transfer");
		assert.equal((await containerInstance.balanceOf(accounts[1])).toNumber(), transferAmount, "receiver balance credited on transfer");
		//test approval
		await containerInstance.approve(accounts[1], transferAmount, {from: deployerAccount});
		assert.equal((await containerInstance.allowance(deployerAccount, accounts[1])).toNumber(), transferAmount, "allowance set to expected value");
		await containerInstance.transferFrom(deployerAccount, accounts[2], transferAmount, {from: accounts[1]});
		assert.equal((await containerInstance.allowance(deployerAccount, accounts[1])).toNumber(), 0, "allowance decreaced");
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), totalSupply-2*transferAmount, "from account balance reduced by expected amount");
		assert.equal((await containerInstance.balanceOf(accounts[2])).toNumber(), transferAmount, "to account balane credited correct amount");
	});

	it('uses specific allowances and transferTokenOwnerFrom, autoClaim on', async () => {
		amount = 10 * subUnits;
		await containerInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await containerInstance.totalYield(accounts[2])).toNumber();
		initialDeployerSecondYield = (await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstFirstYield = (await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initialFirstSecondYield = (await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		await containerInstance.approveYieldOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await containerInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), amount, "specific allowance is correct");
		initalBalanceFirstAct = (await containerInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await containerInstance.balanceOf(deployerAccount)).toNumber();
		await containerInstance.transferTokenOwnerFrom(deployerAccount, accounts[1], amount, accounts[2], {from: accounts[1]});
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await containerInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await containerInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), 0, "specific allowance reduced correctly");
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond-amount, "totalYield decreaced for second account");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield, "yieldDistribution[token recipient][yield owner] remains the same");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield+amount, "yieldDistribution[first account][first account] increaced by correct amount");
	});

	it('uses transferTokenOwner, autoClaim on', async () => {
		amount = 10 * subUnits;
		await containerInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await containerInstance.totalYield(accounts[2])).toNumber();
		initialDeployerSecondYield = (await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstSecondYield = (await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		initialFirstFirstYield = (await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initalBalanceFirstAct = (await containerInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await containerInstance.balanceOf(deployerAccount)).toNumber();
		await containerInstance.transferTokenOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for deployer account");
		assert.equal((await containerInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the first account");
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond-amount, "totalYield correct for second account");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield, "yieldDistribution[token recipient][yield owner] remained the same");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield+amount, "yieldDistribution[first account][first account] increaced by amount");
	});

	it('sends and claims yield', async () => {
		amount = 10 * subUnits;
		initialYieldSecond = (await containerInstance.totalYield(accounts[2])).toNumber();
		initialYieldDeployer = (await containerInstance.totalYield(deployerAccount)).toNumber();
		initialDeployerDepoyer = (await containerInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber();
		initialDeployerSecond = (await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		await containerInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond+amount, "correct total yield for second account");
		assert.equal((await containerInstance.totalYield(deployerAccount)).toNumber(), initialYieldDeployer-amount, "correct total yield for deployer account");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber(), initialDeployerDepoyer-amount, "correct value of yieldDistribution[deployer][deployer]");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecond+amount, "correct value of yieldDistribution[deployer][second account] first pass");
		await containerInstance.claimYield(accounts[2], amount, {from: deployerAccount});
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "correct total yield for second account");
		assert.equal((await containerInstance.totalYield(deployerAccount)).toNumber(), initialYieldDeployer, "correct total yield for deployer account");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber(), initialDeployerDepoyer, "correct value of yieldDistribution[deployer][deployer]");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecond, "correct value of yieldDistribution[deployer][second account] second pass");
	});

	it('sets auto claim', async () => {
		amount = 10 * subUnits;
		assert.equal((await containerInstance.autoClaimYieldDisabled(deployerAccount)), false, "autoClaimYieldDisabled deployer is false by default");
		assert.equal(await containerInstance.autoClaimYieldDisabled(accounts[1]), false, "autoClaimYieldDisabled firstAccount is false by default");
		containerInstance.setAutoClaimYield({from: deployerAccount});
		await containerInstance.setAutoClaimYield({from: accounts[1]});
		assert.equal(await containerInstance.autoClaimYieldDisabled(deployerAccount), true, "autoClaimYieldDisabled deployer set to true");
		assert.equal(await containerInstance.autoClaimYieldDisabled(accounts[1]), true, "autoClaimYieldDisabled first account set to true");
	});

	it('uses transferTokenOwner, autoClaim off', async () => {
		amount = 10 * subUnits;
		res = await containerInstance.autoClaimYieldDisabled(accounts[1]);
		if (!res) await containerInstance.setAutoClaimYield({from: accounts[1]});
		await containerInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await containerInstance.totalYield(accounts[2])).toNumber();
		initialYieldFirst = (await containerInstance.totalYield(accounts[1])).toNumber();
		initialDeployerSecondYield = (await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstSecondYield = (await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		initialFirstFirstYield = (await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initalBalanceFirstAct = (await containerInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await containerInstance.balanceOf(deployerAccount)).toNumber();
		await containerInstance.transferTokenOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await containerInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await containerInstance.totalYield(accounts[1])).toNumber(), initialYieldFirst, "totalYield[first account] remained the same");
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "totalYield[second account] remained the same");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield+amount, "yieldDistribution[token recipient][yield owner] increaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield, "yieldDistribution[first account][first account] remains the same");
	});

	it('uses specific allowances and transferTokenOwnerFrom, autoClaim off', async () => {
		amount = 10 * subUnits;
		res = await containerInstance.autoClaimYieldDisabled(accounts[1]);
		if (!res) await containerInstance.setAutoClaimYield({from: accounts[1]});
		await containerInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldFirst = (await containerInstance.totalYield(accounts[1])).toNumber();
		initialYieldSecond = (await containerInstance.totalYield(accounts[2])).toNumber();
		initialDeployerYield = (await containerInstance.totalYield(deployerAccount)).toNumber();
		initialDeployerSecondYield = (await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstFirstYield = (await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initialFirstSecondYield = (await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		await containerInstance.approveYieldOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await containerInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), amount, "specific allowance is correct");
		initalBalanceFirstAct = (await containerInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await containerInstance.balanceOf(deployerAccount)).toNumber();
		await containerInstance.transferTokenOwnerFrom(deployerAccount, accounts[1], amount, accounts[2], {from: accounts[1]});
		assert.equal((await containerInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await containerInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await containerInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), 0, "specific allowance reduced correctly");
		assert.equal((await containerInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "totalYield constant for second account");
		assert.equal((await containerInstance.totalYield(accounts[1])).toNumber(), initialYieldFirst, "totalYield constant for first account");
		assert.equal((await containerInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield+amount, "yieldDistribution[token recipient][yield owner] increaced by amount");
		assert.equal((await containerInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield, "yieldDistribution[first account][first account] remains the same");
	});

	it('changes the fee', () => {
		nonDeployer = accounts[1];
		return containerInstance.setFee(1500, {from: deployerAccount}).then(() => {
			feeDenominator = 1500;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OK", "Successfully changed the fee");
			return containerInstance.setFee(400, {from: deployerAccount});
		}).then(() => {
			feeDenominator = 400;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because fee was too high");
			return containerInstance.setFee(1800, {from: nonDeployer});
		}).then(() => {
			feeDenominator = 1800;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because the sender was not the deployer");
		});
	});

	it('gathers yeild from fees generated in options contract', async () => {
		await oracleInstance.set(1);
		maturity = (await web3.eth.getBlock('latest')).timestamp;
		strike = 100
		//set spot very low
		amount = 1000;
		expectedTransfer = amount * satUnits;
		expectedFee = parseInt(expectedTransfer/feeDenominator);
		await tokenInstance.approve(optionsInstance.address, expectedTransfer, {from: deployerAccount});
		await helper.advanceTime(2);
		optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
		await optionsInstance.addStrike(maturity, strike, {from: accounts[2]});
		await optionsInstance.mintCall(accounts[1], accounts[2], maturity, 100, amount, expectedTransfer, {from: deployerAccount});
		await optionsInstance.claim(maturity, {from: accounts[1]});
		await optionsInstance.claim(maturity, {from: accounts[2]});
		await containerInstance.contractClaimDividend();
		assert.equal((await tokenInstance.balanceOf(containerInstance.address)).toNumber(), expectedFee, "balance of contract is the same as expectedFee");
		//size of contractBalanceUnderlying array is 2, get the last index
		assert.equal((await containerInstance.contractBalanceUnderlying(1)).toNumber(), expectedFee, "balance of contract reflected in contractBalanceUnderlying");
		//size of contractBalanceStrike array is 2, get the last index
		assert.equal((await containerInstance.contractBalanceStrike(1)).toNumber(), 0, "no fee revenue has been recorded for the strikeAsset");
		deployerYield = (await containerInstance.totalYield(deployerAccount)).toNumber();
		firstAccountYield = (await containerInstance.totalYield(accounts[1])).toNumber();
		secondAccountYield = (await containerInstance.totalYield(accounts[2])).toNumber();
		containerInstance.claimDividend({from: deployerAccount});
		containerInstance.claimDividend({from: accounts[1]});
		await containerInstance.claimDividend({from: accounts[2]});
		deployerUnderlyingBalance = (await containerInstance.viewUnderlyingAssetBalance({from: deployerAccount})).toNumber();
		assert.equal(deployerUnderlyingBalance, Math.floor(expectedFee*(deployerYield)/totalSupply), "correct divident paid to deployerAccount");
		firstUnderlyingBalance = (await containerInstance.viewUnderlyingAssetBalance({from: accounts[1]})).toNumber();
		assert.equal(firstUnderlyingBalance, Math.floor(expectedFee*(firstAccountYield)/totalSupply), "correct divident paid to accounts[1]");
		secondUnderlyingBalance = (await containerInstance.viewUnderlyingAssetBalance({from: accounts[2]})).toNumber();
		assert.equal(secondUnderlyingBalance, Math.floor(expectedFee*(secondAccountYield)/totalSupply), "correct divident paid to accounts[2]");
	});

	it('withdraws funds', async () => {
		assert.notEqual(typeof(deployerUnderlyingBalance), "undefined", "we have balance of deployer account");
		assert.notEqual(typeof(firstUnderlyingBalance), "undefined", "we have balance of first account");
		assert.notEqual(typeof(secondUnderlyingBalance), "undefined", "we have balance of second account");
		//deployer account is the only account with a balance of underlyingAsset held outside of the container contract
		llg = deployerUnderlyingBalance;
		deployerUnderlyingBalance += (await tokenInstance.balanceOf(deployerAccount)).toNumber();
		await containerInstance.withdrawFunds({from: deployerAccount});
		assert.equal((await tokenInstance.balanceOf(deployerAccount)).toNumber(), deployerUnderlyingBalance, "correct amount of funds credited to deployerAccount");
		assert.equal((await containerInstance.viewUnderlyingAssetBalance({from: deployerAccount})).toNumber(), 0, "correct amount of deployerAccount's funds remain in container contract");
		await containerInstance.withdrawFunds({from: accounts[1]});
		assert.equal((await tokenInstance.balanceOf(accounts[1])).toNumber(), firstUnderlyingBalance, "correct amount of funds credited to first account");
		assert.equal((await containerInstance.viewUnderlyingAssetBalance({from: accounts[1]})).toNumber(), 0, "correct amount of first account's funds remain in container contract");
		await containerInstance.withdrawFunds({from: accounts[2]});
		assert.equal((await tokenInstance.balanceOf(accounts[2])).toNumber(), secondUnderlyingBalance, "correct amount of funds credited to second account");
		assert.equal((await containerInstance.viewUnderlyingAssetBalance({from: accounts[2]})).toNumber(), 0, "correct amount of second account's funds remain in container contract");
	});

	it('grants fee immunity', async () => {
		strike = 10;
		spot = strike+10;
		//strike*=satUnits;
		//spot*=satUnits;
		await oracleInstance.set(spot);
		maturity = (await web3.eth.getBlock('latest')).timestamp;
		maxTransfer = satUnits*amount;
		//wait one second to allow for maturity to pass
		await helper.advanceTime(1);
		await tokenInstance.approve(optionsInstance.address, maxTransfer, {from: deployerAccount});
		assert.equal((await tokenInstance.balanceOf(deployerAccount)).toNumber() >= maxTransfer, true, "balance is large enough");
		optionsInstance.addStrike(maturity, strike, {from: deployerAccount});
		optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
		await optionsInstance.mintCall(deployerAccount, accounts[1], maturity, strike, amount, maxTransfer, {from: deployerAccount});
		feeDenominator = 1000;
		await containerInstance.setFee(1000, {from: deployerAccount});
		prevBalance = (await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber();
		await containerInstance.changeFeeStatus(accounts[1], {from: deployerAccount});
		assert.equal(await optionsInstance.feeImmunity(accounts[1]), true, "fee immunity granted to receiver account");
		await optionsInstance.claim(maturity, {from: accounts[1]});
		assert.equal((await optionsInstance.viewClaimedTokens({from: accounts[1]})).toNumber(), prevBalance + Math.floor(satUnits*amount*(spot-strike)/spot), "No fee charged on first account's call to options.claim");
		await containerInstance.changeFeeStatus(accounts[1], {from: deployerAccount});
		assert.equal(await optionsInstance.feeImmunity(accounts[1]), false, "fee immunity revoked for receiver account");
		maturity++;
		maxTransfer = amount*strike;
		helper.advanceTime(1);
		await strikeAssetInstance.approve(optionsInstance.address, maxTransfer, {from: deployerAccount});
		optionsInstance.addStrike(maturity, strike, {from: deployerAccount});
		optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
		await optionsInstance.mintPut(accounts[1], deployerAccount, maturity, strike, amount, maxTransfer, {from: deployerAccount});
		prevBalance = (await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber();
		//option expired worthless first account gets back all collateral
		await optionsInstance.claim(maturity, {from: accounts[1]});
		assert.equal((await optionsInstance.viewClaimedStable({from: accounts[1]})).toNumber(), prevBalance+maxTransfer-Math.floor(maxTransfer/feeDenominator), "fee is now charged again");
	});
});