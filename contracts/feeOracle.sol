pragma solidity >=0.6.0;
import "./interfaces/Ownable.sol";

contract feeOracle is Ownable {

    address public feldmexTokenAddress;

    uint public baseOptionsFeeDenominator = 1<<255;

    uint public exchangeFlatEtherFee = 0;

    uint public multiLegExchangeFlatEtherFee = 0;

    mapping(address => uint) public specificOptionsFeeDenominator;

    mapping(address => bool) public feeImmunity;

    //optionsContract => user => feeImmune
    mapping(address => mapping(address => bool)) public specificFeeImmunity;

    /*
        Description: setup
    */
    constructor (address _feldmexTokenAddress) public {
        feldmexTokenAddress = _feldmexTokenAddress;
    }

    /*
        @Description: set base option fee denominator

        @param uitn _baseOptionsFeeDenominator
    */
    function setBaseFee(uint _baseOptionsFeeDenominator) onlyOwner public {
        require(_baseOptionsFeeDenominator >= 500);
        baseOptionsFeeDenominator = _baseOptionsFeeDenominator;
    }

    /*
        @Description: set specific fee denominator for certain option handler contracts

        @param address _optionsAddress: address of the smart contract that handles the logic of minting options
    */
    function setSpecificFee(address _optionsAddress, uint _specificOptionsFeeDenominator) onlyOwner public {
        require(_specificOptionsFeeDenominator >= 500 || _specificOptionsFeeDenominator == 0);
        specificOptionsFeeDenominator[_optionsAddress] = _specificOptionsFeeDenominator;
    }

    /*
        @Description: set flat ether fees for posting orders on exchanges
            This is done to disincentivise placing small orders that clog up the order book

        @param uint _exchnageFlatEtherFee: the amount of ether paid by users to post an order on a single option exchange
        @param uint _multiLegExchnageFlatEtherFee: the amount of ether paid by users to post an order on a multi leg option exchange
    */
    function setFlatEtherFees(uint _exchageFlatEtherFee, uint _multiLegExchnageFlatEtherFee) onlyOwner public {
        exchangeFlatEtherFee = _exchageFlatEtherFee;
        multiLegExchangeFlatEtherFee = _multiLegExchnageFlatEtherFee;
    }


    /*
        @Description: delete fees specific to certain options handler
            this makes the fees for the given options handler the same as the base fees for all option handler contracts

        @param address _optionsAddress: address of the smart contract that handles the logic of minting options
    */
    function deleteSpecificFee(address _optionsAddress) onlyOwner public {
        delete specificOptionsFeeDenominator[_optionsAddress];
    }

    /*
        @Description: get the fee denominator that is to be used for a given options handler contract

        @param address _optionsAddress: address of the smart contract that handles the logic of minting options
    */
    function fetchFee(address _optionsAddress) public view returns (uint _feeDenominator) {
        _feeDenominator = specificOptionsFeeDenominator[_optionsAddress];
        if (_feeDenominator==0) _feeDenominator = baseOptionsFeeDenominator;
    }

    /*
        @Description: grant / revoke fee immunity to an address across all option handler contracts

        @param address _addr: the address for which to grant / revoke fee immunity
        @param bool _feeImmunity: true if fee immunity is granted false if it is revoked
    */
    function setBaseFeeImmunity(address _addr, bool _feeImmunity) onlyOwner public {
        feeImmunity[_addr] = _feeImmunity;
    }

    /*
        @Description: grant / revoke fee immunity to an address for a specific options handler contract

        @param address _optionsAddress: address of the smart contract that handles the logic of minting options
        @param address _addr: the address for which to grant / revoke fee immunity
        @param bool _feeImmunity: true if fee immunity is granted false if it is revoked
    */
    function setSpecificFeeImmunity(address _optionsAddress, address _addr, bool _feeImmunity) public {
        require(msg.sender == owner || msg.sender == _optionsAddress);
        specificFeeImmunity[_optionsAddress][_addr] = _feeImmunity;
    }

    /*
        @Description: returns wether or not a given address is fee immune on a specific options handler contract

        @param address _optionsAddress: address of the smart contract that handles the logic of minting options
        @param address _addr: the address for find the fee immunity status

        @param bool _feeImmunity: true if fee immunity has been granted false if it is not
    */
    function isFeeImmune(address _optionsAddress, address _addr) public view returns (bool _feeImmunity) {
        _feeImmunity = feeImmunity[_addr] || specificFeeImmunity[_optionsAddress][_addr];
    }
}
