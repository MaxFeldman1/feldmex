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
	collateral = artifacts.require("./collateral.sol");
	stablecoin = artifacts.require("./stablecoin.sol");

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return dappToken.deployed();
	}).then((i) => {
		tokenInstance = i;
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
		for (var i = 0; i < accounts.length; i++){
			await tokenInstance.transfer(accounts[i], amount, true, {from: defaultAccount});
			await stablecoinInstance.transfer(accounts[i], stableAmount, true, {from: defaultAccount});
		}
	}).then(async () => {
		for (var i = 0; i < accounts.length; i++){
			console.log(accounts[i]);
			await tokenInstance.addrBalance(accounts[i], false).then((res) => {
				console.log('Token Balance: '+(res.toNumber()/satUnits));
			});
			await stablecoinInstance.addrBalance(accounts[i], false).then((res) => {
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
			await tokenInstance.approve(collateral.address, toClaim, true, {from: accounts[i]}).then(() => {
				return stablecoinInstance.approve(collateral.address, toClaimStable, true, {from: accounts[i]})
			}).then(() => {
				return collateralInstance.postCollateral(toClaim, true, toClaimStable, true, {from: accounts[i]});
			}).then(() => console.log('posted collateral for '+accounts[i]));
		}
	});
}