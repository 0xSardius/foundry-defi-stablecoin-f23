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

    /////////////////////
    // State Variables
    /////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////
    // Events
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////
    // External Functions
    /////////////////////

    function depositCollateralAndMintDSC() external {

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
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {

    }

    function redeemCollateral() external {

    }

    /**
    * @notice follows Check Effect Interaction pattern (CEI)
    * @param amountDscToMint The amount of DSC to mint
    * @notice they must have more collateral value than the minimum threshold
    
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken();
    }

    function burnDsc() external {

    }

    function liquidate() external {

    }

    function getHealthFactor() external view {

    }

    //////////////////////////////////////
    // Private and Internal Functions   //
    //////////////////////////////////////

    /*
    * Returns how close to liquidation the user is
    *
    */
    function _healthFactor(address user) private view returns(uint256) {

    }



    function _revertIfHealthFactorIsBroken() internal view {

    }
}
