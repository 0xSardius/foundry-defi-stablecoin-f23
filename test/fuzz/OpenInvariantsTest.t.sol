// SPDX-License-Identifier: MIT

// What are our invariants?
// What aspects should always hold?

// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/Invariant.sol";
import {DeployDSC} from "../../script/DeployDSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../src/HelperConfig.sol";

contract OpenInvariantsTest is Test, StdInvariant {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStablecoin dsc;


    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        targetContract(address(dsce));
    }
}
