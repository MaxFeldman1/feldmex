const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const container = artifacts.require("container");
const organiser = artifacts.require("organiser");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");
const cHelper = artifacts.require("cHelper");
const orcHelper = artifacts.require("orcHelper");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const mOrganizer = artifacts.require("mOrganizer");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const ERC20FeldmexOption = artifacts.require("ERC20FeldmexOption");
const feeOracle = artifacts.require("feeOracle");

const nullAddress = "0x0000000000000000000000000000000000000000";

var maturity = 100;
var strike = 1000;

contract('ERC20FeldmexOptions', async function(accounts){

	deployerAccount = accounts[0];

	it('transfers funds', async () => {
		tokenInstance = await underlyingAsset.new(0);
		tokenSubUnits = Math.pow(10, (await tokenInstance.decimals()).toNumber());
		strikeAssetInstance = await underlyingAsset.new(0);
		tokenSubUnits = Math.pow(10, (await strikeAssetInstance.decimals()).toNumber());
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feeOracleInstance = await feeOracle.new();
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address,  /*this param does not matter*/accounts[0], assignOptionsDelegateInstance.address, feeOracleInstance.address);
		await feldmexERC20HelperInstance.deployNew(optionsInstance.address, maturity, strike, true);
		await feldmexERC20HelperInstance.deployNew(optionsInstance.address, maturity, strike, false);
		feldmexERC20CallInstance = await ERC20FeldmexOption.at(await feldmexERC20HelperInstance.callAddresses(optionsInstance.address, maturity, strike));
		feldmexERC20PutInstance = await ERC20FeldmexOption.at(await feldmexERC20HelperInstance.putAddresses(optionsInstance.address, maturity, strike));
		assert.notEqual(feldmexERC20CallInstance.address, nullAddress, "feldmex call erc20 instance has non null address");
		assert.notEqual(feldmexERC20PutInstance.address, nullAddress, "feldmex put erc20 instance has non null address");
		assert.notEqual(feldmexERC20CallInstance.address, feldmexERC20PutInstance.address, "feldmex call and put erc 20 instances have different addresses");

		depositFunds = async (sats, sc, to) => {
			if (sats > 0)
				await tokenInstance.transfer(optionsInstance.address, sats, {from: deployerAccount});
			if (sc > 0)
				await strikeAssetInstance.transfer(optionsInstance.address, sc, {from: deployerAccount});
			return optionsInstance.depositFunds(to);
		};
	});

	it('transfers call options', async () => {
		amount = 20;
		await depositFunds(tokenSubUnits * amount, 0, deployerAccount);
		await optionsInstance.addStrike(maturity, strike, 0, {from: deployerAccount});
		await feldmexERC20CallInstance.transfer(accounts[1], amount, {from: deployerAccount});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toNumber(), -amount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toNumber(), amount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20CallInstance.balanceOf(deployerAccount)).toNumber(), 0, "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20CallInstance.balanceOf(accounts[1])).toNumber(), amount, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.viewClaimedTokens({from: deployerAccount})).toNumber(), 0, "correct balance of claimed tokens in the options handler for deployerAccount");
		secondAmount = 15;
		await feldmexERC20CallInstance.transfer(deployerAccount, secondAmount, {from: accounts[1]});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toNumber(), secondAmount-amount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toNumber(), amount-secondAmount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20CallInstance.balanceOf(deployerAccount)).toNumber(), 0, "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20CallInstance.balanceOf(accounts[1])).toNumber(), amount-secondAmount, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.viewClaimedTokens({from: deployerAccount})).toNumber(), secondAmount*tokenSubUnits, "correct balance of claimed tokens in the options handler for first account");
	});

	it('transfers put options', async () => {
		amount = 20;
		await depositFunds(0, strike * amount, deployerAccount);
		await feldmexERC20PutInstance.transfer(accounts[1], amount, {from: deployerAccount});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toNumber(), -amount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toNumber(), amount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20PutInstance.balanceOf(deployerAccount)).toNumber(), 0, "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20PutInstance.balanceOf(accounts[1])).toNumber(), amount, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.viewClaimedStable({from: deployerAccount})).toNumber(), 0, "correct balance of claimed tokens in the options handler for deployerAccount");
		secondAmount = 15;
		await feldmexERC20PutInstance.transfer(deployerAccount, secondAmount, {from: accounts[1]});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toNumber(), secondAmount-amount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toNumber(), amount-secondAmount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20PutInstance.balanceOf(deployerAccount)).toNumber(), 0, "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20PutInstance.balanceOf(accounts[1])).toNumber(), amount-secondAmount, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.viewClaimedStable({from: deployerAccount})).toNumber(), secondAmount*strike, "correct balance of claimed tokens in the options handler for first account");
	});

	it('approves spending of call options', async () => {
		await feldmexERC20CallInstance.approve(accounts[1], secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20CallInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount, "correct allowance");
	});

	it('approves spending of put options', async () => {
		await feldmexERC20PutInstance.approve(accounts[1], secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20PutInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount, "correct allowance");
	});

	//this test will fail if 'approves spending of call options' fails
	it('transfers call options from owner', async () => {
		thirdAmount = 7;
		prevDeployerBalance = (await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toNumber();
		await feldmexERC20CallInstance.transferFrom(deployerAccount, accounts[2], thirdAmount, {from: accounts[1]});

		assert.equal((await feldmexERC20CallInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount-thirdAmount, "correct allowance after transfer from");
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toNumber(), prevDeployerBalance-thirdAmount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[2], maturity, strike, true)).toNumber(), thirdAmount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20CallInstance.balanceOf(deployerAccount)).toNumber(), Math.max(prevDeployerBalance-thirdAmount, 0), "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20CallInstance.balanceOf(accounts[2])).toNumber(), thirdAmount, "correct balance in call erc20 wrapper instance for first account");
	});

	//this test will fail if 'approves spending of put options' fails
	it('transfers put options from owner', async () => {
		thirdAmount = 7;
		prevDeployerBalance = (await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toNumber();
		await feldmexERC20PutInstance.transferFrom(deployerAccount, accounts[2], thirdAmount, {from: accounts[1]});

		assert.equal((await feldmexERC20PutInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount-thirdAmount, "correct allowance after transfer from");
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toNumber(), prevDeployerBalance-thirdAmount, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[2], maturity, strike, false)).toNumber(), thirdAmount, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20PutInstance.balanceOf(deployerAccount)).toNumber(), Math.max(prevDeployerBalance-thirdAmount, 0), "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20PutInstance.balanceOf(accounts[2])).toNumber(), thirdAmount, "correct balance in call erc20 wrapper instance for first account");
	});

	it('cannot transfer/transferFrom calls without meeting safety requirements', async () => {
		//jeg vet ikke
		var caught = "not caught";
		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toNumber(), 0) + 1;
		assert.equal(await optionsInstance.containedStrikes(accounts[1], maturity, strike), false, "strike is not contained by first account");
		//add sufficient funds
		await depositFunds(amount*tokenSubUnits, 0, accounts[1]);
		try{
			await feldmexERC20CallInstance.transfer(deployerAccount, amount, {from: accounts[1]});
		} catch (err) {
			caught = "caught";
		}
		assert.equal(caught, "caught", "transfer failed");
		caught = "not caught";

		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toNumber(), 0) + 1;
		await depositFunds(amount*tokenSubUnits, 0, accounts[1]);
		await feldmexERC20CallInstance.approve(deployerAccount, amount, {from: accounts[1]});

		try{
			await feldmexERC20CallInstance.transferFrom(deployerAccount, amount, {from: accounts[1]});
		} catch (err) {
			caught = "caught";
		}

		assert.equal(caught, "caught", "transferFrom failed");
	});

	it('cannot transfer/transferFrom puts without meeting safety requirements', async () => {
		//jeg vet ikke
		var caught = "not caught";
		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toNumber(), 0) + 1;
		assert.equal(await optionsInstance.containedStrikes(accounts[1], maturity, strike), false, "strike is not contained by first account");
		//add sufficient funds
		await depositFunds(amount*tokenSubUnits, 0, accounts[1]);
		try{
			await feldmexERC20PutInstance.transfer(deployerAccount, amount, {from: accounts[1]});
		} catch (err) {
			caught = "caught";
		}
		assert.equal(caught, "caught", "transfer failed");
		caught = "not caught";

		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toNumber(), 0) + 1;
		await depositFunds(amount*tokenSubUnits, 0, accounts[1]);
		await feldmexERC20PutInstance.approve(deployerAccount, amount, {from: accounts[1]});

		try{
			await feldmexERC20PutInstance.transferFrom(deployerAccount, amount, {from: accounts[1]});
		} catch (err) {
			caught = "caught";
		}

		assert.equal(caught, "caught", "transferFrom failed");
	});

});