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
		originalSpot = 100;
		oracleInstance.set(originalSpot);
	    return askQuestion("What Maturity?\n");
	}).then((res) => {
		maturity = res;
		return askQuestion("What Stike?\n");
	}).then((res) => {
		strike = res;
		return askQuestion("What price per contract?\n");
	}).then((res) => {
		price = res;
		return askQuestion("How many contracts\n");
	}).then((res) => {
		amount = res;
		transferAmount = satUnits * amount;
		console.log("Approving collateral contract");
		return tokenInstance.approve(collateral.address, transferAmount, true);
	}).then(() => {
		console.log("Claiming collateral");
		return collateralInstance.postCollateral(transferAmount, false, {from: defaultAccount});
	}).then(() => {
		console.log("Posting buy");
		return collateralInstance.postSell(maturity, strike, price, amount, {from: defaultAccount});
	}).then((res) => {
		console.log("Hash of order: "+res.tx);
		console.log("Withdrawing excess collateral");
		return collateralInstance.withdrawMaxCollateral({from: defaultAccount});
	});

}