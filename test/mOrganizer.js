const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const multiCallExchange = artifacts.require("multiCallExchange");
const multiPutExchange = artifacts.require("multiPutExchange");
const mOrganizer = artifacts.require("mOrganizer");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");

const nullAddress = "0x0000000000000000000000000000000000000000";

contract('mOrganizer', async function(accounts){
	it('before each', async () => {
		tokenInstance = await underlyingAsset.new(0);
		strikeAssetInstance = await underlyingAsset.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		mCallHelperInstance = await mCallHelper.new();
		mPutHelperInstance = await mPutHelper.new();
		mOrganizerInstance = await mOrganizer.new(mCallHelperInstance.address, mPutHelperInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address, mOrganizerInstance.address, assignOptionsDelegateInstance.address);
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
		putExchangeAddress = await mOrganizerInstance.exchangeAddresses(optionsInstance.address, 0);
		assert.notEqual(putExchangeAddress, nullAddress, "call exchange address not null");
		multiPutExchangeInstance = await multiPutExchange.at(putExchangeAddress);
	});

});