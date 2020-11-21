pragma solidity >=0.6.0;
import "../interfaces/Ownable.sol";
import "../interfaces/IERC20.sol";

contract StakingRewards is Ownable {

	/*
		start with 1 to differentiate from null value of 0
		prevents double claim in the first round of staking
	*/
	uint16 public totalStakeRounds = 1;

	IERC20 public stakeAsset;

	uint public stakeDuration;
	uint public breakPeriod;

	uint public nextLockupStart;
	uint public nextLockupEnd;

	uint public totalStakeRewards;
	uint public prevTotalStaked;
	uint public currentAmtStaking;


	struct Stake {
		//amount of stake asset staked
		uint amount;
		//round at which funds were staked
		uint16 round;
	}

	mapping(address => Stake) public stakes;

	event StartStake(
		address staker,
		uint amount
	);

	event Claim(
		address staker,
		uint rewards
	);

	constructor(
			address _stakeAsset,
			uint _stakeDuration,
			uint _breakPeriod
		) public {

		stakeAsset = IERC20(_stakeAsset);
		stakeDuration = _stakeDuration;
		breakPeriod = _breakPeriod;
		nextLockupStart = block.timestamp;
	}

	/*
		@Description: start staking period, end inter stake period
	*/
	function startLockupPeriod() external {
		require(block.timestamp >= nextLockupStart && nextLockupStart > nextLockupEnd, "cannot transition yet");
		nextLockupEnd = block.timestamp + stakeDuration;
		prevTotalStaked = currentAmtStaking;
		currentAmtStaking = 0;
	}

	function endLockupPeriod() external {
		require(block.timestamp >= nextLockupEnd && nextLockupEnd > nextLockupStart, "cannot transition yet");
		totalStakeRewards = address(this).balance;
		nextLockupStart = block.timestamp + breakPeriod;
		totalStakeRounds++;
	}

	function stake(uint _amount) external {
		_stake(_amount);
	}

	function _stake(uint _amount) internal {
		require(nextLockupStart > nextLockupEnd, "can only start stake in break period");
		uint stakeAmt = stakes[msg.sender].amount;
		uint16 round = stakes[msg.sender].round;
		uint16 _totalStakeRounds = totalStakeRounds;	//gas savings
		if (_amount > 0) {
			stakeAsset.transferFrom(msg.sender, address(this), _amount);
			stakeAmt += _amount;
			stakes[msg.sender].amount = stakeAmt;
		}

		if (round == _totalStakeRounds)
			currentAmtStaking+=_amount;
		else{
			currentAmtStaking+= stakeAmt;
			stakes[msg.sender].round = _totalStakeRounds;
		}

		emit StartStake(msg.sender, stakeAmt);
	}

	function withdraw(uint _amount) external {
		_withdraw(_amount);
	}

	function _withdraw(uint _amount) internal {
		require(nextLockupStart > nextLockupEnd, "can only withdraw from stake in break period");
		require(stakes[msg.sender].amount >= _amount, "_amount must be <= amount staked");
		stakes[msg.sender].amount -= _amount;
		stakeAsset.transfer(msg.sender, _amount);
		if (stakes[msg.sender].round == totalStakeRounds)
			currentAmtStaking -= _amount;
	}

	function claim(address payable _to, bool _restake, uint _toStakeOrWithdraw) external {
		require(stakes[msg.sender].round+1 == totalStakeRounds, "must claim 1 staking round after stake started");
		require(nextLockupStart > nextLockupEnd, "must wait until end of staking period to claim");
		uint amount = stakes[msg.sender].amount;
		uint rewards = amount * totalStakeRewards / prevTotalStaked;
		_to.transfer(rewards);

		if (_restake) {
			_stake(_toStakeOrWithdraw);
		}
		else {
			_withdraw(_toStakeOrWithdraw);
			//prevent double claim
			stakes[msg.sender].round = 0;
		}

		emit Claim(msg.sender, rewards);
	}

	//----------------onlyOwner-------------
	function setStakeDuration(uint _stakeDuration) onlyOwner external {
		stakeDuration = _stakeDuration;
	}

	function setBreakPeriod(uint _breakPeriod) onlyOwner external {
		breakPeriod = _breakPeriod;
	}

	receive () external payable {}
}
