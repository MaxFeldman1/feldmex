var oracle = artifacts.require("./oracle.sol");

contract('oracle', function(accounts){

	it('sets and fetches spot price', function(){
		return oracle.deployed().then((instance) => {
			orcInstance = instance;
			spot = 5
			secondSpot = 7;
			return orcInstance.set(spot);
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return orcInstance.get();
		}).then((res) => {
			assert.equal(res.toNumber(), spot, 'get(void) fetches current spot price');
			return orcInstance.height();
		}).then((res) => {
			height = res.toNumber();
			return orcInstance.getUint(height);
		}).then((res) => {
			assert.equal(res.toNumber(), spot, "getUint(uint) fetches the latest spot price");
			return orcInstance.set(secondSpot);
		}).then(() => {
			//note that we have not updated the value of height yet
			return orcInstance.getUint(height);
		}).then((res) => {
			assert.equal(res.toNumber(), spot, "getUint(uint) can fetch previous values");
			//we are now feching the price of the blocks after setting the spot a second time
			return orcInstance.getUint(height+2);
		}).then((res) => {
			assert.equal(res.toNumber(), secondSpot, "getUint(uint) can fetch the most recent spot");
			return orcInstance.getUint(height-1);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "getUint(uint) returns 0 when there are no previous spot prices");
			return web3.eth.getBlock('latest');
		}).then((res) => {
			height = res.number;
			time = res.timestamp;
			return orcInstance.getUint(height);
		}).then((res) => {
			result = res.toNumber();
			return orcInstance.timestampBehindHeight(height);
		}).then((res) => {
			assert.equal(res[0].toNumber(), time, "returns the correct timestamp");
			return orcInstance.getAtTime(time);
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then((res) => {
			return orcInstance.set(1);		
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return orcInstance.set(5);
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return orcInstance.set(6);
		}).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			diff = res.timestamp-time;
			time = res.timestamp;
			return orcInstance.getAtTime(time);
		}).then((res) => {
			assert.equal(res.toNumber(), 6, "correct spot");
			return orcInstance.getAtTime(time-1);
		}).then((res) => {
			assert.equal(res.toNumber(), 5, "correct spot");
			return orcInstance.getAtTime(time-diff-1);
		}).then((res) => {
			assert.equal(res.toNumber(), spot, "correct spot");
			return orcInstance.getAtTime(time-diff);
		}).then((res) => {
			assert.equal(res.toNumber(), secondSpot, "correct spot");
			return orcInstance.getAtTime(time-diff-3);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct spot");
		});
	});
});