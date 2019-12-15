module.exports = function(callback){
	
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
	    return askQuestion("Contract Identifier (Bytes32 name)?\n");
	}).then((res) => {
		name = res;
		return collateralInstance.linkedNodes(name);
	}).then((res) => {
		node = res;
		hash = node.hash;
		return collateralInstance.offers(hash);
	}).then((res) => {
		offer = res;
		offerer = res.offerer;
		console.log("Canceling "+(offer.buy? "Buy" : "Sell" ));
		if (offer.buy)
			return collateralInstance.cancelBuy(name, {from: offerer});
		return collateralInstance.cancelSell(name, {from: offerer});
	}).then(() => console.log("Success")).catch(() => {
		console.log("ERROR!");
		if (node.name == 0)
			console.log("Linked Nodes returned Null");
		if (offer.price == 0)
			console.log("Offers returned Null");
	});
}