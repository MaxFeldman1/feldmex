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
	    return askQuestion("How many tokens?\n");
	}).then(async (res) => {
		amount = res;
		for (var i = 0; i < accounts.length; i++){
			await tokenInstance.transfer(accounts[i], amount, true, {from: defaultAccount});
		}
	}).then(async () => {
		for (var i = 0; i < accounts.length; i++){
			await tokenInstance.addrBalance(accounts[i], false).then((res) => {
				console.log(accounts[i]+' '+(res.toNumber()/satUnits));
			});
		}
	}).then(() => {
		return askQuestion("How many tokens to claim?\n");
	}).then(async (res) => {
		toClaim = res;
		for (var i = 0; i < accounts.length; i++){
			await tokenInstance.approve(collateral.address, toClaim*satUnits, false, {from: accounts[i]}).then(() => {
				console.log('Claiming for '+accounts[i]);
			}).then(() => {
				return collateralInstance.postCollateral(toClaim*satUnits, false, {from: accounts[i]});
			}).then(() => console.log("Success"));
		}
	});
}