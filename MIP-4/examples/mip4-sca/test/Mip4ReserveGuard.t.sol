// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Mip4ReserveGuard} from "../src/Mip4ReserveGuard.sol";
import {GuardHarnessImpl} from "./helpers/TestDelegates.sol";

/// Guard unit tests — the subset provable under `forge test`.
///
/// The Monad foundry fork exposes a live MIP-4 precompile at 0x1001 (correct
/// invocation-shape behavior), but its test EVM does NOT track reserve
/// debits (verified empirically: delegated-EOA dips never mark the failing
/// set, in default and --isolate modes alike, even for DB-backed accounts).
/// Dip-dependent semantics — guard revert + unwind, transient recovery,
/// innocence rule — are therefore covered by the anvil --monad integration
/// suite (see test/anvil/), where full semantics verifiably work.
contract Mip4ReserveGuardTest is Test {
    address constant MIP4 = 0x0000000000000000000000000000000000001001;

    GuardHarnessImpl harnessImpl;
    address payable eoaGuarded;
    address payable recipient;

    function setUp() public {
        harnessImpl = new GuardHarnessImpl();
        eoaGuarded = payable(makeAddr("eoaGuarded"));
        recipient = payable(makeAddr("recipient"));

        // EIP-7702 delegation designator (0xef0100 ++ impl) on the EOA.
        vm.etch(eoaGuarded, abi.encodePacked(hex"ef0100", address(harnessImpl)));
        vm.deal(eoaGuarded, 10.5 ether);
    }

    function _guarded() internal view returns (GuardHarnessImpl) {
        return GuardHarnessImpl(eoaGuarded);
    }

    // --- probe & pass-through ---

    function test_probe_activeOnMonadFork() public {
        (bool active, bool dipped) = _guarded().probe();
        assertTrue(active);
        assertFalse(dipped);
    }

    function test_guardedCall_passesThrough() public {
        _guarded().doGuarded(recipient, 0.1 ether, "");
        assertEq(eoaGuarded.balance, 10.4 ether);
        assertEq(recipient.balance, 0.1 ether);
    }

    function test_guardedCall_bubblesInnerRevert() public {
        // A failing inner call must revert with its own reason, not be masked
        // by the guard.
        vm.expectRevert("inner call failed");
        _guarded().doGuarded(address(this), 0, abi.encodeWithSignature("alwaysReverts()"));
    }

    function alwaysReverts() external pure {
        revert("nope");
    }

    function test_contractAccount_guardDoesNotInterfere() public {
        // Plain contracts are exempt from the reserve rule; the guard must
        // never block them regardless of balance.
        vm.deal(address(harnessImpl), 10.5 ether);
        harnessImpl.doGuarded(recipient, 1 ether, "");
        assertEq(address(harnessImpl).balance, 9.5 ether);
        assertEq(recipient.balance, 1 ether);
    }

    // --- precompile invocation-shape rules (validates our CALL-shape compliance) ---

    function test_precompile_rejectsStaticcall() public view {
        (bool ok,) = MIP4.staticcall{gas: 100000}(hex"3a61584e");
        assertFalse(ok);
    }

    function test_precompile_rejectsWrongSelector() public {
        (bool ok,) = MIP4.call{gas: 100000}(hex"deadbeef");
        assertFalse(ok);
    }

    function test_precompile_rejectsExtraCalldata() public {
        (bool ok,) = MIP4.call{gas: 100000}(hex"3a61584e00");
        assertFalse(ok);
    }

    function test_precompile_rejectsValue() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = MIP4.call{value: 1, gas: 100000}(hex"3a61584e");
        assertFalse(ok);
    }

    function test_precompile_returns32ByteBool() public {
        (bool ok, bytes memory ret) = MIP4.call{gas: 100000}(hex"3a61584e");
        assertTrue(ok);
        assertEq(ret.length, 32);
        assertEq(abi.decode(ret, (bool)), false);
    }
}
