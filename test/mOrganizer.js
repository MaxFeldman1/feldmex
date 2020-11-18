const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const options = artifacts.require("OptionsHandler");
const exchange = artifacts.require("exchange");
const multiCallExchange = artifacts.require("multiCallExchange");
const multiPutExchange = artifacts.require("multiPutExchange");
const multiLegExchange = artifacts.require("multiLegExchange");
const mOrganizer = artifacts.require("mOrganizer");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const mLegHelper = artifacts.require("mLegHelper");
const mLegDelegate = artifacts.require("mLegDelegate");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");

const nullAddress = "0x0000000000000000000000000000000000000000";

contract('mOrganizer', async function(accounts){
	it('before each', async () => {
		tokenInstance = await token.new(0);
		strikeAssetInstance = await token.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		mCallHelperInstance = await mCallHelper.new(feeOracleInstance.address);
		mPutHelperInstance = await mPutHelper.new(feeOracleInstance.address);
		mLegDelegateInstance = await mLegDelegate.new();
		mLegHelperInstance = await mLegHelper.new(mLegDelegate.address, feeOracleInstance.address);
		mOrganizerInstance = await mOrganizer.new(mCallHelperInstance.address, mPutHelperInstance.address, mLegHelperInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address, feeOracleInstance.address);
	});

	it('contains correct contract addresses', async () => {
		assert.equal(await mOrganizerInstance.mCallHelperAddress(), mCallHelperInstance.address);
		assert.equal(await mOrganizerInstance.mPutHelperAddress(), mPutHelperInstance.address);
	});

	it('sucessfully deploys call exchange', async () => {
		await mOrganizerInstance.deployCallExchange(optionsInstance.address);
		callExchangeAddress = await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 0);
		assert.notEqual(callExchangeAddress, nullAddress, "call exchange address not null");
		multiCallExchangeInstance = await multiCallExchange.at(callExchangeAddress);
	});


	it('sucessfully deploys put exchange', async () => {
		await mOrganizerInstance.deployPutExchange(optionsInstance.address);
		putExchangeAddress = await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 1);
		assert.notEqual(putExchangeAddress, nullAddress, "call exchange address not null");
		multiPutExchangeInstance = await multiPutExchange.at(putExchangeAddress);
	});

	it('sucessfully deploys multi leg exchange', async  () => {
		await mOrganizerInstance.deployMultiLegExchange(optionsInstance.address);
		mLegHelperAddress = await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 2);
		assert.notEqual(mLegHelperAddress, nullAddress, "call exchange address not null");
		multiLegExchangeInstance = await multiLegExchange.at(mLegHelperAddress);
	});

});