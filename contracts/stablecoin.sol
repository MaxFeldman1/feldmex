pragma solidity ^0.5.12;

contract stablecoin {
    uint256 public scUnits = 1000000;
    uint256 public totalSupply;

    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );

    mapping(address => uint256) balanceOf;
    mapping(address => mapping(address => uint256)) allowance;

    constructor (uint256 _initialSupply) public {
        if (_initialSupply == 0)
            _initialSupply = 21000000;
        balanceOf[msg.sender] = _initialSupply * scUnits;
        totalSupply = _initialSupply;
    }

    function transfer(address _to, uint256 _value, bool _fullUnit) public returns (bool success) {
        if (_fullUnit)
            _value*=scUnits;
        require(balanceOf[msg.sender] >= _value);

        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value, bool _fullUnit) public returns (bool success) {
        if (_fullUnit)
            _value*=scUnits;
        allowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value, bool _fullUnit) public returns (bool success) {
        if (_fullUnit)
            _value*=scUnits;
        require(_value <= balanceOf[_from]);
        require(_value <= allowance[_from][msg.sender]);

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }
    
    function addrBalance(address _addr, bool _fullUnit) public view returns (uint) {
        return (balanceOf[_addr])/((_fullUnit)? scUnits: 1);
    }
    
    function addrAllowance(address _holder, address _spender, bool _fullUnit) public view returns (uint) {
        return (allowance[_holder][_spender])/((_fullUnit)? scUnits : 1);
    }
}