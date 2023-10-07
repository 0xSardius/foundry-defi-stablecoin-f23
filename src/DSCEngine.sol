// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

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

contract DSCEngine {
    /////////////////////
    // Errors
    /////////////////////
    error DSCEngine__MustBeMoreThanZero();



    /////////////////////
    // Modifiers
    /////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }





    function depositCollateralAndMintDSC() external {

    }

    /**
    * @param tokenCollateralAddress The address of the collateral token to deposit
    * @param amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
        ) external moreThanZero(amountCollateral) 
        {

    }

    function redeemCollateralForDsc() external {

    }

    function redeemCollateral() external {

    }

    function mintDsc() external {

    }

    function burnDsc() external {

    }

    function liquidate() external {

    }

    function getHealthFactor() external view {

    }
}
