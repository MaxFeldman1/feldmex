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

contract('organiser', function(accounts){
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
			return cHelper.new();
		}).then((res) => {
			cHelperInstance = res;
			return organiser.new(cHelperInstance.address, oHelperInstance.address, eHelperInstance.address);
		}).then((res) => {
			organiserInstance = res;
			return cHelperInstance.transferOwnership(organiserInstance.address);
		});
	});

	it('contains correct contract addresses', () => {
		return organiserInstance.cHelperAddress().then((res) => {
			assert.equal(res, cHelperInstance.address);
			return organiserInstance.oHelperAddress();
		}).then((res) => {
			assert.equal(res, oHelperInstance.address);
			return organiserInstance.eHelperAddress();
		}).then((res) => {
			assert.equal(res, eHelperInstance.address);
			return cHelperInstance.containerAddress(tokenInstance.address, strikeAssetInstance.address);
		});
	});

	it('sucessfully launches options chains', () => {
		nullAddress = "0x0000000000000000000000000000000000000000";
		return organiserInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address).then(() => {
			return cHelperInstance.containerAddress(tokenInstance.address, strikeAssetInstance.address);
		}).then((res) => {
			assert.notEqual(res, nullAddress, "containerAddress is not null");
			return container.at(res);
		}).then((res) => {
			containerInstance = res;
			return containerInstance.oracleContract();
		}).then((res) => {
			assert.notEqual(res, nullAddress, "oracle has been deployed");
			return containerInstance.progress();
		}).then((res) => {
			assert.equal(res.toNumber(), 0, "only constructor has been executed");
			return organiserInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		}).then(() => {
			return containerInstance.optionsContract();
		}).then((res) => {
			assert.notEqual(res, nullAddress, "options smart contract has been deployed");
			return options.at(res);
		}).then((res) => {
			optionsInstance = res;
			return containerInstance.progress();
		}).then((res) => {
			assert.equal(res.toNumber(), 1, "progress counter is correct");
			return organiserInstance.progressContainer(tokenInstance.address, strikeAssetInstance.address);
		}).then(() => {
			return containerInstance.exchangeContract();
		}).then((res) => {
			assert.notEqual(res, nullAddress, "exchange smart contract has been deployed");
			return exchange.at(res);
		}).then((res) => {
			exchangeInstance = res;
			return containerInstance.progress();
		}).then((res) => {
			assert.equal(res, 2, "progress counter is correct");
		});
	});

});