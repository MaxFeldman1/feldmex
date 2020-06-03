const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");
const container = artifacts.require("container");
const organiser = artifacts.require("organiser");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");
const cHelper = artifacts.require("cHelper");

module.exports = function(deployer) {
  deployer.deploy(underlyingAsset, 0).then((res) => {
    underlyingAssetAddress = res.address;
    return deployer.deploy(strikeAsset, 0);
  }).then((res) => {
    strikeAssetAddress = res.address;
    return deployer.deploy(oHelper);
  }).then((res) => {
    oHelperInstance = res;
    oHelperAddress = res.address;
    return deployer.deploy(eHelper);
  }).then((res) => {
    eHelperInstance = res;
    eHelperAddress = res.address;
    return deployer.deploy(cHelper);
  }).then((res) => {
    cHelperInstance = res;
    cHelperAddress = res.address;
    return deployer.deploy(organiser, cHelperAddress, oHelperAddress, eHelperAddress);
  }).then((res) => {
    organiserInstance = res;
    organiserAddress = res.address;
    return cHelperInstance.transferOwnership(organiserAddress);
  });
}
