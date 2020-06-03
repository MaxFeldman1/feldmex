pragma solidity >=0.4.21 <0.6.0;
//import "./ERC20.sol";

interface  yield {
    /*
        It is important to note the difference between the definitions of yield and dividend used in this contract
        Dividend is defined as the proceeds that one recieves in the form of another asset when one calls the claimPublic function
        Yield is defined as the portion of the total dividends rewarded by this contract that a certain user is entitled to.
        Yield can be thought of as the ability to claim dividends
        Ownership of one token sub unit gives the owner of the token a yield of (1/totalSupply)*totalContractDividend 
        Owners of tokens may give their yield to other accounts
    */

    /*
		It should be mentioned that each contract that implements this interface would be wise to inclued one dynamically sized array of total dividends produced by the contract for each asset that is yielded
		Each time that the contract produces more revenue each array should have the value of its previous element plus the amount of the respective asset recieved pushed
		To reduce complexity it is best to ensure that all such arrays are of the same length at all times
		contracts that implement this interface would also be wize to include a mapping that maps addresses to the last index at which they claimed dividends
		however, this is not a part of the interface but rather a suggestion of an effective method of implementation

		while it may not apply to all contracts, for certain contracts it may be wize to make a public function that may be called every so often and makes external calls to bring revenue in to the contract
    */

    /*
		@Description: Emitted when there is movement of _value in yeildDistribution from
			yeildDistribution[_tokenOwner][_yeildOwner] to
			yeildDistribution[_tokenOwner][_tokenOwner]
    */
    event ClaimYield(
    	address indexed _tokenOwner,
    	address indexed _yieldOwner,
    	uint256 _value
    );

    /*
		@Description: Emitted when there is movement of _value in yeildDistribution from
			yeildDistirbution[_tokenOwner][_tokenOwner] to
			yeildDistribution[_tokenOwner][_yeildOwner]
    */
    event SendYield(
    	address indexed _tokenOwner,
    	address indexed _yieldOwner,
    	uint256 _value
    );


	//double mapping (owner of tokens) => (cowner of yield) => (amount of tokens from which to collect yield)
	function yieldDistribution(address _tokenOwner, address _yieldOwner) external view returns (uint256 allowed);

	//mapping (owner of yield) => (amount of yield)
	function totalYield(address _addr) external view returns (uint256 value);

	//mapping (token owner) => (spender) => (yield owner)
	function specificAllowance(address, address, address) external view returns (uint256);

	//mapping (address) => (whether or not to automatically claim yeild when tokens are transfered to this address)
	function autoClaimYieldDisabled(address) external view returns (bool);

	/*
		@Description: moves yield to the token owner in yieldDistribution, the mapping yieldDistribution moves yield from
			yieldDistribution[msg.sender][_yieldOwner] to
			yieldDistribution[msg.sender][msg.sender]
			Thus allowing token owners to recieve dividends on the tokens that they own

		@param address _yieldOwner: the address from which to transfer the yield
		@param uint256 _value: the amount of yield to transfer

		@return bool success: if an error occurs returns false if no error return true
	*/
	function claimYield(address _yieldOwner, uint256 _value) external returns (bool success);

	/*
		@Description: move yield from token owner to a new yieldOwner, the mapping yieldDistribution moves yield from
			yieldDistribution[msg.sender][msg.sender] to
			yieldDistribution[msg.sender][_yieldOwner]
			Thus allowing token owners to delegate their dividends to other addresses

		@param address _to: the address which receives the yield
		@param uint256 _value: the amount of yield to transfer

		@return bool success: if an error occurs returns false if no error return true		
	*/
	function sendYield(address _to, uint256 _value) external returns (bool success);

	/*
		@Description: allows users to transfer tokens much like the transfer function in the ERC20 interface however this function specifies the yeild owner of the tokens
			thus the change in the mapping yeildDistribution resulting from execution of this function will result in movement of funds from
			yeildDistribution[msg.sender][_yeildOwner]
			to
			yeildDistribution[_to][_yeildOwner] //If !autoClaim[_to] 
			or
			yeildDistribution[_to][_to] //If autoClaim[_to]

		@param address _to: the address that recieves the tokens
		@param uint256 _value: the amount of sub units of tokens to transfered
		@param address _yeildOwner: the address that owns the yeild of the funds that are to be transfered

		@return bool success: if an error occurs returns false if no error return true				
	*/
	function transferTokenOwner(address _to, uint256 _value, address _yieldOwner) external returns (bool success);

	/*
		@Description: simmilar to the approve function in the ERC20 interface however this function specifies the yeild owner of the funds that the spender may transfer

		@param address _spender: the address that may spend the funds
		@param uint256 _value: the amount of funds to allow the spender to spend
		@param address _yeildOwner: the address of the yeild owner of the funds that the spender may spend

		@return bool success: if an error occurs returns false if no error return true				
	*/
	function approveYieldOwner(address _spender, uint256 _value, address _yieldOwner) external returns (bool success);

	/*
		@Description: allows users to transfer tokens from another address after being approved to do so much like the transferFrom function in the ERC20 interface however this function specifies the yeild owner of the tokens
			thus the change in the mapping yeildDistribution resulting from execution of this function will result in movement of funds from
			yeildDistribution[_from][_yeildOwner]
			to
			yeildDistribution[_to][_yeildOwner] //If !autoClaim[_to] 
			or
			yeildDistribution[_to][_to] //If autoClaim[_to]

		@param address _to: the address that recieves the tokens
		@param uint256 _value: the amount of sub units of tokens to transfered
		@param address _yeildOwner: the address that owns the yeild of the funds that are to be transfered

		@return bool success: if an error occurs returns false if no error return true				
	*/
	function transferTokenOwnerFrom(address _from, address _to, uint256 _value, address _yieldOwner) external returns (bool success);

	/*
		@Description: allows users to claim their share of the total dividends of the contract based on their portion of totalYeild compared to the total supply
	*/
	function claimDividend() external;

	/*
		@Description: change the value of autoClaim[msg.sender] to !autoClaim[msg.sender]
	*/
	function setAutoClaimYield() external;
}