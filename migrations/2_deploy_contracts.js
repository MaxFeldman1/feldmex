const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");
const container = artifacts.require("container");
const oHelper = artifacts.require("oHelper");
const eHelper = artifacts.require("eHelper");

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
    return deployer.deploy(container, underlyingAssetAddress, strikeAssetAddress, oHelperAddress, eHelperAddress, 1000000, 0);
  }).then((res) => {
    containerInstance = res;
    return oHelperInstance.setOwner(containerInstance.address);
  }).then(() => {
    return eHelperInstance.setOwner(containerInstance.address);
  }).then(() => {
    return containerInstance.depOptions();
  }).then(() => {
    return containerInstance.depExchange();
  });
}
