module.exports = function(callback){
	
	const defaultHash = '0x0000000000000000000000000000000000000000000000000000000000000000';
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
	    return askQuestion("What Maturity?\n");
	}).then((res) => {
		maturity = res;
		return askQuestion("What Stike?\n");
	}).then((res) => {
		strike = res;
		return exchangeInstance.listHeads(maturity, strike, 0);
	}).then((res) => {
		callBuy = res;
		return exchangeInstance.listHeads(maturity, strike, 1);
	}).then((res) => {
		callSell = res;
		return exchangeInstance.listHeads(maturity, strike, 2);
	}).then((res) => {
		putBuy = res;
		return exchangeInstance.listHeads(maturity, strike, 3);
	}).then((res) => {
		putSell = res;
	}).then(async () => {
		var node;
		console.log("\nCALL BUYS\n");
		do {	
			await exchangeInstance.linkedNodes(callBuy).then((res) => {
				node = res;
				callBuy = node.next;
				return exchangeInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				return;
			})
		} while (callBuy != defaultHash);
	}).then(async () => {
		var node;
		console.log("\nCALL SELLS\n");
		do {	
			await exchangeInstance.linkedNodes(callSell).then((res) => {
				node = res;
				callSell = node.next;
				return exchangeInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				return;
			})
		} while (callSell != defaultHash);
	}).then(async () => {
		var node;
		console.log("\nPUT BUYS\n");
		do {	
			await exchangeInstance.linkedNodes(putBuy).then((res) => {
				node = res;
				putBuy = node.next;
				return exchangeInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				return;
			})
		} while (putBuy != defaultHash)
	}).then(async () => {
		var node;
		console.log("\nPUT SELLS\n");
		do {	
			await exchangeInstance.linkedNodes(putSell).then((res) => {
				node = res;
				putSell = node.next;
				return exchangeInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				return;
			})
		} while (putSell != defaultHash);
	});


}
