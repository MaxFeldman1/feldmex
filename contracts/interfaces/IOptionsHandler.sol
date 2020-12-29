pragma solidity >=0.4.21 <0.9.0;

interface IOptionsHandler {
	//owner only
	function setExchangeAddress(address _exchangeAddress) external;

	//all others
	function claim(uint _maturity) external returns (bool success);
	function withdrawFunds() external returns (uint underlyingAsset, uint strikeAsset);
	function depositFunds(address _to) external returns (bool success);
	function contains(address _addr, uint _maturity, uint _strike) external view returns (bool _contains);
	function addStrike(uint _maturity, uint _strike, uint _index) external;
	function balanceOf(address _owner, uint _maturity, uint _strike, bool _call) external view returns (int256 balance);
	function addPosition(uint _strike, int _amount, bool _call) external;
	function clearPositions() external;
	function inversePosition(bool _call) external;
	function transferAmount(bool _call) external returns (uint _debtorTransfer, uint _holderTransfer);
	function assignCallPosition() external;
	function assignPutPosition() external;
	function setParams(address _debtor, address _holder, uint _maturity) external;
	function setPaymentParams(bool _useDebtorInternalFunds, int _premium) external;
	function setTrustedAddressFeldmexERC20(uint _maturity, uint _strike, bool _call) external;
	function setTrustedAddressMainExchange() external;
	function setTrustedAddressMultiLegExchange(uint8 _index) external;
	function setLimits(int _maxDebtorTransfer, int _maxHolderTransfer) external;
	function viewStrikes(address _addr, uint _maturity) external view returns (uint[] memory);
	function underlyingAssetAddress() external view returns (address);
	function strikeAssetAddress() external view returns (address);
	function underlyingAssetDeposits(address _owner) external view returns (uint);
	function strikeAssetDeposits(address _owner) external view returns (uint);
	function underlyingAssetCollateral(address _addr, uint _maturity) external view returns (uint);
	function strikeAssetCollateral(address _addr, uint _maturity) external view returns (uint);
	function underlyingAssetDeduction(address _addr, uint _maturity) external view returns (uint);
	function strikeAssetDeduction(address _addr, uint _maturity) external view returns (uint);
    function useDeposits(address _addr) external view returns (bool);
    function transferAmountDebtor() external view returns (int);
    function transferAmountHolder() external view returns (int);
}