const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
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
const feldmexToken = artifacts.require("FeldmexToken");

module.exports = async function(deployer) {
  underlyingAssetAddress  = await deployer.deploy(underlyingAsset, 0);
  strikeAssetAddress = await deployer.deploy(underlyingAsset, 0);
  feldmexERC20HelperInstance = await deployer.deploy(feldmexERC20Helper);
  feldmexERC20HelperAddress = feldmexERC20HelperInstance.address;
  mCallHelperInstance = await deployer.deploy(mCallHelper);
  mPutHelperInstance = await deployer.deploy(mPutHelper);
  mLegDelegateInstance = await deployer.deploy(mLegDelegate);
  mLegHelperInstance = await deployer.deploy(mLegHelper, mLegDelegateInstance.address);
  mOrganizerInstance = await deployer.deploy(mOrganizer, mCallHelperInstance.address, mPutHelperInstance.address, mLegHelperInstance.address);
  mOrganizerAddress = mOrganizerInstance.address;
  assignOptionsDelegateInstance = await deployer.deploy(assignOptionsDelegate);
  assignOptionsDelegateAddress = assignOptionsDelegateInstance.address;
  feldmexTokenInstance = await deployer.deploy(feldmexToken);
  feeOracleInstance = await deployer.deploy(feeOracle, feldmexToken.address);
  feeOracleAddress = feeOracleInstance.address;
  oHelperInstance = await deployer.deploy(oHelper, feldmexERC20HelperAddress, mOrganizerAddress, assignOptionsDelegateAddress, feeOracleAddress);
  oHelperAddress = oHelperInstance.address;
  eHelperInstance = await deployer.deploy(eHelper);
  eHelperAddress = eHelperInstance.address;
  cHelperInstance = await deployer.deploy(cHelper);
  cHelperAddress = cHelperInstance.address;
  orcHelperInstance = await deployer.deploy(orcHelper);
  orcHelperAddress = orcHelperInstance.address;
  containerDeveloperInstance = await deployer.deploy(containerDeveloper, cHelperAddress, oHelperAddress, eHelperAddress, orcHelperAddress);
  containerDeveloperAddress = containerDeveloperInstance.address;
  await cHelperInstance.transferOwnership(containerDeveloperAddress);
}
