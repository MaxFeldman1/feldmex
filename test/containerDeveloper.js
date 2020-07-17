const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");
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
const mLegHelper = artifacts.require("mLegHelper");
const mLegDelegate = artifacts.require("mLegDelegate");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");

const nullAddress = "0x0000000000000000000000000000000000000000";

contract('containerDeveloper', async function(accounts){
	it('before each', async () => {
		tokenInstance = await underlyingAsset.new(0);
		strikeAssetInstance = await strikeAsset.new(0);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexToken.address);
		mCallHelperInstance = await mCallHelper.new(feeOracleInstance.address);
		mPutHelperInstance = await mPutHelper.new(feeOracleInstance.address);
		mLegDelegateInstance = await mLegDelegate.new();
		mLegHelperInstance = await mLegHelper.new(mLegDelegate.address, feeOracle.address);
		mOrganizerInstance = await mOrganizer.new(mCallHelperInstance.address, mPutHelperInstance.address, mLegHelperInstance.address);
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		oHelperInstance = await oHelper.new(feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
		eHelperInstance = await eHelper.new(feeOracleInstance.address);
		cHelperInstance = await cHelper.new();
		orcHelperInstance = await orcHelper.new();
		containerDeveloperInstance = await containerDeveloper.new(cHelperInstance.address, oHelperInstance.address, eHelperInstance.address, orcHelperInstance.address);
		await cHelperInstance.transferOwnership(containerDeveloperInstance.address);
	});

	it('contains correct contract addresses', async () => {
		assert.equal(await containerDeveloperInstance.cHelperAddress(), cHelperInstance.address);
		assert.equal(await containerDeveloperInstance.oHelperAddress(), oHelperInstance.address);
		assert.equal(await containerDeveloperInstance.eHelperAddress(), eHelperInstance.address);
		assert.equal(await cHelperInstance.containerAddress(tokenInstance.address, strikeAssetInstance.address), nullAddress, "no link to non existent options chain");
	});

	it('sucessfully launches options chains', async () => {
		await containerDeveloperInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		res = await cHelperInstance.containerAddress(tokenInstance.address, strikeAssetInstance.address);
		assert.notEqual(res, nullAddress, "containerAddress is not null");
		containerInstance = await container.at(res);
		assert.notEqual(await containerInstance.oracleContract(), nullAddress, "oracle has been deployed");
		assert.equal((await containerInstance.progress()).toNumber(), 0, "only constructor has been executed");
		await containerDeveloperInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		res = await containerInstance.optionsContract();
		assert.notEqual(res, nullAddress, "options smart contract has been deployed");
		optionsInstance = await options.at(res);
		assert.equal((await containerInstance.progress()).toNumber(), 1, "progress counter is correct");
		await containerDeveloperInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		res = await containerInstance.exchangeContract();
		assert.notEqual(res, nullAddress, "exchange smart contract has been deployed");
		exchangeInstance = await exchange.at(res);
		assert.equal((await containerInstance.progress()).toNumber(), 2, "progress counter is correct");
		await containerDeveloperInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		res = await containerInstance.optionsContract2();
		assert.notEqual(res, nullAddress, "second options smart contract has been deployed");
		optionsInstance2 = await options.at(res);
		assert.equal((await containerInstance.progress()).toNumber(), 3, "progress counter is correct");
		await containerDeveloperInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		res = await containerInstance.exchangeContract2();
		assert.notEqual(res, nullAddress, "second exchange smart contract has been deployed");
		exchangeInstance2 = await exchange.at(res);
		assert.equal((await containerInstance.progress()).toNumber(), 4, "progress counter is correct");
	});

});