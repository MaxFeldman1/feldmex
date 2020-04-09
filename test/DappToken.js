var DappToken = artifacts.require("./DappToken.sol");

contract('DappToken', function(accounts) {
	var btcs = 21000000;

	it('before each', async() => {
		return DappToken.new(0).then((i) => {
			tokenInstance = i;
			return;
		});
	});

	it('initial supply == '+btcs, function(){
		return DappToken.deployed().then((instance) => {
			dappInstance = instance;
			return dappInstance.totalSupply();
		}).then((supply) => {
			assert.equal(supply, btcs, 'initial supply is equal to 21mil from btc');
		})
	});
	it('allows token transfer', function(){
		transferAmount = 1000;
		accountTo = accounts[1];
		accountFrom = accounts[0];
		return dappInstance.satUnits.call().then((sats) => {
			satUnits = sats.toNumber();
			return dappInstance.balanceOf(accountTo);
		}).then((balance) => {
			toStartBalance = balance;
			return dappInstance.balanceOf(accountFrom);
		}).then((balance) => {
			fromStartBalance = balance;
			return dappInstance.transfer(accountTo, transferAmount*satUnits, {from: accountFrom});
		}).then((reciept) => {
			assert.equal(reciept.logs[0].args._value, transferAmount*satUnits, 'tokens transfer returns true');
			return dappInstance.balanceOf(accountTo);
		}).then((balance) => {
			assert.equal(balance-toStartBalance, transferAmount*satUnits, 'amount credited to toAccount');
			return dappInstance.balanceOf(accountFrom);
		}).then((balance) => {
			assert.equal(fromStartBalance-balance, transferAmount*satUnits, 'amount debited from fromAccount');
			return;
		});
	});
});