module.exports = function(callback){

	const readline = require('readline');

	var processedArgs = 4;
	function askQuestion(query) {
		if (processedArgs < process.argv.length){
			processedArgs++;
			return process.argv[processedArgs-1];
		}
	    const rl = readline.createInterface({
	        input: process.stdin,
	        output: process.stdout,
	    });

	    return new Promise(resolve => rl.question(query, ans => {
	        rl.close();
	        resolve(ans);
	    }))
	}

	oracle = artifacts.require("./oracle.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return askQuestion("What spot?");
	}).then((res) => {
		spot = res;
		return web3.eth.getAccounts();
	}).then((res) => {
		account = res[0];
		return oracleInstance.set(spot, {from: account});
	}).then((res) => {
		console.log("successfully set spot");
	});

}