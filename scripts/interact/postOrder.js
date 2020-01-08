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
		maturity = parseInt(res);
		return askQuestion("What Stike?\n");
	}).then((res) => {
		strike = parseInt(res);
		return askQuestion("What price per contract?\n");
	}).then((res) => {
		price = parseInt(res);
		return askQuestion("How many contracts?\n");
	}).then((res) => {
		amount = parseInt(res);
		transferAmount = satUnits * amount;
		return askQuestion("Buy or Sell?\n");
	}).then((res) => {
		buy = res.charAt(0) == 'b' || res.charAt(0) == 'B';
		return askQuestion("Call or Put?\n");
	}).then((res) => {
		call = res.charAt(0) == 'c' || res.charAt(0) == 'C';
		//console.log("maturity "+maturity+"\tstrike " +strike+"\tprice "+price+"\tamount "+amount+"\tbuy "+buy+"\tcall "+call);
		console.log("Posting Order");
		return collateralInstance.postOrder(maturity, strike, price, amount, buy, call, {from: defaultAccount});
	}).then(() => console.log("Order Posted"));

}