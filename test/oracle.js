var oracle = artifacts.require("./oracle.sol");

contract('oracle', function(accounts){

	it('val == set spot', function(){
		return oracle.deployed().then((instance) => {
			orcInstance = instance;
			return orcInstance.set(5);
		}).then(() => {
			return orcInstance.get();
		}).then((val) => {
			assert.equal(val, 5, 'val == 1st set spot');
			return;
		}).then(() => {
			return orcInstance.set(10);
		}).then(() => {
			return orcInstance.get();
		}).then((val) => {
			assert.equal(val, 10, 'val == 2nd set spot');
		});
	});
});