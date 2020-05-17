const oracle = artifacts.require("oracle");
const underlyingAsset = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const exchange = artifacts.require("exchange");
const strikeAsset = artifacts.require("strikeAsset");

module.exports = function(deployer) {
  deployer.deploy(oracle).then(() => {
  	return deployer.deploy(underlyingAsset, 0);
  }).then(() => {
  	return deployer.deploy(strikeAsset, 0);
  }).then(() => {
  	return deployer.deploy(options, oracle.address, underlyingAsset.address, strikeAsset.address);
  }).then((instance) => {
    optionsInstance = instance;
  	return deployer.deploy(exchange, underlyingAsset.address, strikeAsset.address, options.address);
  }).then(() => {
  	return options.deployed();
  }).then(() => {
  	return optionsInstance.setExchangeAddress(exchange.address);
  });
};