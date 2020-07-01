const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const container = artifacts.require("container");
const organiser = artifacts.require("organiser");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");
const cHelper = artifacts.require("cHelper");
const orcHelper = artifacts.require("orcHelper");
const mCallHelper = artifacts.require("mCallHelper");
const mPutHelper = artifacts.require("mPutHelper");
const mOrganizer = artifacts.require("mOrganizer");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");

module.exports = async function(deployer) {
  underlyingAssetAddress  = await deployer.deploy(underlyingAsset, 0);
  strikeAssetAddress = await deployer.deploy(underlyingAsset, 0);
  feldmexERC20HelperInstance = await deployer.deploy(feldmexERC20Helper);
  feldmexERC20HelperAddress = feldmexERC20HelperInstance.address;
  mCallHelperInstance = await deployer.deploy(mCallHelper);
  mPutHelperInstance = await deployer.deploy(mPutHelper);
  mOrganizerInstance = await deployer.deploy(mOrganizer, mCallHelperInstance.address, mPutHelperInstance.address);
  mOrganizerAddress = mOrganizerInstance.address;
  oHelperInstance = await deployer.deploy(oHelper, feldmexERC20HelperAddress, mOrganizerAddress);
  oHelperAddress = oHelperInstance.address;
  eHelperInstance = await deployer.deploy(eHelper);
  eHelperAddress = eHelperInstance.address;
  cHelperInstance = await deployer.deploy(cHelper);
  cHelperAddress = cHelperInstance.address;
  orcHelperInstance = await deployer.deploy(orcHelper);
  orcHelperAddress = orcHelperInstance.address;
  organiserInstance = await deployer.deploy(organiser, cHelperAddress, oHelperAddress, eHelperAddress, orcHelperAddress);
  organiserAddress = organiserInstance.address;
  await cHelperInstance.transferOwnership(organiserAddress);
}
