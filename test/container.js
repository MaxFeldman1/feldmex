const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");
const container = artifacts.require("container");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");

contract('container', function(accounts){

	deployerAccount = accounts[0];

	//before it is set the fee denominator has default value high enough that there is effectively no fee
	feeDenominator = Math.pow(2, 200);

	it('before each', () => {
		return underlyingAsset.new(0).then((res) => {
			tokenInstance = res;
			return strikeAsset.new(0);
		}).then((res) => {
			strikeAssetInstance = res;
			return oHelper.new();
		}).then((res) => {
			oHelperInstance = res;
			return eHelper.new();
		}).then((res) => {
			eHelperInstance = res;
			return container.new(tokenInstance.address, strikeAssetInstance.address, oHelperInstance.address, eHelperInstance.address, 0, 0);
		}).then((res) => {
			containerInstance = res;
			return oHelperInstance.setOwner(containerInstance.address);
		}).then(() => {
			return eHelperInstance.setOwner(containerInstance.address);
		}).then(() => {
			return containerInstance.depOptions();
		}).then(() => {
			return containerInstance.depExchange();
		}).then(() => {
			return containerInstance.progress();
		}).then((res) => {
			assert.equal(res, 2, "cotainer contract setup has been sucessfully completed");
			return containerInstance.oracleContract();
		}).then((res) => {
			return oracle.at(res);
		}).then((res) => {
			oracleInstance = res;
			return containerInstance.optionsContract();
		}).then((res) => {
			return options.at(res);
		}).then((res) => {
			optionsInstance = res;
			return containerInstance.exchangeContract();
		}).then((res) => {
			return exchange.at(res)
		}).then((res) => {
			exchangeInstance = res;
			return tokenInstance.decimals();
		}).then((res) => {
			satUnits = Math.pow(10, res.toNumber());
			return strikeAssetInstance.decimals();
		}).then((res) => {
			scUnits = Math.pow(10, res.toNumber());
		});
	});


	it('implements erc20', () => {
		//allows token transfer
		return containerInstance.decimals().then((res) => {
			assert.equal(res.toNumber(), 4, "correct default decimal value");
			subUnits = Math.pow(10, res.toNumber());
			return containerInstance.totalSupply();
		}).then((res) => {
			assert.equal(res.toNumber(), 1000000*subUnits, "correct default total supply");
			totalSupply = res.toNumber();
			totalCoins = totalSupply/subUnits;
			return containerInstance.balanceOf(deployerAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), totalSupply, "deployerAccount initially holds all coins");
			transferAmount = 10 * subUnits;
			return containerInstance.transfer(accounts[1], transferAmount, {from: deployerAccount});
		}).then(() => {
			return containerInstance.balanceOf(deployerAccount);
		}).then((res) => {
			assert.equal(res, totalSupply-transferAmount, "sender balance reduced on transfer");
			return containerInstance.balanceOf(accounts[1]);
		}).then((res) => {
			assert.equal(res, transferAmount, "receiver balance credited on transfer");
			//test approval
			return containerInstance.approve(accounts[1], transferAmount, {from: deployerAccount});
		}).then(() => {
			return containerInstance.allowance(deployerAccount, accounts[1]);
		}).then((res) => {
			assert.equal(res, transferAmount, "allowance set to expected value");
			return containerInstance.transferFrom(deployerAccount, accounts[2], transferAmount, {from: accounts[1]});
		}).then(() => {
			return containerInstance.allowance(deployerAccount, accounts[1]);
		}).then((res) => {
			assert.equal(res, 0, "allowance decreaced");
			return containerInstance.balanceOf(deployerAccount);
		}).then((res) => {
			assert.equal(res, totalSupply-2*transferAmount, "from account balance reduced by expected amount");
			return containerInstance.balanceOf(accounts[2]);
		}).then((res) => {
			assert.equal(res, transferAmount, "to account balane credited correct amount");
		});
	});

	it('changes the fee', function(){
		nonDeployer = accounts[1];
		return containerInstance.setFee(1500, {from: deployerAccount}).then(() => {
			feeDenominator = 1500;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OK", "Successfully changed the fee");
			return containerInstance.setFee(400, {from: deployerAccount});
		}).then(() => {
			feeDenominator = 400;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because fee was too high");
			return containerInstance.setFee(1800, {from: nonDeployer});
		}).then(() => {
			feeDenominator = 1800;
			return "OK";
		}).catch(() => {
			return "OOF";
		}).then((res) => {
			assert.equal(res, "OOF", "Fee change was stopped because the sender was not the deployer");
		});
	});

	it('gathers yeild from fees generated in options contract', () => {
		return oracleInstance.set(1).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			maturity = res.timestamp;
			strike = 100
			//set spot very low
			amount = 1000;
			expectedTransfer = amount * satUnits;
			expectedFee = parseInt(expectedTransfer/feeDenominator);
			return tokenInstance.approve(optionsInstance.address, expectedTransfer, {from: deployerAccount});
		}).then(() => {
			return new Promise(resolve => setTimeout(resolve, 2000));
		}).then(() => {
			optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
			return optionsInstance.addStrike(maturity, strike, {from: accounts[2]});
		}).then(() => {
			return optionsInstance.mintCall(accounts[1], accounts[2], maturity, 100, amount, expectedTransfer, {from: deployerAccount});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: accounts[1]});
		}).then(() => {
			return optionsInstance.claim(maturity, {from: accounts[2]});
		}).then(() => {
			return containerInstance.contractClaim();
		}).then(() => {
			return tokenInstance.balanceOf(containerInstance.address);
		}).then((res) => {
			assert.equal(res.toNumber(), expectedFee, "balance of contract is the same as expectedFee");
			//size of contractBalanceUnderlying array is 2, get the last index
			return containerInstance.contractBalanceUnderlying(1);
		}).then((res) => {
			assert.equal(res.toNumber(), expectedFee, "balance of contract reflected in contractBalanceUnderlying");
			//size of contractBalanceStrike array is 2, get the last index
			return containerInstance.contractBalanceStrike(1);
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "no fee revenue has been recorded for the strikeAsset");
			return containerInstance.balanceOf(deployerAccount);
		}).then((res) => {
			deployerBalance = res.toNumber();
			return containerInstance.balanceOf(accounts[1]);
		}).then((res) => {
			firstAccountBalance = res.toNumber();
			return containerInstance.balanceOf(accounts[2]);
		}).then((res) => {
			secondAccountBalance = res.toNumber();
			containerInstance.publicClaim({from: deployerAccount});
			containerInstance.publicClaim({from: accounts[1]});
			return containerInstance.publicClaim({from: accounts[2]});
		}).then(() => {
			return containerInstance.viewUnderlyingAssetBalance({from: deployerAccount});
		}).then((res) => {
			deployerUnderlyingBalance = res.toNumber();
			assert.equal(deployerUnderlyingBalance, Math.floor(expectedFee*(deployerBalance)/totalSupply), "correct divident paid to deployerAccount");
			return containerInstance.viewUnderlyingAssetBalance({from: accounts[1]});
		}).then((res) => {
			firstUnderlyingBalance = res.toNumber();
			assert.equal(res.toNumber(), Math.floor(expectedFee*(firstAccountBalance)/totalSupply), "correct divident paid to accounts[1]");
			return containerInstance.viewUnderlyingAssetBalance({from: accounts[2]});
		}).then((res) => {
			secondUnderlyingBalance = res.toNumber();
			assert.equal(res.toNumber(), Math.floor(expectedFee*(secondAccountBalance)/totalSupply), "correct divident paid to accounts[2]");
		});
	});

	it('withdraws funds', () => {
		assert.notEqual(typeof(deployerUnderlyingBalance), "undefined", "we have balance of deployer account");
		assert.notEqual(typeof(firstUnderlyingBalance), "undefined", "we have balance of first account");
		assert.notEqual(typeof(secondUnderlyingBalance), "undefined", "we have balance of second account");
		//deployer account is the only account with a balance of underlyingAsset held outside of the container contract
		return tokenInstance.balanceOf(deployerAccount).then((res) => {
			deployerUnderlyingBalance += res.toNumber();
			return containerInstance.withdrawFunds({from: deployerAccount});
		}).then(() => {
			return tokenInstance.balanceOf(deployerAccount);
		}).then((res) => {
			assert.equal(res.toNumber(), deployerUnderlyingBalance, "correct amount of funds credited to deployerAccount");
			return containerInstance.viewUnderlyingAssetBalance({from: deployerAccount});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct amount of deployerAccount's funds remain in container contract");
			return containerInstance.withdrawFunds({from: accounts[1]});
		}).then(() => {
			return tokenInstance.balanceOf(accounts[1]);
		}).then((res) => {
			assert.equal(res.toNumber(), firstUnderlyingBalance, "correct amount of funds credited to first account");
			return containerInstance.viewUnderlyingAssetBalance({from: accounts[1]});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct amount of first account's funds remain in container contract");
			return containerInstance.withdrawFunds({from: accounts[2]});
		}).then(() => {
			return tokenInstance.balanceOf(accounts[2]);
		}).then((res) => {
			assert.equal(res.toNumber(), secondUnderlyingBalance, "correct amount of funds credited to second account");
			return containerInstance.viewUnderlyingAssetBalance({from: accounts[2]});
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "correct amount of second account's funds remain in container contract");
		});
	});


	it('grants fee immunity', () => {
		strike = 10;
		spot = strike+10;
		//strike*=satUnits;
		//spot*=satUnits;
		return oracleInstance.set(spot).then(() => {
			return web3.eth.getBlock('latest');
		}).then((res) => {
			maturity = res.timestamp;
			maxTransfer = satUnits*amount;
			//wait one second to allow for maturity to pass
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return tokenInstance.approve(optionsInstance.address, maxTransfer, {from: deployerAccount});
		}).then(() => {
			return tokenInstance.balanceOf(deployerAccount);
		}).then((res) => {
			assert.equal(res.toNumber() >= maxTransfer, true, "balance is large enough");
			optionsInstance.addStrike(maturity, strike, {from: deployerAccount});
			optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
			return optionsInstance.mintCall(deployerAccount, accounts[1], maturity, strike, amount, maxTransfer, {from: deployerAccount});
		}).then(() => {
			feeDenominator = 1000;
			return containerInstance.setFee(1000, {from: deployerAccount});
		}).then(() => {
			return optionsInstance.viewClaimedTokens({from: accounts[1]});
		}).then((res) => {
			prevBalance = res.toNumber();
			return containerInstance.changeFeeStatus(accounts[1], {from: deployerAccount});
		}).then(() => {
			return optionsInstance.feeImmunity(accounts[1]);
		}).then((res) => {
			assert.equal(res, true, "fee immunity granted to receiver account");
			return optionsInstance.claim(maturity, {from: accounts[1]});
		}).then(() => {
			return optionsInstance.viewClaimedTokens({from: accounts[1]});
		}).then((res) => {
			//note that there is no fee present when calculating balance
			assert.equal(res.toNumber(), prevBalance + Math.floor(satUnits*amount*(spot-strike)/spot), "No fee charged on first account's call to options.claim");
			return containerInstance.changeFeeStatus(accounts[1], {from: deployerAccount});
		}).then(() => {
			return optionsInstance.feeImmunity(accounts[1]);			
		}).then((res) => {
			assert.equal(res, false, "fee immunity revoked for receiver account");
			maturity++;
			maxTransfer = amount*strike;
			return new Promise(resolve => setTimeout(resolve, 1000));
		}).then(() => {
			return strikeAssetInstance.approve(optionsInstance.address, maxTransfer, {from: deployerAccount});
		}).then(() => {
			optionsInstance.addStrike(maturity, strike, {from: deployerAccount});
			optionsInstance.addStrike(maturity, strike, {from: accounts[1]});
			return optionsInstance.mintPut(accounts[1], deployerAccount, maturity, strike, amount, maxTransfer, {from: deployerAccount});
		}).then((res) => {
			return optionsInstance.viewClaimedStable({from: accounts[1]});
		}).then((res) => {
			prevBalance = res.toNumber();
			//option expired worthless first account gets back all collateral
			return optionsInstance.claim(maturity, {from: accounts[1]});
		}).then(() => {
			return optionsInstance.viewClaimedStable({from: accounts[1]});
		}).then((res) => {
			assert.equal(res.toNumber(), prevBalance+maxTransfer-Math.floor(maxTransfer/feeDenominator), "fee is now charged again");
		});
	});
});