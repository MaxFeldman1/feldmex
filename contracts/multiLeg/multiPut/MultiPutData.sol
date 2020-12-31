pragma solidity >=0.8.0;

contract MultiPutData {
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

	//denominated in the legsHash asset strikeAssetSubUnits
    mapping(address => uint) internalStrikeAssetDeposits;
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
    //address of a digital asset that represents a unit of account such as DAI
    address strikeAssetAddress;
    //address of the smart contract that handles the creation of calls and puts and thier subsequent redemption
    address optionsAddress;
    //incrementing identifier for each order that garunties unique hashes for all identifiers
    uint totalOrders;
    //number of the smallest unit in one full unit of the unit of account such as pennies in a dollar
    uint strikeAssetSubUnits;
    //previously recorded balances of this contract
    uint strikeAssetReserves;
    //address of the contract that stores all fee information and collects all fees
    address feeOracleAddress;
    address delegateAddress;
    uint unfilled;
}