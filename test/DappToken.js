var DappToken = artifacts.require("./DappToken.sol");

contract('DappToken', function(accounts) {
	var btcs = 21000000;
	it('initial supply == '+btcs, function(){
		return DappToken.deployed().then((instance) => {
			dappInstance = instance;
			return dappInstance.totalSupply();
		}).then((supply) => {
			assert.equal(supply, btcs, 'initial supply is equal to 21mil from btc');
		})
	});
	it('allows token transfer', function(){
		return DappToken.deployed().then((instance) => {
			dappInstance = instance;
			transferAmount = 1000;
			accountTo = accounts[1];
			accountFrom = accounts[0];
			return dappInstance.satUnits.call();
		}).then((sats) => {
			satUnits = sats.toNumber();
			return dappInstance.addrBalance(accountTo, true);
		}).then((balance) => {
			toStartBalance = balance;
			return dappInstance.addrBalance(accountFrom, true);
		}).then((balance) => {
			fromStartBalance = balance;
			return dappInstance.transfer(accountTo, transferAmount, true, {from: accountFrom});
		}).then((reciept) => {
			assert.equal(reciept.logs[0].args._value, transferAmount*satUnits, 'tokens transfer returns true');
			return dappInstance.addrBalance(accountTo, true);
		}).then((balance) => {
			assert.equal(balance-toStartBalance, transferAmount, 'amount credited to toAccount');
			return dappInstance.addrBalance(accountFrom, true);
		}).then((balance) => {
			assert.equal(fromStartBalance-balance, transferAmount, 'amount debited from fromAccount');
			return;
		});
	});
});