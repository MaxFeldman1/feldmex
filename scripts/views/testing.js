module.exports = function(callback){
	
	exchange = artifacts.require("./exchange.sol");

	exchange.deployed().then((i) => {
		exchangeInstance = i;
		return exchangeInstance.testing();
	}).then(async (res) => {
		console.log("Exchange Testing value == "+res.toNumber());
	});
}
