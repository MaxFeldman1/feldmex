pragma solidity >=0.8.0;

contract MultiCallData {
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
        */
        uint8 index;
    }

    struct position {
        int[] callAmounts;
        uint[] callStrikes;
        //inflated by underlyingAssetSubUnits
        int maxUnderlyingAssetDebtor;
        //inflated by underlyingAssetSubUnits
        int maxUnderlyingAssetHolder;
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

    //denominated in Underlying Token underlyingAssetSubUnits
    mapping(address => uint) internalUnderlyingAssetDeposits;
    /*
        internalListHeads are the heads of 4 linked lists that hold buy and sells of calls and puts
        the linked lists are ordered by price with the most enticing internalOffers at the top near the head
    */
    //maturity => legsHash => headNode.name [buy, sell]
    mapping(uint => mapping(bytes32 => bytes32[2])) internalListHeads;
    //holds all nodes node.name is the identifier for the location in this mapping
    mapping (bytes32 => linkedNode) internalLinkedNodes;
    /*
        Note all internalLinkedNodes correspond to a buyOffer
        The internalOffers[internalLinkedNodes[name].hash] links to a buyOffer
    */
    //holds all internalOffers
    mapping(bytes32 => Offer) internalOffers;
    //hash of position information => position
    mapping(bytes32 => position) internalPositions;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address underlyingAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint underlyingAssetSubUnits;
    //previously recorded balances of this contract
    uint underlyingAssetReserves;
    //address of the contract that stores all fee information and collects all fees
    address feeOracleAddress;
    address delegateAddress;
    uint unfilled;
}