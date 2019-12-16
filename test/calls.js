var oracle = artifacts.require("./oracle.sol");
var dappToken = artifacts.require("./DappToken.sol");
var calls = artifacts.require("./calls.sol");
var collateral = artifacts.require("./collateral.sol");

contract('calls', function(accounts){
	it ('can mint contracts', function(){
		return 	oracle.deployed().then((i) => {
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
			return tokenInstance.approve(calls.address, 1000, true, {from: defaultAccount});
		}).then(() => {
			return oracleInstance.height();
		}).then((res) => {
			height = res.toNumber();
			debtor = accounts[1];
			holder = accounts[2];
			maturity = height + 10;
			strike = 100;
			amount = 10;
			return callsInstance.mint(debtor, holder, maturity, strike, amount, {from: defaultAccount});
		}).then(() => {
			return callsInstance.myContracts({from: debtor});
		}).then((res) => {
			assert.equal(res.length, 1, "length of the debtors contract array is correct");
			contractAddress = res[0];
			return callsInstance.allCalls(contractAddress);
		}).then((res) => {
			assert.equal(res.debtor, debtor, "debtor is named in the contract");
			assert.equal(res.holder, holder, "holder is named in the contract");
			assert.equal(res.maturity.toNumber(), maturity, "maturity is correct in the contract");
			assert.equal(res.strike.toNumber(), strike*satUnits, "strike is correct in the contract");
			assert.equal(res.amount.toNumber(), amount, "amount is correct in the contract");
			return callsInstance.myContracts({from: holder});
		}).then((res) => {
			assert.equal(res, contractAddress, "the same contract is logged for the debtor and the holder");
		});
	});

	it ('can exercice and reclaim contracts', function(){
		return 	oracle.deployed().then((i) => {
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
			debtor = accounts[1];
			holder = accounts[2];
			return tokenInstance.satUnits();
		}).then((res) => {
			satUnits = res.toNumber();
			return oracleInstance.height();
		}).then((res) => {
			height = res.toNumber() + 1;
			maturity = height + 10;
			strike = 100;
			amount = 10;
			return callsInstance.mint(debtor, holder, maturity, strike, amount, {from: defaultAccount});
		}).then(() => {
			finalSpot = 2*strike;
			height++;
			return oracleInstance.set(finalSpot);
		}).then(() => {
			return callsInstance.myContracts({from: defaultAccount});
		}).then(async (res) => {
			//med mine blekkspruter, hun kaller meg tone
			for (var i = 0; i < res.length; i++){
				await callsInstance.allCalls(res[i]).then((res1) => {
					if (res1.maturity > height+2)
						return callsInstance.reclaim(res[i], {from: res1.debtor});
					else if (res1.strike < finalSpot)
						return callsInstance.exercice(res[i], {from: res1.holder});
				});
				height++;
			}
		}).then(() => {
			return callsInstance.myContracts({from: defaultAccount});
		}).then((res) => {
			assert.equal(res.length, 0, "all contracts have been executed or reclaimed");
		});

	});

});