pragma solidity >=0.8.0;

/*
    This contract allows for inheriting contracts to all have the same variable at the same slots 
    this allows for creation of callee contracts for the proxy option handler contract
*/
contract FeldmexOptionsData {
	//address of the contract of the price oracle for the underlying asset in terms of the strike asset such as a price oracle for WBTC/DAI
    address oracleAddress;
    //address of the contract of the underlying digital asset such as WBTC or WETH
    address internalUnderlyingAssetAddress;
    //address of a digital asset that represents a unit of account such as DAI
    address internalStrikeAssetAddress;
    //address of the exchange is allowed to see collateral requirements for all users
    address exchangeAddress;
    //address of the FeldmexERC20Helper contract that is responsible for providing ERC20 interfaces for options
    address feldmexERC20HelperAddress;
    //address of the multi leg exchange organizer
    address mOrganizerAddress;
    //address of delegate contract that is responsible for assigning positions
    address assignOptionsDelegateAddress;
    //address of the contract that holds the info about fees
    address feeOracleAddress;
    //number of the smallest unit in one full unit of the underlying asset such as satoshis in a bitcoin
    uint underlyingAssetSubUnits;
    //number of the smallest unit in one full unit of the strike asset such as pennies in a dollar
    uint strikeAssetSubUnits;
    //previously recorded balances
    uint underlyingAssetReserves;
    uint strikeAssetReserves;


    /*
        callAmounts and putAmounts store the net position of each type of calls and puts respectively for each user at each matirity and strike
    */
    //address => maturity => strike => amount of calls
    mapping(address => mapping(uint => mapping(uint => int))) callAmounts;
    
    //address => maturity => strike => amount of puts
    mapping(address => mapping(uint => mapping(uint => int))) putAmounts;

    /*
        internalUnderlyingAssetDeposits and internalStrikeAssetDeposits refers to the amount of the underlying and strike asset respectively that each user may withdraw
    */
    //denominated in underlyingAssetSubUnits
    mapping(address => uint) internalUnderlyingAssetDeposits;
    //denominated in strikeAssetSubUnits
    mapping(address => uint) internalStrikeAssetDeposits;

    /*
        internalUnderlyingAssetCollateral maps each user to the amount of collateral in the underlying that they have locked at each maturuty for calls
        internalStrikeAssetCollateral maps each user to the amount of collateral in strike asset that they have locked at each maturity for puts
    */
    //address => maturity => amount (denominated in underlyingAssetSubUnits)
    mapping(address => mapping(uint => uint)) internalUnderlyingAssetCollateral;
    //address => maturity => amount (denominated in strikeAssetSubUnits)
    mapping(address => mapping(uint => uint)) internalStrikeAssetCollateral;


    /*
        strikes maps each user to the strikes that they have traded calls or puts on for each maturity
    */
    //address => maturity => array of strikes
    mapping(address => mapping(uint => uint[])) strikes;
    //address => maturity => strike => contained
    mapping(address => mapping(uint => mapping(uint => bool))) containedStrikes;

    /*
        satDeduction is the amount of underlying asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for calls
        scDeduction is the amount of strike asset collateral that has been excused from being locked due to long positions that offset the short positions at each maturity for puts
    */
    //address => maturity => amount of collateral not required //denominated in satUnits
    mapping(address => mapping(uint => uint)) internalUnderlyingAssetDeduction;
    //address => maturity => amount of collateral not required //denominated in scUnits
    mapping(address => mapping(uint => uint)) internalStrikeAssetDeduction;


    //store positions in call/putAmounts[helperAddress][helperMaturity] to allow us to calculate collateral requirements
    //make helper maturities extremely far out, Dec 4th, 292277026596 A.D
    uint helperMaturity = 10**20;
    address helperAddress = address(0);

    /*
        when true funds are taken from claimedToken and claimedSc reserves to meet collateral requirements
        when false funds are transfered from the address to this contract to meet collateral requirements
    */
    mapping(address => bool) internalUseDeposits;

    /*
        store most recent transfer amounts
    */
    int internalTransferAmountDebtor;
    int internalTransferAmountHolder;


    address debtor;
    address holder;
    uint maturity;
    int maxDebtorTransfer;
    int maxHolderTransfer;

    address trustedAddress;
    bool useDebtorInternalFunds;
    int premium;
}