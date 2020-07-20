var underlyingAsset = artifacts.require("UnderlyingAsset");

contract('UnderlyingAsset', function(accounts) {
	var btcs = 21000000;

	it('before each', async() => {
		return underlyingAsset.new(0).then((i) => {
			tokenInstance = i;
			return;
		});
	});

	it('initial supply == '+btcs, function(){
		return tokenInstance.totalSupply().then((supply) => {
			assert.equal(supply, btcs, 'initial supply is equal to 21mil from btc');
		});
	});
	it('allows token transfer', function(){
		transferAmount = 1000;
		accountTo = accounts[1];
		accountFrom = accounts[0];
		return tokenInstance.decimals().then((res) => {
			satUnits = Math.pow(10, res);
			return tokenInstance.balanceOf(accountTo);
		}).then((balance) => {
			toStartBalance = balance;
			return tokenInstance.balanceOf(accountFrom);
		}).then((balance) => {
			fromStartBalance = balance;
			return tokenInstance.transfer(accountTo, transferAmount*satUnits, {from: accountFrom});
		}).then((reciept) => {
			assert.equal(reciept.logs[0].args._value, transferAmount*satUnits, 'tokens transfer returns true');
			return tokenInstance.balanceOf(accountTo);
		}).then((balance) => {
			assert.equal(balance-toStartBalance, transferAmount*satUnits, 'amount credited to toAccount');
			return tokenInstance.balanceOf(accountFrom);
		}).then((balance) => {
			assert.equal(fromStartBalance-balance, transferAmount*satUnits, 'amount debited from fromAccount');
			return;
		});
	});
});