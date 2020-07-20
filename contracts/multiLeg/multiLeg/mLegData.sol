pragma solidity >=0.6.0;

contract mLegData {
	   //denominated in Underlying Token satUnits
    mapping(address => uint) claimedToken;
    
    //denominated in the legsHash asset scUnits
    mapping(address => uint) claimedStable;

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

    /*
        listHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing offers at the top near the head
    */
    //maturity => legsHash => headNode.name [buy w/ UnderlyingAsset, sell w/ UnderlyingAsset, buy w/ StrikeAsset, sell w/ StrikeAsset]
    mapping(uint => mapping(bytes32 => bytes32[4])) public listHeads;
    
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) public linkedNodes;

    /*
        Note all linkedNodes correspond to a buyOffer
        The offers[linkedNodes[name].hash] links to a buyOffer
    */
    
    //holds all offers
    mapping(bytes32 => Offer) public offers;

    struct position {
        int[] callAmounts;
        uint[] callStrikes;
        int[] putAmounts;
        uint[] putStrikes;
        uint maxUnderlyingAssetDebtor;
        uint maxUnderlyingAssetHolder;
        uint maxStrikeAssetDebtor;
        uint maxStrikeAssetHolder;
    }

    //hash of position information => position
    mapping(bytes32 => position) public positions;


    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint satUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint scUnits;
    //previously recorded balances of this contract
    uint public satReserves;
    uint public scReserves;

    address delegateAddress;


    address taker;
    bytes32 name;

    address debtor;
    address holder;
    uint maturity;
    bytes32 legsHash;
    uint amount;
    int price;
    uint8 index;

    address feeOracleAddress;
}