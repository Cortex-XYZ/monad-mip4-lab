// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReserveProbe} from "../src/ReserveProbe.sol";

contract ReserveProbeTest is Test {
    ReserveProbe probe;

    function setUp() public {
        probe = new ReserveProbe();
    }

    function testProbeReturnsFalse() public {
        bool dipped = probe.probe();
        assertEq(dipped, false);
    }
}
