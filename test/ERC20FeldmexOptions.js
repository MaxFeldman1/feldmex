const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const container = artifacts.require("container");
const containerDeveloper = artifacts.require("containerDeveloper");
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
const feldmexToken = artifacts.require("FeldmexToken");
const detachedOption = artifacts.require("detachedOption");
const BN = web3.utils.BN;

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";

var maturity = 100;
var strike = 1000000;

contract('ERC20FeldmexOptions', async function(accounts){

	deployerAccount = accounts[0];

	it('transfers funds', async () => {
		tokenInstance = await token.new(0);
		tokenSubUnitsBN = (new BN(10)).pow(await tokenInstance.decimals());
		strikeAssetInstance = await token.new(0);
		tokenSubUnits = Math.pow(10, (await strikeAssetInstance.decimals()).toNumber());
		strikeAssetSubUnits = (new BN("10")).pow(await strikeAssetInstance.decimals());
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address,  /*this param does not matter*/accounts[0], assignOptionsDelegateInstance.address, feeOracleInstance.address);
		await feldmexERC20HelperInstance.deployNew(optionsInstance.address, maturity, strike, true);
		await feldmexERC20HelperInstance.deployNew(optionsInstance.address, maturity, strike, false);
		feldmexERC20CallInstance = await ERC20FeldmexOption.at(await feldmexERC20HelperInstance.callAddresses(optionsInstance.address, maturity, strike));
		feldmexERC20PutInstance = await ERC20FeldmexOption.at(await feldmexERC20HelperInstance.putAddresses(optionsInstance.address, maturity, strike));
		feldmexDetachedCall = await detachedOption.at(await feldmexERC20CallInstance.detachedOptionsAddress());
		feldmexDetachedPut = await detachedOption.at(await feldmexERC20PutInstance.detachedOptionsAddress());
		assert.notEqual(feldmexERC20CallInstance.address, nullAddress, "feldmex call erc20 instance has non null address");
		assert.notEqual(feldmexERC20PutInstance.address, nullAddress, "feldmex put erc20 instance has non null address");
		assert.notEqual(feldmexDetachedCall.address, nullAddress, "feldmex detached call instance has non null address");
		assert.notEqual(feldmexDetachedPut.address, nullAddress, "feldmex detached put instance has non null address");
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
		amount = "20";
		var amtBN = (new BN(amount)).mul(tokenSubUnitsBN);
		var amt = amtBN.toString();
		await depositFunds(tokenSubUnits * amount, 0, deployerAccount);
		await optionsInstance.addStrike(maturity, strike, 0, {from: deployerAccount});
		await feldmexERC20CallInstance.transfer(accounts[1], amt, {from: deployerAccount});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toString(), "-"+amt, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toString(), amt, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20CallInstance.balanceOf(deployerAccount)).toString(), "0", "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20CallInstance.balanceOf(accounts[1])).toString(), amt, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.underlyingAssetDeposits(deployerAccount)).toString(), "0", "correct balance of claimed tokens in the options handler for deployerAccount");
		secondAmount = "15";
		var amt2BN = (new BN(secondAmount)).mul(tokenSubUnitsBN);
		var amt2 = amt2BN.toString();
		await feldmexERC20CallInstance.transfer(deployerAccount, amt2, {from: accounts[1]});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, true)).toString(), amt2BN.sub(amtBN).toString(), "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toString(), amtBN.sub(amt2BN).toString(), "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20CallInstance.balanceOf(deployerAccount)).toString(), "0", "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20CallInstance.balanceOf(accounts[1])).toString(), amtBN.sub(amt2BN).toString(), "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.underlyingAssetDeposits(deployerAccount)).toString(), amt2, "correct balance of claimed tokens in the options handler for first account");
	});

	it('transfers put options', async () => {
		amount = "20";
		var amtBN = (new BN(amount)).mul(tokenSubUnitsBN);
		var amt = amtBN.toString();
		await depositFunds(0, strike * amount, deployerAccount);
		await feldmexERC20PutInstance.transfer(accounts[1], amt, {from: deployerAccount});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toString(), "-"+amt, "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toString(), amt, "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20PutInstance.balanceOf(deployerAccount)).toString(), "0", "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20PutInstance.balanceOf(accounts[1])).toString(), amt, "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.strikeAssetDeposits(deployerAccount)).toString(), "0", "correct balance of claimed tokens in the options handler for deployerAccount");
		secondAmount = "15";
		var amt2BN = (new BN(secondAmount)).mul(tokenSubUnitsBN);
		var amt2 = amt2BN.toString();
		await feldmexERC20PutInstance.transfer(deployerAccount, amt2, {from: accounts[1]});
		assert.equal((await optionsInstance.balanceOf(deployerAccount, maturity, strike, false)).toString(), amt2BN.sub(amtBN).toString(), "correct call balance of deployerAccount in options instance");
		assert.equal((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toString(), amtBN.sub(amt2BN).toString(), "correct call balance of first account in options instance");
		assert.equal((await feldmexERC20PutInstance.balanceOf(deployerAccount)).toString(), "0", "correct balance in call erc20 wrapper instance for deployerAccount");
		assert.equal((await feldmexERC20PutInstance.balanceOf(accounts[1])).toString(), amtBN.sub(amt2BN).toString(), "correct balance in call erc20 wrapper instance for first account");
		assert.equal((await optionsInstance.strikeAssetDeposits(deployerAccount)).toString(), (new BN(secondAmount)).mul(new BN(strike)).toString(), "correct balance of claimed tokens in the options handler for first account");
	});

	it('approves spending of call options', async () => {
		await feldmexERC20CallInstance.approve(accounts[1], secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20CallInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount, "correct allowance");

		await feldmexERC20CallInstance.approve(feldmexDetachedCall.address, secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20CallInstance.allowance(deployerAccount, feldmexDetachedCall.address)).toNumber(), secondAmount, "correct allowance");
	});

	it('approves spending of put options', async () => {
		await feldmexERC20PutInstance.approve(accounts[1], secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20PutInstance.allowance(deployerAccount, accounts[1])).toNumber(), secondAmount, "correct allowance");

		await feldmexERC20PutInstance.approve(feldmexDetachedPut.address, secondAmount, {from: deployerAccount});
		assert.equal((await feldmexERC20PutInstance.allowance(deployerAccount, feldmexDetachedPut.address)).toNumber(), secondAmount, "correct allowance");
	});

	it('deposits funds in detached call', async () => {
		await feldmexDetachedCall.deposit(secondAmount, deployerAccount, {from: deployerAccount});
		assert.equal((await feldmexDetachedCall.balanceOf(deployerAccount)).toString(), secondAmount);
	});

	it('deposits funds in detached put', async () => {
		await feldmexDetachedPut.deposit(secondAmount, deployerAccount, {from: deployerAccount});
		assert.equal((await feldmexDetachedPut.balanceOf(deployerAccount)).toString(), secondAmount);
	});

	//this test will fail if 'approves spending of call options' fails
	it('transfers call options from owner', async () => {
		secondAmount = parseInt(secondAmount);
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

		var caught = "not caught";
		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, true)).toNumber(), 0) + 1;
		assert.equal(await optionsInstance.contains(accounts[1], maturity, strike), false, "strike is not contained by first account");
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

		var caught = "not caught";
		amount = Math.max((await optionsInstance.balanceOf(accounts[1], maturity, strike, false)).toNumber(), 0) + 1;
		assert.equal(await optionsInstance.contains(accounts[1], maturity, strike), false, "strike is not contained by first account");
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

	it('withdraws funds detached call', async () => {
		withdrawAmt = secondAmount >> 1;
		var prevBalance = await optionsInstance.balanceOf(deployerAccount, maturity, strike, true);
		await feldmexDetachedCall.withdraw(withdrawAmt, deployerAccount, {from: deployerAccount});
		var balance = await optionsInstance.balanceOf(deployerAccount, maturity, strike, true);
		assert.equal(balance.sub(prevBalance).toNumber(), withdrawAmt, "correct amount of calls withdrawn");
	});

	it('withdraws funds detached put', async () => {
		withdrawAmt = secondAmount >> 1;
		var prevBalance = await optionsInstance.balanceOf(deployerAccount, maturity, strike, false);
		await feldmexDetachedPut.withdraw(withdrawAmt, deployerAccount, {from: deployerAccount});
		var balance = await optionsInstance.balanceOf(deployerAccount, maturity, strike, false);
		assert.equal(balance.sub(prevBalance).toNumber(), withdrawAmt, "correct amount of puts withdrawn");
	});

	it('detached call enters payout phase', async () => {
		await feldmexDetachedCall.enterPayoutPhase();
		assert.equal(await feldmexDetachedCall.inPayoutPhase(), true, "enters payout phase");
	});

	it('detached put enters payout phase', async () => {
		await feldmexDetachedPut.enterPayoutPhase();
		assert.equal(await feldmexDetachedPut.inPayoutPhase(), true, "enters payout phase");
	});

	it('gives correct payout detached call', async () => {
		//we never set spot in the oracle so its default value is 0
		var prevBalance = await tokenInstance.balanceOf(deployerAccount);
		await feldmexDetachedCall.claim(deployerAccount, {from: deployerAccount});			
		var balance = await tokenInstance.balanceOf(deployerAccount);
		assert.equal(balance.sub(prevBalance).toString(), "0", "correct payout from detached call");
	});

	it('gives correct payout detached put', async () => {
		//we never set spot in the oracle so its default value is 0
		var expectedChange = (new BN(strike)).mul(new BN(secondAmount - withdrawAmt)).div(strikeAssetSubUnits).toString();
		var prevBalance = await strikeAssetInstance.balanceOf(deployerAccount);
		await feldmexDetachedPut.claim(deployerAccount, {from: deployerAccount});
		var balance = await strikeAssetInstance.balanceOf(deployerAccount);
		assert.equal(balance.sub(prevBalance).toString(), expectedChange, "correct payout from detached put");
	});

});
