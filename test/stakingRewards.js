var token = artifacts.require("FeldmexToken");
var StakingRewards = artifacts.require("StakingRewards");

const BN = web3.utils.BN;

const helper = require("../helper/helper.js");

const secondsPerDay = 24*3600;
const _60days = 60 * secondsPerDay;
const _7days = 7*secondsPerDay;

contract('StakingRewards', function(accounts){

	it('before each', async () => {
		asset1 = await token.new();
		stakingRewardsInstance = await StakingRewards.new(asset1.address, _60days, _7days);
		//approve large number to avoid approvals in the future
		await asset1.approve(stakingRewardsInstance.address, "100000000000000");
	});

	it('recieves ether', async () => {
		ethSent = web3.utils.toWei('0.001', 'ether');
		await web3.eth.sendTransaction({to: stakingRewardsInstance.address, from: accounts[0], value: ethSent});
		assert.equal(await web3.eth.getBalance(stakingRewardsInstance.address), ethSent, "correct amount received by contract");
	});

	it('start stake', async () => {
		var amount = "100";
		await stakingRewardsInstance.stake(amount);
		var stake = await stakingRewardsInstance.stakes(accounts[0]);
		totalStakeRounds = await stakingRewardsInstance.totalStakeRounds();
		assert.equal(stake.amount.toString(), amount, "correct amount staking");
		assert.equal(stake.round.toString(), totalStakeRounds.toString(), "correct round in stake");
		assert.equal((await stakingRewardsInstance.currentAmtStaking()).toString(), amount, "correct value of global var currentAmtStaking");
	});

	it('add to stake', async () => {
		var addAmt = "50";
		var totalAmt = "150";
		await stakingRewardsInstance.stake(addAmt);
		var stake = await stakingRewardsInstance.stakes(accounts[0]);		
		assert.equal(stake.amount.toString(), totalAmt, "correct amount staking");
		assert.equal(stake.round.toString(), totalStakeRounds.toString(), "correct round in stake");
		assert.equal((await stakingRewardsInstance.currentAmtStaking()).toString(), totalAmt, "correct value of global var currentAmtStaking");
	});

	it('withdraw from stake', async () => {
		var subAmt = "50";
		var totalAmt = "100";
		await stakingRewardsInstance.withdraw(subAmt);
		stakeAccount0 = await stakingRewardsInstance.stakes(accounts[0]);		
		assert.equal(stakeAccount0.amount.toString(), totalAmt, "correct amount staking");
		assert.equal(stakeAccount0.round.toString(), totalStakeRounds.toString(), "correct round in stake");
		assert.equal((await stakingRewardsInstance.currentAmtStaking()).toString(), totalAmt, "correct value of global var currentAmtStaking");
	});

	it('start stake account 1', async () => {
		var amount = "100";
		var totalAmt = "200";
		await asset1.transfer(accounts[1], amount, {from:accounts[0]});
		await asset1.approve(stakingRewardsInstance.address, amount, {from: accounts[1]});
		await stakingRewardsInstance.stake(amount, {from: accounts[1]});
		stakeAccount1 = await stakingRewardsInstance.stakes(accounts[1]);
		assert.equal(stakeAccount1.amount.toString(), amount, "correct amount staking");
		assert.equal(stakeAccount1.round.toString(), totalStakeRounds.toString(), "correct round in stake");
		assert.equal((await stakingRewardsInstance.currentAmtStaking()).toString(), totalAmt, "correct value of global var currentAmtStaking");
	});

	it('enters lockup period', async () => {
		currentAmtStaking = await stakingRewardsInstance.currentAmtStaking();
		var rec = await stakingRewardsInstance.startLockupPeriod();
		prevTotalStaked = currentAmtStaking;
		currentAmtStaking = new BN(0);
		assert.equal((await stakingRewardsInstance.prevTotalStaked()).toString(), prevTotalStaked.toString(), "correct value prevTotalStaked");
		assert.equal((await stakingRewardsInstance.currentAmtStaking()).toString(), currentAmtStaking.toString(), "correct value prevTotalStaked");
		var expectedTime = (new BN((await web3.eth.getBlock(rec.receipt.blockHash)).timestamp)).add(new BN(_60days)).toString();
		nextLockupEnd = await stakingRewardsInstance.nextLockupEnd();
		assert.equal(nextLockupEnd.toString(), expectedTime, "correct timestamp for end of lockup period");
	});

	it('cannot stake while in lockup period', async () => {
		var amount = "100";
		var caught = false;
		try {
			await stakingRewardsInstance.stake(amount);
		} catch (err) {
			caught = true;
		}
		assert.equal(caught, true, "cannot stake in lockup period");
	});


	it('cannot withdraw from stake in lockup period', async () => {
		var amount = "100";
		var caught = false;
		try {
			await stakingRewardsInstance.withdraw(subAmt);
		} catch (err) {
			caught = true;
		}
		assert.equal(caught, true, "cannot withdraw from stake in lockup period");
	});

	it('end lockup period', async () => {
		var timestamp = (await web3.eth.getBlock('latest')).timestamp;
		if (nextLockupEnd - timestamp > 0)
			await helper.advanceTime(3+nextLockupEnd-timestamp);
		var rec = await stakingRewardsInstance.endLockupPeriod();
		var expectedTime = (new BN((await web3.eth.getBlock(rec.receipt.blockHash)).timestamp)).add(new BN(_7days)).toString();
		nextLockupStart = await stakingRewardsInstance.nextLockupStart();
		totalStakeRewards = await stakingRewardsInstance.totalStakeRewards();
		assert.equal(nextLockupStart.toString(), expectedTime, "correct timestamp for nextLockupStart");
		assert.equal((await stakingRewardsInstance.totalStakeRounds()).toString(), totalStakeRounds.add(new BN('1')).toString(), "correct value totalStakeRounds");
		assert.equal(totalStakeRewards.toString(), ethSent, "correct value for totalStakeRewards");
	});

	it('claims reward w/ restake', async () => {
		var prevBalanceAccount1 = new BN(await web3.eth.getBalance(accounts[1]));
		var amount = "100";
		await stakingRewardsInstance.claim(accounts[1], true, amount);
		var balanceAccount1 = new BN(await web3.eth.getBalance(accounts[1]));
		var updatedStake = await stakingRewardsInstance.stakes(accounts[0]);
		assert.equal(balanceAccount1.sub(prevBalanceAccount1).toString(),
			totalStakeRewards.mul(stakeAccount0.amount).div(prevTotalStaked).toString(), "correct payout");
		assert.equal(updatedStake.amount.sub(stakeAccount0.amount).toString(), amount, "correct new amount in stake");
		assert.equal(updatedStake.round.sub(stakeAccount0.round).toString(), "1", "corret new round in stake");
	});

	it('claims reward w/ withdraw', async () => {
		var prevBalanceAccount2 = new BN(await web3.eth.getBalance(accounts[2]));
		var amount = "10";
		await stakingRewardsInstance.claim(accounts[2], false, amount, {from: accounts[1]});
		var balanceAccount2 = new BN(await web3.eth.getBalance(accounts[2]));
		var updatedStake = await stakingRewardsInstance.stakes(accounts[1]);
		assert.equal(balanceAccount2.sub(prevBalanceAccount2).toString(),
			totalStakeRewards.mul(stakeAccount1.amount).div(prevTotalStaked).toString(), "correct payout");
		assert.equal(stakeAccount1.amount.sub(updatedStake.amount).toString(), amount, "correct new amount in stake");
		assert.equal(updatedStake.round.toString(), "0", "corret new round in stake");
	});

	it('cannot double claim', async () => {
		var caught = false;
		try {
			await stakingRewardsInstance.claim(accounts[0], true, 0);
		} catch (err) {
			caught = true;
		}
		assert.equal(caught, true, "account 0 cannot double claim");

		caught = false;
		try {
			await stakingRewardsInstance.claim(accounts[0], true, 0, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		assert.equal(caught, true, "account 1 cannot double claim");
	});


});
