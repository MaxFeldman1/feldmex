module.exports = function(callback){
	//import all solidity files
	oracle = artifacts.require("./oracle.sol");
	dappToken = artifacts.require("./DappToken.sol");
	calls = artifacts.require("./calls.sol");
	collateral = artifacts.require("./collateral.sol");

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
		originalSpot = 100;
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
		console.log(res.logs[0].event + ' ' + res.logs[0].args._value.toNumber()/satUnits);
		return tokenInstance.approve(collateral.address, transferAmount, true, {from: reciverAccount});
	}).then((res) => {
		console.log(res.logs[0].event + ' ' + res.logs[0].args._value.toNumber()/satUnits);
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
		maturity = blockHeight+10;
		console.log(maturity+' ' +originalSpot);
		return collateralInstance.postBuy(maturity, originalSpot, 177777, 100, {from: defaultAccount});
	}).then((res) => {
		console.log("Buy Posted, now reciver is making marketSell");
		return collateralInstance.marketSell(maturity, originalSpot, 55, {from: reciverAccount});
	}).then((res) => {
		console.log("Market Sell complete");
		return oracleInstance.set(originalSpot + 50);
	}).then((res) => {
		return callsInstance.myContracts({from: defaultAccount});
	}).then((res) => {
		contracts = res;
		console.log("Exercizing/recliaming all contracts");
		console.log("# of contracts: " + contracts.length);
		contracts.forEach((res0) => {
			callsInstance.allCalls(res0).then((res1) => {
				console.log("Maturity: " + res1.maturity.toNumber());
				web3.eth.getBlockNumber().then((res) => {
					blockHeight = res;
					console.log("Height: " + blockHeight);
					if (res1.maturity.toNumber() < blockHeight){
						callsInstance.reclaim(res0, {from: res1.debtor}).then(() => console.log("Reclaimed")).catch((err) => {console.log("Reclaim Error")});
					}
					else {
						callsInstance.exercize(res0, {from: res1.holder}).then(() => console.log("Exercized")).catch((err) => {console.log("Exercize Error")});
					}
				});
			});
		});
		return;
	}).then((res) => {
		return collateralInstance.withdrawMaxCollateral({from: defaultAccount});
	}).then((res) => {
		console.log("Identifier numbero En");
		return collateralInstance.withdrawMaxCollateral({from: reciverAccount});
	}).then((res) => {
		console.log("Identifier numbero to");
		return tokenInstance.addrBalance(defaultAccount, false);
	}).then((res) => {
		console.log("Default Address Balance: " + res/satUnits);
		return tokenInstance.addrBalance(reciverAccount, false);
	}).then((res) => {
		console.log("Reciver Account Balance " + res/satUnits);
		return collateralInstance.testing();
	}).then((res) => {
		console.log("Testing: "+res);
	});
};
