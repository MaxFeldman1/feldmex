var oracle = artifacts.require("./oracle.sol");

contract('oracle', function(accounts){

	it('sets and fetches spot price', function(){
		return oracle.deployed().then((instance) => {
			orcInstance = instance;
			spot = 5
			secondSpot = 7;
			return orcInstance.set(spot);
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
		});
	});
});