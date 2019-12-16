var oracle = artifacts.require("./oracle.sol");

contract('oracle', function(accounts){

	it('val == set spot', function(){
		return oracle.deployed().then((instance) => {
			orcInstance = instance;
			return orcInstance.set(5);
		}).then(() => {
			return orcInstance.get();
		}).then((val) => {
			assert.equal(val, 5, 'val == set spot');
		});
	});
});