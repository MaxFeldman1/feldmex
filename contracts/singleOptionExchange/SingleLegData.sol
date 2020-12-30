pragma solidity >=0.8.0;

contract SingleLegData {
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
        /*
            long call => index: 0
            short call => index: 1
            long put => index: 2
            short put => index: 3
        */
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
	/*
		the name of all the variables for mappings start with an _
		without the _ the names of the mappings would clash with the names of their view functions specified in ISingleLegExchange
	*/
    //denominated in Underlying Token underlyingAssetSubUnits
    mapping(address => uint) _underlyingAssetDeposits;
    //denominated in the strike asset strikeAssetSubUnits
    mapping(address => uint) _strikeAssetDeposits;
    /*
        _listHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing _offers at the top near the head
    */
    //maturity => strike => headNode.name [longCall, shortCall, longPut, shortPut]
    mapping(uint => mapping(uint => bytes32[4])) _listHeads;    
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) _linkedNodes;
    /*
        Note all _linkedNodes correspond to a buyOffer
        The _offers[_linkedNodes[name].hash] links to a buyOffer
    */    
    //holds all _offers
    mapping(bytes32 => Offer) _offers;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //address of the smart contract that stores all fee information and collects all exchange fees
    address feeOracleAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint underlyingAssetSubUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint strikeAssetSubUnits;
    //previously recorded balances of this contract
    uint satReserves;
    uint scReserves;
    uint unfilled;
    address delegateAddress;


}