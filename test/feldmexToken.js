const feldmexToken = artifacts.require("FeldmexToken");

const helper = require("../helper/helper.js");

const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';


contract('Feldmex Token', async function(accounts){

	deployerAccount = accounts[0];

	it('before each', async () => {
		feldmexTokenInstance = await feldmexToken.new();
		decimals = (await feldmexTokenInstance.decimals()).toNumber()
		subUnits = Math.pow(10, decimals);
		totalSupply =  (await feldmexTokenInstance.totalSupply()).toNumber();
	});


	it('implements erc20', async () => {
		assert.equal(totalSupply, 1000000*subUnits, "correct default total supply");
		totalCoins = totalSupply/subUnits;
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), totalSupply, "deployerAccount initially holds all coins");
		transferAmount = 10 * subUnits;
		await feldmexTokenInstance.transfer(accounts[1], transferAmount, {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), totalSupply-transferAmount, "sender balance reduced on transfer");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[1])).toNumber(), transferAmount, "receiver balance credited on transfer");
		//test approval
		await feldmexTokenInstance.approve(accounts[1], transferAmount, {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.allowance(deployerAccount, accounts[1])).toNumber(), transferAmount, "allowance set to expected value");
		await feldmexTokenInstance.transferFrom(deployerAccount, accounts[2], transferAmount, {from: accounts[1]});
		assert.equal((await feldmexTokenInstance.allowance(deployerAccount, accounts[1])).toNumber(), 0, "allowance decreaced");
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), totalSupply-2*transferAmount, "from account balance reduced by expected amount");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[2])).toNumber(), transferAmount, "to account balane credited correct amount");
	});

	it('uses specific allowances and transferTokenOwnerFrom, autoClaim on', async () => {
		amount = 10 * subUnits;
		await feldmexTokenInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await feldmexTokenInstance.totalYield(accounts[2])).toNumber();
		initialDeployerSecondYield = (await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstFirstYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initialFirstSecondYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		await feldmexTokenInstance.approveYieldOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), amount, "specific allowance is correct");
		initalBalanceFirstAct = (await feldmexTokenInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber();
		await feldmexTokenInstance.transferTokenOwnerFrom(deployerAccount, accounts[1], amount, accounts[2], {from: accounts[1]});
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await feldmexTokenInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), 0, "specific allowance reduced correctly");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond-amount, "totalYield decreaced for second account");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield, "yieldDistribution[token recipient][yield owner] remains the same");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield+amount, "yieldDistribution[first account][first account] increaced by correct amount");
	});

	it('uses transferTokenOwner, autoClaim on', async () => {
		amount = 10 * subUnits;
		await feldmexTokenInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await feldmexTokenInstance.totalYield(accounts[2])).toNumber();
		initialDeployerSecondYield = (await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstSecondYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		initialFirstFirstYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initalBalanceFirstAct = (await feldmexTokenInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber();
		await feldmexTokenInstance.transferTokenOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for deployer account");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the first account");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond-amount, "totalYield correct for second account");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield, "yieldDistribution[token recipient][yield owner] remained the same");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield+amount, "yieldDistribution[first account][first account] increaced by amount");
	});

	it('sends and claims yield', async () => {
		amount = 10 * subUnits;
		initialYieldSecond = (await feldmexTokenInstance.totalYield(accounts[2])).toNumber();
		initialYieldDeployer = (await feldmexTokenInstance.totalYield(deployerAccount)).toNumber();
		initialDeployerDepoyer = (await feldmexTokenInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber();
		initialDeployerSecond = (await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		await feldmexTokenInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond+amount, "correct total yield for second account");
		assert.equal((await feldmexTokenInstance.totalYield(deployerAccount)).toNumber(), initialYieldDeployer-amount, "correct total yield for deployer account");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber(), initialDeployerDepoyer-amount, "correct value of yieldDistribution[deployer][deployer]");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecond+amount, "correct value of yieldDistribution[deployer][second account] first pass");
		await feldmexTokenInstance.claimYield(accounts[2], amount, {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "correct total yield for second account");
		assert.equal((await feldmexTokenInstance.totalYield(deployerAccount)).toNumber(), initialYieldDeployer, "correct total yield for deployer account");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, deployerAccount)).toNumber(), initialDeployerDepoyer, "correct value of yieldDistribution[deployer][deployer]");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecond, "correct value of yieldDistribution[deployer][second account] second pass");
	});

	it('sets auto claim', async () => {
		amount = 10 * subUnits;
		assert.equal((await feldmexTokenInstance.autoClaimYieldDisabled(deployerAccount)), false, "autoClaimYieldDisabled deployer is false by default");
		assert.equal(await feldmexTokenInstance.autoClaimYieldDisabled(accounts[1]), false, "autoClaimYieldDisabled firstAccount is false by default");
		feldmexTokenInstance.setAutoClaimYield({from: deployerAccount});
		await feldmexTokenInstance.setAutoClaimYield({from: accounts[1]});
		assert.equal(await feldmexTokenInstance.autoClaimYieldDisabled(deployerAccount), true, "autoClaimYieldDisabled deployer set to true");
		assert.equal(await feldmexTokenInstance.autoClaimYieldDisabled(accounts[1]), true, "autoClaimYieldDisabled first account set to true");
	});

	it('uses transferTokenOwner, autoClaim off', async () => {
		amount = 10 * subUnits;
		res = await feldmexTokenInstance.autoClaimYieldDisabled(accounts[1]);
		if (!res) await feldmexTokenInstance.setAutoClaimYield({from: accounts[1]});
		await feldmexTokenInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldSecond = (await feldmexTokenInstance.totalYield(accounts[2])).toNumber();
		initialYieldFirst = (await feldmexTokenInstance.totalYield(accounts[1])).toNumber();
		initialDeployerSecondYield = (await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstSecondYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		initialFirstFirstYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initalBalanceFirstAct = (await feldmexTokenInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber();
		await feldmexTokenInstance.transferTokenOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[1])).toNumber(), initialYieldFirst, "totalYield[first account] remained the same");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "totalYield[second account] remained the same");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield+amount, "yieldDistribution[token recipient][yield owner] increaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield, "yieldDistribution[first account][first account] remains the same");
	});

	it('uses specific allowances and transferTokenOwnerFrom, autoClaim off', async () => {
		amount = 10 * subUnits;
		res = await feldmexTokenInstance.autoClaimYieldDisabled(accounts[1]);
		if (!res) await feldmexTokenInstance.setAutoClaimYield({from: accounts[1]});
		await feldmexTokenInstance.sendYield(accounts[2], amount, {from: deployerAccount});
		initialYieldFirst = (await feldmexTokenInstance.totalYield(accounts[1])).toNumber();
		initialYieldSecond = (await feldmexTokenInstance.totalYield(accounts[2])).toNumber();
		initialDeployerYield = (await feldmexTokenInstance.totalYield(deployerAccount)).toNumber();
		initialDeployerSecondYield = (await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber();
		initialFirstFirstYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber();
		initialFirstSecondYield = (await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber();
		await feldmexTokenInstance.approveYieldOwner(accounts[1], amount, accounts[2], {from: deployerAccount});
		assert.equal((await feldmexTokenInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), amount, "specific allowance is correct");
		initalBalanceFirstAct = (await feldmexTokenInstance.balanceOf(accounts[1])).toNumber();
		initalBalanceDeployer = (await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber();
		await feldmexTokenInstance.transferTokenOwnerFrom(deployerAccount, accounts[1], amount, accounts[2], {from: accounts[1]});
		assert.equal((await feldmexTokenInstance.balanceOf(deployerAccount)).toNumber(), initalBalanceDeployer-amount, "correct token balance for the sender");
		assert.equal((await feldmexTokenInstance.balanceOf(accounts[1])).toNumber(), initalBalanceFirstAct+amount, "correct token balance for the receiver");
		assert.equal((await feldmexTokenInstance.specificAllowance(deployerAccount, accounts[1], accounts[2])).toNumber(), 0, "specific allowance reduced correctly");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[2])).toNumber(), initialYieldSecond, "totalYield constant for second account");
		assert.equal((await feldmexTokenInstance.totalYield(accounts[1])).toNumber(), initialYieldFirst, "totalYield constant for first account");
		assert.equal((await feldmexTokenInstance.yieldDistribution(deployerAccount, accounts[2])).toNumber(), initialDeployerSecondYield-amount, "yieldDistribution[deployer][second account] decreaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[2])).toNumber(), initialFirstSecondYield+amount, "yieldDistribution[token recipient][yield owner] increaced by amount");
		assert.equal((await feldmexTokenInstance.yieldDistribution(accounts[1], accounts[1])).toNumber(), initialFirstFirstYield, "yieldDistribution[first account][first account] remains the same");
	});

	it('gathers yield from fees generated in first options contract', async () => {
		maturity = (await web3.eth.getBlock('latest')).timestamp;
		strike = 100
		amount = web3.utils.toWei('0.000007', 'ether');
		web3.eth.sendTransaction({to: feldmexTokenInstance.address, from: deployerAccount, value: amount});
		await feldmexTokenInstance.contractClaimDividend();
		assert.equal(await web3.eth.getBalance(feldmexTokenInstance.address), amount, "balance of contract is the transfer amount");
		assert.equal((await feldmexTokenInstance.contractEtherReceived(1)).cmp(new web3.utils.BN(amount, 10)), 0, "correct balance recorded inside contract internal records");

		amount = new web3.utils.BN(amount);
		totalSupply = new web3.utils.BN(totalSupply);

		deployerYield = await feldmexTokenInstance.totalYield(deployerAccount);
		firstAccountYield = await feldmexTokenInstance.totalYield(accounts[1]);
		secondAccountYield = await feldmexTokenInstance.totalYield(accounts[2]);
		gasPrice = web3.utils.toWei('20', 'gwei');
		prevBalanceDeployer = new web3.utils.BN(await web3.eth.getBalance(deployerAccount));
		prevBalanceFirst = new web3.utils.BN(await web3.eth.getBalance(accounts[1]));
		prevBalanceSecond = new web3.utils.BN(await web3.eth.getBalance(accounts[2]));
		rec = await feldmexTokenInstance.claimDividend({from: deployerAccount, gasPrice});
		txFeeDeployer = new web3.utils.BN((rec.receipt.gasUsed * parseInt(gasPrice))+"");
		rec = await feldmexTokenInstance.claimDividend({from: accounts[1], gasPrice});
		txFeeFirst = new web3.utils.BN((rec.receipt.gasUsed * parseInt(gasPrice))+"");
		rec = await feldmexTokenInstance.claimDividend({from: accounts[2], gasPrice});
		txFeeSecond = new web3.utils.BN((rec.receipt.gasUsed * parseInt(gasPrice))+"");

		newBalanceDeployer = new web3.utils.BN(await web3.eth.getBalance(deployerAccount));
		newBalanceFirst = new web3.utils.BN(await web3.eth.getBalance(accounts[1]));
		newBalanceSecond = new web3.utils.BN(await web3.eth.getBalance(accounts[2]));

		assert.equal(newBalanceDeployer.add(txFeeDeployer).sub(prevBalanceDeployer).cmp(amount.mul(deployerYield).div(totalSupply)), 0, "correct ether dividend for deployer account");
		assert.equal(newBalanceFirst.add(txFeeFirst).sub(prevBalanceFirst).cmp(amount.mul(firstAccountYield).div(totalSupply)), 0, "correct ether dividend for first account");
		assert.equal(newBalanceSecond.add(txFeeSecond).sub(prevBalanceSecond).cmp(amount.mul(secondAccountYield).div(totalSupply)), 0, "correct ether dividend for second account");

	});

});