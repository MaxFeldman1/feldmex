module.exports = function(callback){
	//import all solidity files
	oracle = artifacts.require("./oracle.sol");
	dappToken = artifacts.require("./DappToken.sol");
	calls = artifacts.require("./calls.sol");
	collateral = artifacts.require("./collateral.sol");

	originalSpot = 100;
	finalSpot = 150;
	strike = originalSpot;
	price = 177777;
	buyAmount = 100;
	sellAmount = 55;

	const defaultBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';

	//set instances for each artifact
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
		oracleInstance.set(originalSpot);
	}).then((res) => {
		transferAmount = 1000;
		return tokenInstance.transfer(accounts[1], transferAmount, true);
	}).then((recipt) => {
		console.log("Transfer value: " + recipt.logs[0].args._value.toNumber()/satUnits);
		return tokenInstance.addrBalance(accounts[1], true);
	}).then((uint) => {
		console.log("Total reciver balance: " +uint.toNumber());
		return tokenInstance.approve(collateral.address, transferAmount, true); // from defaultAccount
	}).then((res) => {
		return tokenInstance.approve(collateral.address, transferAmount, true, {from: reciverAccount});
	}).then((res) => {
		return collateralInstance.postCollateral(transferAmount, true);
	}).then((res) => {
		return collateralInstance.postCollateral(transferAmount, true, {from: reciverAccount});
	}).then((res) => {
		return collateralInstance.claimedCollateral(defaultAccount, true);
	}).then((res) => {
		console.log("Sender claimed collateral: " + res.toNumber());
		return collateralInstance.claimedCollateral(reciverAccount, true);
	}).then((res) => {
		console.log("Reciver claimed collateral: " + res.toNumber());
	}).then((res) => {
		return oracleInstance.height();
	}).then((res) => {
		blockHeight = res.toNumber();
		console.log("Block Height: " + blockHeight);
		maturity = blockHeight+2;
		console.log(maturity+' ' +originalSpot);
		return collateralInstance.postBuy(maturity, strike, price, buyAmount, {from: defaultAccount});
	}).then((res) => {
		console.log("Buy Posted, now reciver is making marketSell");
		return collateralInstance.marketSell(maturity, strike, sellAmount, {from: reciverAccount});
	}).then((res) => {
		console.log("Market Sell complete");
		return oracleInstance.set(finalSpot);
	}).then((res) => {
		//return callsInstance.myContracts({from: defaultAccount});
		return callsInstance.claim(maturity, strike, {from: defaultAccount});
	}).then((res) => {
		return callsInstance.claim(maturity, strike, {from: reciverAccount});
	}).then(() => {
		return callsInstance.withdrawFunds({from: defaultAccount});
	}).then(() => {
		return callsInstance.withdrawFunds({from: reciverAccount});
	}).then(async () => {
		for (var cont = true; cont;){
			await collateralInstance.listHeads(maturity, strike, 0).then((res) => {
				if (res == defaultBytes32) {cont = false; return;}
				return collateralInstance.linkedNodes(res).then((res1) => {
					return collateralInstance.offers(res1.hash).then((res2) => {
						return collateralInstance.cancelBuy(res1.name, {from: res2.offerer});
					})
				})
			});
		}
	}).then((res) => {
		return collateralInstance.withdrawMaxCollateral({from: defaultAccount});
	}).then((res) => {
		return collateralInstance.withdrawMaxCollateral({from: reciverAccount});
	}).then((res) => {
		return tokenInstance.addrBalance(defaultAccount, false);
	}).then((res) => {
		console.log("Default Address Balance: " + res.toNumber()/satUnits);
		return tokenInstance.addrBalance(reciverAccount, false);
	}).then((res) => {
		console.log("Reciver Account Balance " + res.toNumber()/satUnits);
		return tokenInstance.addrBalance(collateral.address, false);
	}).then((res) => {
		console.log("collateral contract balance: " + res.toNumber()/satUnits);
	});
};