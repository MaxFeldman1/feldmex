pragma solidity >=0.4.21 <0.9.0;

interface IMultiLegExchange {
    //stores price and hash of (maturity, stike, price)

    function positions(bytes32 _legsHash) external view returns (
            int[] memory callAmounts,
            uint[] memory callStrikes,
            int[] memory putAmounts,
            uint[] memory putStrikes,
            int maxUnderlyingAssetDebtor,
            int maxUnderlyingAssetHolder,
            int maxStrikeAssetDebtor,
            int maxStrikeAssetHolder
    );


    function underlyingAssetDeposits(address _owner) external view returns (uint);
    function strikeAssetDeposits(address _owner) external view returns (uint);
    function listHeads(uint, bytes32, uint8) external view returns (bytes32);
    function linkedNodes(bytes32) external view returns (bytes32, bytes32, bytes32, bytes32);
    function offers(bytes32) external view returns (address, uint, bytes32, int, uint, uint8);
    function underlyingAssetReserves() external view returns (uint);
    function strikeAssetReserves() external view returns (uint);
    function addLegHash(uint[] calldata _callStrikes, int[] calldata _callAmounts, uint[] calldata _putStrikes, int[] calldata _putAmounts) external;
    function depositFunds(address _to) external returns (bool success);
    function withdrawAllFunds(bool _token) external;
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) external payable;
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) external payable;
    function cancelOrder(bytes32 _name) external;
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) external returns (uint unfilled);
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations, bool _payInUnderlying) external returns (uint unfilled);

}