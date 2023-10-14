// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, and contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view and pure

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
* @title DSCEngine
* @dev Sardius
* The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
* The stablecoin has the properties:
* - Exogenous Collateral
* - Dollar Pegged
* - Algorithmically Stable
* It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC
* Our DSC system should always be "overcollateralized." At no point, should the value of all collateral <= the backed value of all the DSC.
* @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawaing collateral
* @notice This contract is very loosely base don the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////////
    // Errors
    /////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();

    /////////////////////
    // State Variables
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////
    // Events
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 indexed amount);


    /////////////////////
    // Modifiers
    /////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////////
    // Functions
    /////////////////////
    constructor(address[] memory tokenAddresses, 
                address[] memory priceFeedAddresses, 
                address dscAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////
    // External Functions
    /////////////////////

    /*
    * @param tokenCollateralAddress The address of the collateral token to deposit
    * @param amountCollateral The amount of collateral to deposit
    * @param amountDscToMint The amount of DSC to mint
    * @notice this function will deposit your collateral and mint DSC in one transaction
    */

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToMint
        ) public 
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
    * @notice follows Check Effect Interaction pattern (CEI)
    * @param tokenCollateralAddress The address of the collateral token to deposit
    * @param amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
        external moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral, tokenCollateralAddress);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    * @param tokenCollateralAddress The address of the collateral token to redeem
    * @param amountCollateral The amount of collateral to redeem
    * @param amountDscToBurn The amount of DSC to burn
    * @notice this function will redeem your collateral and burn DSC in one transaction
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);

    }

    // in order to redeem collateral:
    // 1. health factor must be over 1 after collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) 
        external 
        moreThanZero(amountCollateral) 
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
    * @notice follows Check Effect Interaction pattern (CEI)
    * @param amountDscToMint The amount of DSC to mint
    * @notice they must have more collateral value than the minimum threshold
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_DSCMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken((msg.sender)); // I don't think this would ever hit...
    }

    // If someone if almost undercollateralized, we will pay you to liquidate them!
    /**
    * @param collateral The erc20 collateral address of the collateral token to liquidate
    * @param user The address of the user to liquidate. The user's _healthFactor should be below
    * MIN_HEALTH_FACTOR
    * @param debtToCover The amount of DSC you to burn to improve the user's health factor
    * @notice You can partially liquidate a user.
    * @notice You will get a liquidation bonus for taking the user's funds.
    * @notice This function working assumes the protocol is overcollateralized at roughtly 200%
    * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able
    * to incentivze the liquidators
    * For ewxample, if the price of the collateral plummeted before anyone could be liquidated
     */
    function liquidate(address collateral, address user, uint256 debtToCover) moreThanZero(debtToCover) nonReentrant external {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
    }

    

    function getHealthFactor() external view {

    }

    //////////////////////////////////////
    // Private and Internal Functions   //
    //////////////////////////////////////

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    /*
    * Returns how close to liquidation the user is
    *
    */
    function _getAccountInformation(address user) 
        private 
        view 
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }


    function _healthFactor(address user) private view returns(uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // 1. Check health factor (do they have enough collateral?)
    // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
 
    //////////////////////////////////////////
    // Public and External View Functions   //
    //////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        // price of ETH (token)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount); 
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

}
