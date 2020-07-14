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

    constructor (address _feldmexTokenAddress) public {
        feldmexTokenAddress = _feldmexTokenAddress;
    }

    function setBaseFee(uint _baseOptionsFeeDenominator) onlyOwner public {
        require(_baseOptionsFeeDenominator >= 500);
        baseOptionsFeeDenominator = _baseOptionsFeeDenominator;
    }

    function setSpecificFee(address _optionsAddress, uint _specificOptionsFeeDenominator) onlyOwner public {
        require(_specificOptionsFeeDenominator >= 500 || _specificOptionsFeeDenominator == 0);
        specificOptionsFeeDenominator[_optionsAddress] = _specificOptionsFeeDenominator;
    }

    function setFlatEtherFees(uint _exchageFlatEtherFee, uint _multiLegExchnageFlatEtherFee) onlyOwner public {
        exchangeFlatEtherFee = _exchageFlatEtherFee;
        multiLegExchangeFlatEtherFee = _multiLegExchnageFlatEtherFee;
    }


    function deleteSpecificFee(address _optionsAddress) onlyOwner public {
        delete specificOptionsFeeDenominator[_optionsAddress];
    }

    function fetchFee(address _optionsAddress) public view returns (uint _feeDenominator) {
        _feeDenominator = specificOptionsFeeDenominator[_optionsAddress];
        if (_feeDenominator==0) _feeDenominator = baseOptionsFeeDenominator;
    }

    function setBaseFeeImmunity(address _addr, bool _feeImmunity) onlyOwner public {
        feeImmunity[_addr] = _feeImmunity;
    }

    function setSpecificFeeImmunity(address _optionsAddress, address _addr, bool _feeImmunity) public {
        require(msg.sender == owner || msg.sender == _optionsAddress);
        specificFeeImmunity[_optionsAddress][_addr] = _feeImmunity;
    }

    function isFeeImmune(address _optionsAddress, address _addr) public view returns (bool _feeImmunity) {
        _feeImmunity = feeImmunity[_addr] || specificFeeImmunity[_optionsAddress][_addr];
    }
}
