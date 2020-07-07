pragma solidity >=0.5.0;
import "./interfaces/Ownable.sol";

contract feeOracle is Ownable {

    uint public baseOptionsFeeDenominator;

    uint public baseExchangeFeeDenominator;

    uint public baseMultiLegExchangeFeeDenominator;

    mapping(address => uint) public specificOptionsFeeDenominator;

    mapping(address => uint) public specificExchangeFeeDenominator;

    mapping(address => uint) public specificMultiLegExchangeFeeDenominator;

    function setBaseFees(uint _baseOptionsFeeDenominator, uint _baseExchangeFeeDenominator, uint _baseMultiLegExchangeFeeDenominator) onlyOwner public {
        baseOptionsFeeDenominator = _baseOptionsFeeDenominator;
        baseExchangeFeeDenominator = _baseExchangeFeeDenominator;
        baseMultiLegExchangeFeeDenominator = _baseMultiLegExchangeFeeDenominator;
    }

    function setSpecificFees(address _optionsAddress, uint _specificOptionsFeeDenominator, uint _specificExchangeFeeDenominator, uint _specificMultiLegExchangeFeeDenominator) onlyOwner public {
        specificOptionsFeeDenominator[_optionsAddress] = _specificOptionsFeeDenominator;
        specificExchangeFeeDenominator[_optionsAddress] = _specificExchangeFeeDenominator;
        specificMultiLegExchangeFeeDenominator[_optionsAddress] = _specificMultiLegExchangeFeeDenominator;
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
}
