pragma solidity >=0.4.21 <0.9.0;

interface ISingleLegExchange {

/*
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
        uint strike;
        uint price;
        uint amount;

        uint8 index;
    }
    
    event offerPosted(
        bytes32 name,
        uint maturity,
        uint strike,
        uint price,
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
*/

	function underlyingAssetDeposits(address _owner) external view returns (uint);
	function strikeAssetDeposits(address _owner) external view returns (uint);
	function listHeads(uint _maturity, uint _strike, uint _index) external view returns (bytes32);
    //returns linkedNode struct
	function linkedNodes(bytes32 _name) external view returns (bytes32 hash, bytes32 name, bytes32 next, bytes32 previous);
    //returns Offer struct
	function offers(bytes32 _hash) external view returns (address offerer, uint maturity, uint strike, uint price, uint amount, uint8 index);
	function depositFunds(address _to) external returns (bool success);
	function withdrawAllFunds(bool _token) external returns(bool success);
	function postOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call) external payable;
	function insertOrder(uint _maturity, uint _strike, uint _price, uint _amount, bool _buy, bool _call, bytes32 _name) external payable;
	function cancelOrder(bytes32 _name) external;
	function marketSell(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external returns(uint unfilled);
	function marketBuy(uint _maturity, uint _strike, uint _limitPrice, uint _amount, uint8 _maxIterations, bool _call) external returns (uint unfilled);
}