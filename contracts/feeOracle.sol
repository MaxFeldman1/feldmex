pragma solidity >=0.5.0;
import "./interfaces/Ownable.sol";

contract feeOracle is Ownable {

    uint public baseOptionsFeeDenominator = 1<<255;

    uint public baseExchangeFeeDenominator = 1<<255;

    uint public baseMultiLegExchangeFeeDenominator = 1<<255;

    uint public exchangeFlatEtherFee = 0;

    uint public multiLegExchangeFlatEtherFee = 0;

    mapping(address => uint) public specificOptionsFeeDenominator;

    mapping(address => uint) public specificExchangeFeeDenominator;

    mapping(address => uint) public specificMultiLegExchangeFeeDenominator;

    mapping(address => bool) public feeImmunity;

    //optionsContract => user => feeImmune
    mapping(address => mapping(address => bool)) public specificFeeImmunity;

    function setBaseFees(uint _baseOptionsFeeDenominator, uint _baseExchangeFeeDenominator, uint _baseMultiLegExchangeFeeDenominator) onlyOwner public {
        require(_baseOptionsFeeDenominator >= 500);
        require(_baseExchangeFeeDenominator >= 500 );
        require(_baseMultiLegExchangeFeeDenominator >= 500);
        baseOptionsFeeDenominator = _baseOptionsFeeDenominator;
        baseExchangeFeeDenominator = _baseExchangeFeeDenominator;
        baseMultiLegExchangeFeeDenominator = _baseMultiLegExchangeFeeDenominator;
    }

    function setSpecificFees(address _optionsAddress, uint _specificOptionsFeeDenominator, uint _specificExchangeFeeDenominator, uint _specificMultiLegExchangeFeeDenominator) onlyOwner public {
        require(_specificOptionsFeeDenominator >= 500 || _specificOptionsFeeDenominator == 0);
        require(_specificExchangeFeeDenominator >= 500 || _specificExchangeFeeDenominator == 0);
        require(_specificMultiLegExchangeFeeDenominator >= 500 || _specificMultiLegExchangeFeeDenominator == 0);
        specificOptionsFeeDenominator[_optionsAddress] = _specificOptionsFeeDenominator;
        specificExchangeFeeDenominator[_optionsAddress] = _specificExchangeFeeDenominator;
        specificMultiLegExchangeFeeDenominator[_optionsAddress] = _specificMultiLegExchangeFeeDenominator;
    }

    function setFlatEtherFees(uint _exchageFlatEtherFee, uint _multiLegExchnageFlatEtherFee) onlyOwner public {
        exchangeFlatEtherFee = _exchageFlatEtherFee;
        multiLegExchangeFlatEtherFee = _multiLegExchnageFlatEtherFee;
    }


    function deleteSpecificFees(address _optionsAddress) onlyOwner public {
        delete specificOptionsFeeDenominator[_optionsAddress];
        delete specificExchangeFeeDenominator[_optionsAddress];
        delete specificMultiLegExchangeFeeDenominator[_optionsAddress];
    }

    function fetchFee(uint8 _type) public view returns (uint _feeDenominator) {
        if (_type==0) {
            _feeDenominator = specificOptionsFeeDenominator[msg.sender];
            if (_feeDenominator==0) _feeDenominator = baseOptionsFeeDenominator;
        }
        else if (_type==1) {
            _feeDenominator = specificExchangeFeeDenominator[msg.sender];
            if (_feeDenominator==0) _feeDenominator = baseExchangeFeeDenominator;
        }
        else {
            _feeDenominator = specificMultiLegExchangeFeeDenominator[msg.sender];
            if (_feeDenominator==0) _feeDenominator = baseMultiLegExchangeFeeDenominator;
        }
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
