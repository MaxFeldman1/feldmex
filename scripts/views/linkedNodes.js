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
	exchange = artifacts.require("./exchange.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return exchange.deployed();
	}).then((i) => {
		exchangeInstance = i;
	    return askQuestion("What is the node identifier?\n");
	}).then(async (res) => {
		hash = res;
		return exchangeInstance.linkedNodes(hash);
	}).then((res) => {
		console.log("hash: "+res.hash);
		console.log("name: "+res.name);
		console.log("next: "+res.next);
		console.log("previous: "+res.previous);
		return exchangeInstance.offers(res.hash);
	}).then((res) => {
		console.log("\n"+((res.buy)? "Buy" : "Sell" )+" Offer\n");
		console.log("Offerer: "+res.offerer);
		console.log("Maturity: "+res.maturity.toNumber());
		console.log("Strike: "+res.strike.toNumber());
		console.log("Price: "+res.price.toNumber());
		console.log("Amount: "+res.amount.toNumber());
	});
}
