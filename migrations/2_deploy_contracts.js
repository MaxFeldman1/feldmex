const oracle = artifacts.require("oracle");
const token = artifacts.require("Token");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const container = artifacts.require("container");
const containerDeveloper = artifacts.require("containerDeveloper");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");
const cHelper = artifacts.require("cHelper");
const orcHelper = artifacts.require("orcHelper");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const mLegHelper = artifacts.require("mLegHelper");
const mLegDelegate = artifacts.require("mLegDelegate");
const mOrganizer = artifacts.require("mOrganizer");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const feeOracle = artifacts.require("feeOracle");
const stakingRewards = artifacts.require("StakingRewards");
const feldmexToken = artifacts.require("FeldmexToken");
const singleLegDelegate = artifacts.require("SingleLegDelegate");
const multiCallDelegate = artifacts.require("MultiCallDelegate");
const multiPutDelegate = artifacts.require("MultiPutDelegate");

module.exports = async function(deployer) {
  underlyingAssetAddress  = await deployer.deploy(token, 0);
  strikeAssetAddress = await deployer.deploy(token, 0);
  feldmexERC20HelperInstance = await deployer.deploy(feldmexERC20Helper);
  feldmexERC20HelperAddress = feldmexERC20HelperInstance.address;
  feldmexTokenInstance = await deployer.deploy(feldmexToken);
  stakingRewardsInstance = await deployer.deploy(stakingRewards, feldmexTokenInstance.address, /*60 days*/60*24*60*60, /*7 days*/7*24*60*60);
  feeOracleInstance = await deployer.deploy(feeOracle, feldmexTokenInstance.address);
  feeOracleAddress = feeOracleInstance.address;
  multiCallDelegateInstance = await deployer.deploy(multiCallDelegate);
  multiPutDelegateInstance = await deployer.deploy(multiPutDelegate);
  mCallHelperInstance = await deployer.deploy(mCallHelper, feeOracleAddress, multiCallDelegateInstance.address);
  mPutHelperInstance = await deployer.deploy(mPutHelper, feeOracleAddress, multiPutDelegateInstance.address);
  mLegDelegateInstance = await deployer.deploy(mLegDelegate);
  mLegHelperInstance = await deployer.deploy(mLegHelper, mLegDelegateInstance.address, feeOracleAddress);
  mOrganizerInstance = await deployer.deploy(mOrganizer, mCallHelperInstance.address, mPutHelperInstance.address, mLegHelperInstance.address);
  mOrganizerAddress = mOrganizerInstance.address;
  assignOptionsDelegateInstance = await deployer.deploy(assignOptionsDelegate);
  assignOptionsDelegateAddress = assignOptionsDelegateInstance.address;
  oHelperInstance = await deployer.deploy(oHelper, feldmexERC20HelperAddress, mOrganizerAddress, assignOptionsDelegateAddress, feeOracleAddress);
  oHelperAddress = oHelperInstance.address;
  singleLegDelegateInstance = await deployer.deploy(singleLegDelegate);
  eHelperInstance = await deployer.deploy(eHelper, feeOracleAddress, singleLegDelegateInstance.address);
  eHelperAddress = eHelperInstance.address;
  cHelperInstance = await deployer.deploy(cHelper);
  cHelperAddress = cHelperInstance.address;
  orcHelperInstance = await deployer.deploy(orcHelper);
  orcHelperAddress = orcHelperInstance.address;
  containerDeveloperInstance = await deployer.deploy(containerDeveloper, cHelperAddress, oHelperAddress, eHelperAddress, orcHelperAddress);
  containerDeveloperAddress = containerDeveloperInstance.address;
  await cHelperInstance.transferOwnership(containerDeveloperAddress);
}
