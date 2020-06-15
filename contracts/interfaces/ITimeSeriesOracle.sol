pragma solidity >=0.5.0;

interface ITimeSeriesOracle {
	function latestSpot() external view returns (uint spot);
	function heights(uint _index) external view returns (uint height);
	function heightsLength() external view returns (uint length);
	function timestamps(uint _height) external view returns (uint timestamp);
	function heightToSpot(uint _height) external view returns (uint spot);

	function inflator() external view returns (uint);
	function underlyingAssetAddress() external view returns (address);
	function strikeAssetAddress() external view returns (address);
	function set(uint _spot) external;
	function tsToIndex(uint _time) external view returns (uint index);
	function heightToIndex(uint _height) external view returns (uint index);
	function medianPreviousIndecies(uint _index) external view returns (uint median);
	function fetchSpotAtTime(uint _time) external view returns (uint spot);

}