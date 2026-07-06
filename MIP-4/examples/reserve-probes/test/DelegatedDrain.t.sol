// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/DelegatedDrain.sol";

contract DelegatedDrainTest is Test {
    uint256 internal constant AUTHORITY_PK = 0xA11CE;

    address payable internal authority;
    address internal sponsor;

    DelegatedDrain internal implementation;
    RefundSink internal sink;

    function setUp() public {
        authority = payable(vm.addr(AUTHORITY_PK));
        sponsor = makeAddr("sponsor");

        implementation = new DelegatedDrain();
        sink = new RefundSink();

        vm.deal(authority, 11 ether);
        vm.deal(sponsor, 100 ether);
    }

    function attachDelegationAndAssertCode() internal {
        vm.signAndAttachDelegation(address(implementation), AUTHORITY_PK);

        bytes memory code = authority.code;

        assertEq(code.length, 23, "authority should contain 7702 designator");
        assertEq(uint8(code[0]), 0xef, "bad 7702 prefix byte 0");
        assertEq(uint8(code[1]), 0x01, "bad 7702 prefix byte 1");
        assertEq(uint8(code[2]), 0x00, "bad 7702 prefix byte 2");
    }

    function testTemporaryDrainRestoreMeasurement() public {
        attachDelegationAndAssertCode();

        vm.prank(sponsor);

        (
            bool beforeDip,
            bool duringDip,
            bool afterRestore,
            uint256 beforeBalance,
            uint256 duringBalance,
            uint256 afterBalance
        ) = DelegatedDrain(authority).drainCheckRestore(sink, 2 ether);

        console2.log("temporary restore beforeBalance", beforeBalance);
        console2.log("temporary restore duringBalance", duringBalance);
        console2.log("temporary restore afterBalance", afterBalance);
        console2.log("temporary restore beforeDip", beforeDip);
        console2.log("temporary restore duringDip", duringDip);
        console2.log("temporary restore afterRestore", afterRestore);

        assertEq(beforeBalance, 11 ether);
        assertEq(duringBalance, 9 ether);
        assertEq(afterBalance, 11 ether);

        // This is now an observed fact from our previous run.
        assertFalse(beforeDip);
        assertFalse(duringDip);
        assertFalse(afterRestore);
    }

    function testFinalBelowReserveMeasurement() public {
        attachDelegationAndAssertCode();

        vm.prank(sponsor);

        (
            bool beforeDip,
            bool duringDip,
            uint256 beforeBalance,
            uint256 duringBalance
        ) = DelegatedDrain(authority).drainCheckNoRestore(sink, 2 ether);

        console2.log("final below reserve beforeBalance", beforeBalance);
        console2.log("final below reserve duringBalance", duringBalance);
        console2.log("final below reserve beforeDip", beforeDip);
        console2.log("final below reserve duringDip", duringDip);

        assertEq(beforeBalance, 11 ether);
        assertEq(duringBalance, 9 ether);

        // Do NOT assert duringDip yet.
        // This test is measuring the behavior, not assuming the answer.
    }
}
