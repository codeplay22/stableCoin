// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
// import{console} from "forge-std/console.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import{console} from "../lib/forge-std/src/console.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract DSCEngine is ReentrancyGuard {
    //////////////////////
    //   Errors        //
    ////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    //  State Variables //
    ////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LiquidationBonus = 10; // this means a 10% bonus

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////
    //  Events //
    ////////////////////

    event CollateralDeposited( address indexed user,address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token,uint256 amount);

    //////////////////////
    //   Modifier      //
    ////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
            _;
        }
    }

    //////////////////////
    //   Functions     //
    ////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dcsAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {

            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {

            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]); 

        }

        i_dsc = DecentralizedStableCoin(dcsAddress);

    }


    /////////////////////////
    // External Functions  //
    //////////////////// ///

    /*
    *@param tokenCollateralAddress The address of the token to deposit as  collateral
    *@param amountCollateral The amount of collateral to deposit.
    *@param amountDscToMint The amount of decentralized stablecoin to mint
    *@notice this function will deposit your collateral and mint DSC in one transaction
    */

    function depositCollateralAndMintDSc(address tokenCollateralAddress,uint256 amountCollateral, uint256 amountDscToMint) external {

        depositCollateral(tokenCollateralAddress,amountCollateral);
        mintDsc(amountDscToMint);

    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collaterl deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant

    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);

        if(!success){

            revert DSCEngine_TransferFailed();

        }
    }


 
    
 
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this line will ever hit...
    }


    // in order to redeem collateral:
    // 1. health factor must be over 1 After collateral pulled 
    //DRY: Don't repeat yourself
    function redeemCollateral(address tokenCollateralAddress,uint256 amountCollateral) 
    public moreThanZero(amountCollateral) nonReentrant
     {
        
        _redeemCollateral(msg.sender,msg.sender,tokenCollateralAddress,amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    /**
     * 
     * @param tokenCollateralAddress The collateral Address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction.
     */


    function redeemCollateralForDsc
    (address tokenCollateralAddress,uint256 amountCollateral,uint256 amountDscToBurn)
     external
      {
        
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress,amountCollateral);
        // redeem collateral already checks health Factor.
    }

    // $200
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // If they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amountDscToMint);
        if(!minted){
            revert DSCEngine_MintFailed();
        }

    }
// If we start nearing undercollateralization, we need someone to liquidate positions

    // $100 ETH backing $50 DSC
    // $20 ETH backing $50 DSC <- DSC isn't worth $1!!

    // $75 ETH backing $50 DSC 
    // liquidator take $75 backing and burns off the $50 DSC

    // If someone is almost undercollateralized, we will pay you to liquidate them!

    /**
     * 
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor, their _healthFactor should be below
            MIN_HEALTH_FACTOR. 
     * @param debtToCover The amount of DSC you want  to burn to improve the user health factor.
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking user funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized 
     * in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized,then we wouldn't 
     * be able to incentived the liquidators.
     * For Example, if the price of the collteral plummented before anyone could be liquidated
     * 
     * Follows CEI:Checks,Effects,Interactions
     */

    function liquidate(address collateral,address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant 
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        //We want to burn their DSC "debt"
        //And take their collateral
        // Bad User: $140 ETH, $100 DSC
        // debt to cover = $100
        // $100 of DSC == ??? ETH?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);
        // And give them a 10% bonus.
        // So we are giving the liquidator $110 of WETH 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LiquidationBonus) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender,collateral,totalCollateralToRedeem);
        // we need to burn DSC
        _burnDsc(debtToCover,user,msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////////////////////////
    // Private & Internal View Fuctions  //
    //////////////////// //////////////////

    /**
     * @dev Low-Level internal function, do not call unless the function calling it is checking 
     * for health factor being broken.
     */

    function _burnDsc(uint256 amountDscToBurn,address onBehalfOf, address dscFrom) private{
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom,address(this),amountDscToBurn);
        //This condition is hypothetically unreachable
        if (!success) {
            revert DSCEngine_TransferFailed();
        }

        i_dsc.burn(amountDscToBurn);
    } 

    function _redeemCollateral
    (address from,address to, address tokenCollateralAddress,uint256 amountCollateral) private
     {

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        // Here we are updating state so we are gonna emit event here.
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        //
        bool success = IERC20(tokenCollateralAddress).transfer(to,amountCollateral);

        if(!success){
            revert DSCEngine_TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd){
        totalDscMinted = s_DSCMinted[user];
        console.log("totalDscMinted in _getAccountInformation is",totalDscMinted);
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
        console.log("collateralValueInUsd in _getAccountInformation is ",collateralValueInUsd);

    }

    function _healthFactor(address user) private view returns (uint256) {
        // total dsc minted
        // total collateral value
       
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        console.log("totalDscMinted is",totalDscMinted);
         if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        console.log("totalDscMinted is",totalDscMinted);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD)/100;
        // return (collateralValueInUsd / totalDscMinted);
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view  {
        // 1.check if they have enough health factor(do they have enough collateral?)
        // 2.Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }

    } 

    ///////////////////////////////////////
    // Public & External View Fuctions  //
    //////////////////// //////////////////
    

    function getTokenAmountFromUsd(address token,uint256 usdAmountInWei) public view returns(uint256){
        // price of ETH (token)
        // $/ETH ETH ??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price, , ,) = priceFeed.latestRoundData();
        // console.log("price is",uint256(price));
        // console.log("usdAmountInWei is",usdAmountInWei);
        //($10e18 * 1e18) / ($2000e8 * 1e10) 
        // console.log("precision is", PRECISION);
        return (usdAmountInWei * PRECISION) / (uint256 (price) * ADDITIONAL_FEED_PRECISION);
        

    } 

    function getAccountCollateralValueInUsd(address user) public view returns(uint256 totalCollateralValueInUsd){
        // loop through each collateral token, get the amount they have deposited and map it to
        // the price, to get the USD value

        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            console.log("USER IS inside the looop is",user);
            console.log("amount in getAccountCollateralValueInUsd is",amount);
            totalCollateralValueInUsd += getUsdValue(token,amount);
        }

        return totalCollateralValueInUsd;
    }


    function getUsdValue(address token,uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //The returned value from ChainLink will be 1000 * 1e8
        // 1ETH = $1000
        // console.log("amount is",amount);
        // console.log("price is", uint256(price));
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18; //(1000 * 1e8) * 1000 * 1e18;    
           
    }


    function getAccountInformation(address user) external view
     returns(uint256 totalDscMinted, uint256 collateralValueInUsd)
     {

        (totalDscMinted,collateralValueInUsd) = _getAccountInformation(user);

    }

}
