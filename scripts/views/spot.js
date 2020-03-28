module.exports = function(callback){

	oracle = artifacts.require("./oracle.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return oracleInstance.get();
	}).then((res) => {
		spot = res;
		return web3.eth.getBlock('latest');		
	}).then((res) => {
		console.log("Spot price is currently: "+spot);
		console.log("Block height is currenty: "+res.number);
	}).catch((err) => {console.error(err.message);});

}