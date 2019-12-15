module.exports = function(callback){
	
	const defaultHash = '0x0000000000000000000000000000000000000000000000000000000000000000';
	const readline = require('readline');

	function askQuestion(query) {
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
	calls = artifacts.require("./calls.sol");
	collateral = artifacts.require("./collateral.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return dappToken.deployed();
	}).then((i) => {
		tokenInstance = i;
		return calls.deployed();
	}).then((i) => {
		callsInstance = i;
		return collateral.deployed();
	}).then((i) => {
		collateralInstance = i;
		return web3.eth.getAccounts();
	}).then((accts) => {
		accounts = accts;
		defaultAccount = accounts[0];
		reciverAccount = accounts[1];
		return tokenInstance.satUnits();
	}).then((res) => {
		satUnits = res.toNumber();
		originalSpot = 100;
		oracleInstance.set(originalSpot);
	    return askQuestion("What Maturity?\n");
	}).then((res) => {
		maturity = res;
		return askQuestion("What Stike?\n");
	}).then((res) => {
		strike = res;
		return collateralInstance.listHeads(maturity, strike, 0);
	}).then((res) => {
		buy = res;
		return collateralInstance.listHeads(maturity, strike, 1);
	}).then((res) => {
		sell = res;
	}).then(async () => {
		var node;
		console.log("\nBUYS\n");
		do {	
			await collateralInstance.linkedNodes(buy).then((res) => {
				node = res;
				buy = node.next;
				return collateralInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("BUY OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				console.log("Buy: "+res.buy);
				return;
			})
		} while (buy != defaultHash);
	}).then(async () => {
		var node;
		console.log("\nSELLS\n");
		do {	
			await collateralInstance.linkedNodes(sell).then((res) => {
				node = res;
				sell = node.next;
				return collateralInstance.offers(node.hash);
			}).then((res) => {
				if (res.price.toNumber() == 0) return;
				console.log("SELL OFFER:");
				console.log("Name: "+node.name);
				console.log("Offerer: "+res.offerer);
				console.log("Maturity: "+res.maturity.toNumber());
				console.log("Strike: "+res.strike.toNumber());
				console.log("Price: "+res.price.toNumber());
				console.log("Amount: "+res.amount.toNumber());
				console.log("Next: "+node.next);
				console.log("Buy: "+res.buy);
				return;
			})
		} while (sell != defaultHash);
	}).then(async (res) => {
		return;
	});


}