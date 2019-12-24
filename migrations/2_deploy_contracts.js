const oracle = artifacts.require("oracle");
const DappToken = artifacts.require("DappToken");
const calls = artifacts.require("calls");
const collateral = artifacts.require("collateral");
const stablecoin = artifacts.require("stablecoin");

module.exports = function(deployer) {
  deployer.deploy(oracle).then(() => {
  	return deployer.deploy(DappToken, 0);
  }).then(() => {
  	return deployer.deploy(stablecoin, 0);
  }).then(() => {
  	return deployer.deploy(calls, oracle.address, DappToken.address, stablecoin.address);
  }).then(() => {
  	return deployer.deploy(collateral, DappToken.address, calls.address);
  });
};