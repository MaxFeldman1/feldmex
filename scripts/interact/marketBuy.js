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
		return askQuestion("How many contracts\n");
	}).then((res) => {
		amount = res;
		console.log("Approving collateral contract");
		return tokenInstance.approve(collateral.address, amount, true, {from: reciverAccount});
	}).then(() => {
		console.log("Claiming collateral");
		return collateralInstance.postCollateral(amount, true, {from: reciverAccount});
	}).then(() => {
		return collateralInstance.claimed(reciverAccount);
	}).then((res) => {
		console.log("Executing Market Sell");
		return collateralInstance.marketBuy(maturity, strike, amount, {from: reciverAccount});
	}).catch((res) => {console.log("OOF")}).then(() => {
		return collateralInstance.testing();
	}).then((res) => console.log("Testing: "+res.toNumber())).then((res) => {
		console.log("Withdrawing excess collateral");
		return collateralInstance.withdrawMaxCollateral({from: reciverAccount});
	});


}