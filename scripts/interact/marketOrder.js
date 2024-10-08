module.exports = function(callback){
	
	const readline = require('readline');
	
	const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';

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

	oracle.deployed().then((i) => {
		oracleInstance = i;
		return dappToken.deployed();
	}).then((i) => {
		tokenInstance = i;
		return exchange.deployed();
	}).then((i) => {
		exchangeInstance = i;
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
		return askQuestion("How many contracts?\n");
	}).then((res) => {
		amount = parseInt(res);
		return askQuestion("Buy or Sell?\n");
	}).then((res) => {
		buy = res.charAt(0) == 'b' || res.charAt(0) == 'B';
		return askQuestion("Call or Put?\n");
	}).then((res) => {
		call = res.charAt(0) == 'c' || res.charAt(0) == 'C';
		index = 0;
		if (buy && call) index = 1;
		else if (!buy && !call) index = 2;
		else if (buy && !call) index = 3;
		return exchangeInstance.listHeads(maturity, strike, index);
	}).then((res) => {
		if (res == defaultBytes32) throw "Error: no orders that you can take";
		return  askQuestion("what limit price?\n");
	}).then((res) => {
		limit = res;
		if (buy) return exchangeInstance.marketBuy(maturity, strike, limit, amount, call, {from: reciverAccount});
		return exchangeInstance.marketSell(maturity, strike, limit, amount, call, {from: reciverAccount});
	}).then(() => console.log("Market Order completed")).catch((err) => {if (err.message) console.log(err.message+"\nperhaps you need to post more collateral"); else console.log(err)});
}