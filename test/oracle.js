var oracle = artifacts.require("./oracle.sol");

const helper = require("../helper/helper.js");

contract('oracle', function(accounts){

	it('before each', async() => {
		return oracle.new().then((i) => {
			orcInstance = i;
			return;
		});
	});

	it('sets and fetches spot price', function(){
		spot = 5
		secondSpot = 7;
		return orcInstance.inflator().then((res) => {
			inflator = res;
			return orcInstance.set(spot * inflator);
		}).then((res) => {
			blockSetSpot = res.receipt.blockNumber;
			return helper.advanceTime(2);
		}).then(() => {
			return orcInstance.get();
		}).then((res) => {
			res /= inflator;
			assert.equal(res, spot, 'get() fetches current spot price');
			return orcInstance.height();
		}).then((res) => {
			height = res.toNumber();
			return orcInstance.getUint(height);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, spot, "getUint(uint) fetches the latest spot price");
			return orcInstance.set(secondSpot * inflator);
		}).then((res) => {
			blockSetSecondSpot = res.receipt.blockNumber;
			return helper.advanceTime(2);
		}).then(() => {
			//note that we have not updated the value of height yet
			return orcInstance.getUint(height);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, spot, "getUint(uint) can fetch previous values");
			//we are now feching the price of the blocks after setting the spot a second time
			return orcInstance.getUint(height+2);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, secondSpot, "getUint(uint) can fetch the most recent spot");
			return orcInstance.getUint(height-2);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, 0, "getUint(uint) returns 0 when there are no previous spot prices");
			return web3.eth.getBlock('latest');
		}).then((res) => {
			height = res.number;
			time = res.timestamp;
			return orcInstance.getUint(height);
		}).then((res) => {
			res /= inflator;
			result = res;
			return orcInstance.timestampBehindHeight(height);
		}).then((res) => {
			assert.equal(res[0].toNumber() <= time, true, "returns the correct timestamp");
		}).then((res) => {
			return orcInstance.set(1 * inflator);
		}).then((res) => {
			blockSet1 = res.receipt.blockNumber;
			return helper.advanceTime(2);
		}).then(() => {
			return orcInstance.set(5 * inflator);
		}).then((res) => {
			blockSet5 = res.receipt.blockNumber;
			return helper.advanceTime(2);
		}).then(() => {
			return orcInstance.set(6 * inflator);
		}).then((res) => {
			blockSet6 = res.receipt.blockNumber;
			return web3.eth.getBlock('latest');
		}).then((res) => {
			diff = res.timestamp-time;
			time = res.timestamp;
			height = res.number;
			return orcInstance.getAtTime(time);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, 6, "correct spot");
			return web3.eth.getBlock(height-2);
		}).then((res) => {
			newTime = res.timestamp+1;
			return orcInstance.getAtTime(newTime);
		}).then((res) => {
			assert.equal(res.toNumber()/inflator, 1, "correct spot");
			return web3.eth.getBlock(blockSet5);
		}).then((res) => {
			newTime = res.timestamp+1;
			return orcInstance.getAtTime(newTime);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, 5, "correct spot");
			return web3.eth.getBlock(blockSetSpot);
		}).then((res) => {
			newTime = res.timestamp;
			spotTime = newTime;
			return orcInstance.getAtTime(newTime);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, spot, "correct spot");
			return web3.eth.getBlock(blockSetSecondSpot);
		}).then((res) => {
			newTime = res.timestamp;
			return orcInstance.getAtTime(newTime);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, secondSpot, "correct spot");
			return orcInstance.getAtTime(spotTime-4);
		}).then((res) => {
			res /= inflator;
			assert.equal(res, 0, "correct spot");
		});
	});
});