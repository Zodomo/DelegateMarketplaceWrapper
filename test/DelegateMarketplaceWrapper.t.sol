// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DelegateMarketplaceWrapper} from "../src/DelegateMarketplaceWrapper.sol";

contract DelegateMarketplaceWrapperTest is Test {
    DelegateMarketplaceWrapper public wrapper;

    function setUp() public {
        wrapper = new DelegateMarketplaceWrapper();
    }
}
