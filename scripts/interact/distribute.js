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
	stablecoin = artifacts.require("./stablecoin.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return dappToken.deployed();
	}).then((i) => {
		tokenInstance = i;
		return exchange.deployed();
	}).then((i) => {
		exchangeInstance = i;
		return stablecoin.deployed();
	}).then((i) => {
		stablecoinInstance = i;
		return web3.eth.getAccounts();
	}).then((accts) => {
		accounts = accts;
		defaultAccount = accounts[0];
		return tokenInstance.satUnits();
	}).then((res) => {
		satUnits = res.toNumber();
		return stablecoinInstance.scUnits();
	}).then((res) => {
		scUnits = res.toNumber();		
	    return askQuestion("How many tokens?\n");
	}).then(async (res) => {
		amount = res;
		return askQuestion("How many stablecoins?\n");
	}).then(async (res) => {
		stableAmount = res;
		for (var i = 1; i < accounts.length; i++){
			await tokenInstance.transfer(accounts[i], amount*satUnits, {from: defaultAccount});
			await stablecoinInstance.transfer(accounts[i], stableAmount*scUnits, {from: defaultAccount});
		}
	}).then(async () => {
		for (var i = 0; i < accounts.length; i++){
			console.log(accounts[i]);
			await tokenInstance.balanceOf(accounts[i]).then((res) => {
				console.log('Token Balance: '+(res.toNumber()/satUnits));
			});
			await stablecoinInstance.balanceOf(accounts[i]).then((res) => {
				console.log('Stablecoin Balance: '+(res.toNumber()/scUnits));
			});
		}
	}).then(() => {
		return askQuestion("How many tokens to post for collateral?\n");
	}).then((res) => {
		toClaim = res;
		return askQuestion("How many stablecoins to post for collateral?\n");
	}).then(async (res) => {
		toClaimStable = res;
		for (var i = 0; i < accounts.length; i++){
			await tokenInstance.approve(exchange.address, toClaim*satUnits, {from: accounts[i]}).then(() => {
				return stablecoinInstance.approve(exchange.address, toClaimStable*scUnits, {from: accounts[i]})
			}).then(() => {
				return exchangeInstance.depositFunds(toClaim* satUnits, toClaimStable*scUnits, {from: accounts[i]});
			}).then(() => console.log('posted collateral for '+accounts[i]));
		}
	}).then(() => {console.log("Finished Task sucessfully")});
}