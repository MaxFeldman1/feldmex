const oracle = artifacts.require("oracle");
const token = artifacts.require("UnderlyingAsset");
const options = artifacts.require("options");
const strikeAsset = artifacts.require("strikeAsset");
const assignOptionsDelegate = artifacts.require("assignOptionsDelegate");
const feldmexERC20Helper = artifacts.require("FeldmexERC20Helper");
const feeOracle = artifacts.require("feeOracle");
const feldmexToken = artifacts.require("FeldmexToken");


contract('feeOracle', function(accounts){

	it('before each', async () => {
		tokenInstance = await token.new(0);
		strikeAssetInstance = await token.new(0);
		oracleInstance = await oracle.new(tokenInstance.address, strikeAssetInstance.address);
		assignOptionsDelegateInstance = await assignOptionsDelegate.new();
		feldmexERC20HelperInstance = await feldmexERC20Helper.new();
		feldmexTokenInstance = await feldmexToken.new();
		feeOracleInstance = await feeOracle.new(feldmexTokenInstance.address);
		optionsInstance = await options.new(oracleInstance.address, tokenInstance.address, strikeAssetInstance.address,
			feldmexERC20HelperInstance.address, accounts[0], assignOptionsDelegateInstance.address, feeOracleInstance.address);
		assert.equal(await feeOracleInstance.specificFeeImmunity(optionsInstance.address, accounts[0]), true, "owner of optionsContract is feeImmune");
		assert.equal(await feeOracleInstance.feldmexTokenAddress(), feldmexTokenInstance.address, "correct value of the feldmex token address");
	});

	it('sets base fee', async () => {
		baseOptionsFeeDenominator = 600;
		await feeOracleInstance.setBaseFee(baseOptionsFeeDenominator);
		assert.equal((await feeOracleInstance.baseOptionsFeeDenominator()).toNumber(), baseOptionsFeeDenominator, "correct base options fee denominator");
		assert((await feeOracleInstance.fetchFee(optionsInstance.address)).toNumber(), baseOptionsFeeDenominator, "correct fee for specific options contract");
	});

	it('sets specific fee', async () => {
		specificOptionsFeeDenominator = 900;
		await feeOracleInstance.setSpecificFee(optionsInstance.address, specificOptionsFeeDenominator);
		assert.equal((await feeOracleInstance.specificOptionsFeeDenominator(optionsInstance.address)).toNumber(), specificOptionsFeeDenominator, "correct specific options fee denominator");
		assert((await feeOracleInstance.fetchFee(optionsInstance.address)).toNumber(), specificOptionsFeeDenominator, "correct fee for specific options contract");
	});

	it('deletes specific fee', async () => {
		await feeOracleInstance.deleteSpecificFee(optionsInstance.address);
		assert.equal((await feeOracleInstance.specificOptionsFeeDenominator(optionsInstance.address)).toNumber(), 0, "correct specific options fee denominator");
		assert((await feeOracleInstance.fetchFee(optionsInstance.address)).toNumber(), baseOptionsFeeDenominator, "correct fee for specific options contract");
	});

	it('sets flat ether fees', async () => {
		exchangeFlatEtherFee = web3.utils.toWei('0.00002', 'ether');
		multiLegExchangeFlatEtherFee = web3.utils.toWei('0.00004', 'ether');
		await feeOracleInstance.setFlatEtherFees(exchangeFlatEtherFee, multiLegExchangeFlatEtherFee);
		assert.equal((await feeOracleInstance.exchangeFlatEtherFee()).toNumber(), exchangeFlatEtherFee, "correct exchange flat ether fee");
		assert.equal((await feeOracleInstance.multiLegExchangeFlatEtherFee()).toNumber(), multiLegExchangeFlatEtherFee, "correct multi leg exchange flat ether fee");		
	});

	it('grants and revokes base fee immunity', async () => {
		await feeOracleInstance.setBaseFeeImmunity(accounts[1], true);
		assert.equal(await feeOracleInstance.feeImmunity(accounts[1]), true, "fee immunity granted");
		assert.equal(await feeOracleInstance.isFeeImmune(optionsInstance.address, accounts[1]), true, "fee immunity sustained for specific option handler instance");
		await feeOracleInstance.setBaseFeeImmunity(accounts[1], false);
		assert.equal(await feeOracleInstance.feeImmunity(accounts[1]), false, "fee immunity revoked");
		assert.equal(await feeOracleInstance.isFeeImmune(optionsInstance.address, accounts[1]), false, "fee immunity revoked for specific option handler instance");
	});


	it('grants specific fee immunity', async () => {
		await feeOracleInstance.setSpecificFeeImmunity(optionsInstance.address, accounts[1], true);
		assert.equal(await feeOracleInstance.specificFeeImmunity(optionsInstance.address, accounts[1]), true, "specific fee immunity granted");
		assert.equal(await feeOracleInstance.isFeeImmune(optionsInstance.address, accounts[1]), true, "specific fee immunity granted affects return value of isFeeImmune");
		await feeOracleInstance.setSpecificFeeImmunity(optionsInstance.address, accounts[1], false);
		assert.equal(await feeOracleInstance.specificFeeImmunity(optionsInstance.address, accounts[1]), false, "specific fee immunity revoked");
		assert.equal(await feeOracleInstance.isFeeImmune(optionsInstance.address, accounts[1]), false, "specific fee immunity revoked affects return value of isFeeImmune");
	});
});