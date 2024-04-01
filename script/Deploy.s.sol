// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {DelegateMarketplaceWrapper} from "../src/DelegateMarketplaceWrapper.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}