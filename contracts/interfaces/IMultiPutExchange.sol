pragma solidity >=0.4.21 <0.9.0;

interface IMultiPutExchange {
    //stores price and hash of (maturity, stike, price)
    struct linkedNode{
        //offers[hash] => offer
        bytes32 hash;
        //linkedNodes[this.name] => this
        bytes32 name;
        bytes32 next;
        bytes32 previous;
    }

    struct Offer{
        address offerer;
        uint maturity;
        bytes32 legsHash;
        int price;
        uint amount;
        /*
            long put => index: 0
            short put => index: 1
        */
        uint8 index;
    }

    struct position {
        int[] putAmounts;
        uint[] putStrikes;
        //inflated by strikeAssetSubUnits
        int maxStrikeAssetDebtor;
        //inflated by strikeAssetSubUnits
        int maxStrikeAssetHolder;
    }

    event offerPosted(
        bytes32 name,
        uint maturity,
        bytes32 legsHash,
        int price,
        uint amount,
        uint8 index
    );

    event offerCalceled(
        bytes32 name
    );

    event offerAccepted(
        bytes32 name,
        uint amount
    );

    event legsHashCreated(
        bytes32 legsHash
    );

    function strikeAssetDeposits(address _owner) external view returns (uint);
    function listHeads(uint, bytes32, uint) external view returns (bytes32);
    function linkedNodes(bytes32) external view returns (bytes32, bytes32, bytes32, bytes32);
    function offers(bytes32) external view returns (address, uint, bytes32, int, uint, uint8);
    function positions(bytes32) external view returns (int, int);
    function positionInfo(bytes32 _legsHash) external view returns (int[] memory putAmounts, uint[] memory putStrikes);
    function addLegHash(uint[] calldata _putStrikes, int[] calldata _putAmounts) external;
    function depositFunds(address _to) external returns (bool success);
    function withdrawAllFunds() external returns (bool success);
    function postOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index) external payable;
    function insertOrder(uint _maturity, bytes32 _legsHash, int _price, uint _amount, uint8 _index, bytes32 _name) external payable;
    function cancelOrder(bytes32 _name) external;
    function marketSell(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) external returns (uint unfilled);
    function marketBuy(uint _maturity, bytes32 _legsHash, int _limitPrice, uint _amount, uint8 _maxIterations) external returns (uint unfilled);

}