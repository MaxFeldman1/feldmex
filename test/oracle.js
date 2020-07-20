var oracle = artifacts.require("oracle");
var token = artifacts.require("UnderlyingAsset");

const helper = require("../helper/helper.js");

contract('oracle', function(accounts){

	it('before each', async () => {
		asset1 = await token.new(0);
		asset2 = await token.new(0);
		oracleInstance = await oracle.new(asset1.address, asset2.address);
		asset1SubUnits = await oracleInstance.underlyingAssetSubUnits();
		asset2SubUnits = await oracleInstance.strikeAssetSubUnits();
	});

	async function setPrice(spot) {
		return oracleInstance.set(spot*asset2SubUnits);
	}

	async function heightToPrevTs(height) {
		var index = (await oracleInstance.heightToIndex(height)).toNumber();
		var newHeight = (await oracleInstance.heights(index)).toNumber();
		return (await oracleInstance.timestamps(newHeight)).toNumber();
	}

	async function heightToPrevSpot(height) {
		var index = (await oracleInstance.heightToIndex(height)).toNumber();
		var newHeight = (await oracleInstance.heights(index)).toNumber();
		return (await oracleInstance.heightToSpot(newHeight)).toNumber();
	}

	async function tsToPrevSpot(time) {
		var index = (await oracleInstance.tsToIndex(time)).toNumber();
		var newHeight = (await oracleInstance.heights(index)).toNumber();
		return (await oracleInstance.heightToSpot(newHeight)).toNumber();
	}

	async function indexToSpot(index) {
		var height = (await oracleInstance.heights(index)).toNumber();
		return (await oracleInstance.heightToSpot(height)) / asset2SubUnits;
	}

	//in solidity block.number is always height of the next block, in web3 it is height of prev block
	function getBlockNumber() {
		return web3.eth.getBlockNumber();
	}

	it('sets and fetches spot price', async () => {
		spot = 5
		secondSpot = 7;
		await setPrice(spot);
		blockSetSpot = await getBlockNumber();
		await helper.advanceTime(2);
		res = (await oracleInstance.latestSpot()) / asset2SubUnits;
		assert.equal(res, spot, 'latestSpot() fetches current spot price');
		height = await getBlockNumber();
		res = (await heightToPrevSpot(height))/asset2SubUnits;
		//res = (await heightToPrevSpot(height))/asset2SubUnits;
		assert.equal(res, spot, "getUint(uint) fetches the latest spot price");
		await setPrice(secondSpot);
		blockSetSecondSpot = await getBlockNumber();
		await helper.advanceTime(2);
		//note that we have not updated the value of height yet
		res = (await heightToPrevSpot(height)) / asset2SubUnits;
		assert.equal(res, spot, "getUint(uint) can fetch previous values");
		//we are now feching the price of the blocks after setting the spot a second time
		res = (await heightToPrevSpot(blockSetSecondSpot+5))/asset2SubUnits;
		assert.equal(res, secondSpot, "getUint(uint) can fetch the most recent spot");
		res = (await heightToPrevSpot(height-3))/asset2SubUnits;
		assert.equal(res, 0, "getUint(uint) returns 0 when there are no previous spot prices");
		res = await web3.eth.getBlock('latest');
		height = res.number;
		time = res.timestamp;
		result = (await heightToPrevSpot(height))/asset2SubUnits;
		//res  = await oracleInstance.timestampBehindHeight(height);
		res  = await heightToPrevTs(height);
		assert.equal(res <= time, true, "returns the correct timestamp");
		await setPrice(1);
		blockSet1 = await getBlockNumber();
		await helper.advanceTime(2);
		await setPrice(5);
		blockSet5 = await getBlockNumber();
		await helper.advanceTime(2);
		await setPrice(6);
		blockSet6 = await getBlockNumber();
		res = await web3.eth.getBlock('latest');
		diff = res.timestamp-time;
		time = res.timestamp;
		height = res.number;
		res = (await tsToPrevSpot(time))/asset2SubUnits;
		assert.equal(res, 6, "correct spot");
		newTime = (await web3.eth.getBlock(blockSet1)).timestamp+1;
		res = (await tsToPrevSpot(newTime))/asset2SubUnits;
		assert.equal(res, 1, "correct spot");
		newTime = (await web3.eth.getBlock(blockSet5)).timestamp+1;
		res = (await tsToPrevSpot(newTime))/asset2SubUnits;
		assert.equal(res, 5, "correct spot");
		newTime = (await web3.eth.getBlock(blockSetSpot)).timestamp;
		spotTime = newTime;
		res = (await tsToPrevSpot(newTime))/asset2SubUnits;
		assert.equal(res, spot, "correct spot");
		newTime = (await web3.eth.getBlock(blockSetSecondSpot)).timestamp;
		res = (await tsToPrevSpot(newTime))/asset2SubUnits;
		assert.equal(res, secondSpot, "correct spot");
		res = (await tsToPrevSpot(spotTime-4))/asset2SubUnits;
		assert.equal(res, 0, "correct spot");
	});

});