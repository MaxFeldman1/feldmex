pragma solidity >=0.6.0;

contract mLegData {
	   //denominated in Underlying Token underlyingAssetSubUnits
    mapping(address => uint) internalUnderlyingAssetDeposits;
    
    //denominated in the legsHash asset strikeAssetSubUnits
    mapping(address => uint) internalStrikeAssetDeposits;

    //stores price and hash of (maturity, stike, price)
    struct linkedNode{
        //internalOffers[hash] => offer
        bytes32 hash;
        //internalLinkedNodes[this.name] => this
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
        internalListHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing internalOffers at the top near the head
    */
    //maturity => legsHash => headNode.name [buy w/ UnderlyingAsset, sell w/ UnderlyingAsset, buy w/ StrikeAsset, sell w/ StrikeAsset]
    mapping(uint => mapping(bytes32 => bytes32[4])) internalListHeads;
    
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) internalLinkedNodes;

    /*
        Note all internalLinkedNodes correspond to a buyOffer
        The internalOffers[internalLinkedNodes[name].hash] links to a buyOffer
    */
    
    //holds all Offer s
    mapping(bytes32 => Offer) internalOffers;

    struct position {
        int[] callAmounts;
        uint[] callStrikes;
        int[] putAmounts;
        uint[] putStrikes;
        /*
            the underlying asset maximums are inflated by underlyingAssetSubUnits
            the strike asset maximums are inflated by strikeAssetSubUnits
        */
        int maxUnderlyingAssetDebtor;
        int maxUnderlyingAssetHolder;
        int maxStrikeAssetDebtor;
        int maxStrikeAssetHolder;
    }

    //hash of position information => position
    mapping(bytes32 => position) internalPositions;


    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint underlyingAssetSubUnits;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint strikeAssetSubUnits;
    //previously recorded balances of this contract
    uint internalUnderlyingAssetReserves;
    uint internalStrikeAssetReserves;

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