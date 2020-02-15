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
	dappToken = artifacts.require("./DappToken.sol");
	exchange = artifacts.require("./exchange.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return dappToken.deployed();
	}).then((i) => {
		tokenInstance = i;
		return exchange.deployed();
	}).then((i) => {
		exchangeInstance = i;
	}).then(() => {
	    return askQuestion("Contract Identifier (Bytes32 name)?\n");
	}).then((res) => {
		name = res;
		return exchangeInstance.linkedNodes(name);
	}).then((res) => {
		node = res;
		hash = node.hash;
		return exchangeInstance.offers(hash);
	}).then((res) => {
		offer = res;
		offerer = res.offerer;
		console.log("Canceling "+(offer.buy? "Buy" : "Sell" ));
		return exchangeInstance.cancelOrder(name, {from: offer.offerer});
	}).then(() => console.log("Success")).catch(() => {
		console.log("ERROR!");
		if (node.name == 0)
			console.log("Linked Nodes returned Null");
		if (offer.price == 0)
			console.log("Offers returned Null");
	});
}