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
	stablecoin = artifacts.require("./stablecoin.sol");

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
		return stablecoin.deployed();
	}).then((i) => {
		stablecoinInstance = i;
		return web3.eth.getAccounts();
	}).then((accts) => {
		accounts = accts;
		defaultAccount = accounts[0];
		reciverAccount = accounts[1];
		return tokenInstance.satUnits();
	}).then((res) => {
		satUnits = res.toNumber();
		return stablecoinInstance.scUnits();
	}).then((res) => {
		scUnits = res.toNumber();
	}).then(async (res) => {
		console.log("Account Collateral: ");
		for (var i = 0; i < accounts.length; i++){
			console.log(accounts[i]);
			await collateralInstance.claimedToken(accounts[i]).then((res) => {
				console.log('Claimed Tokens: '+(res.toNumber()/satUnits));
			});
			await collateralInstance.claimedStable(accounts[i]).then((res) => {
				console.log('Cliamed Stablecoins: '+(res.toNumber()/scUnits));
			})
		}		
	}).then(async () => {
		console.log("\nAccount Balances:");
		for (var i = 0; i < accounts.length; i++){
			console.log(accounts[i]);
			await tokenInstance.addrBalance(accounts[i], false).then((res) => {
				console.log('Token balance: '+(res.toNumber()/satUnits));
			});
			await stablecoinInstance.addrBalance(accounts[i], false).then((res) => {
				console.log('Stablecoin balance: '+(res.toNumber()/scUnits));
			});
		}
	});
}