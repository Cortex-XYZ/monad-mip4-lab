// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Mip4ReserveGuard} from "../../src/Mip4ReserveGuard.sol";

/// Shared delegate implementations for guard testing. Used by both the forge
/// unit tests and the anvil --monad integration suite (test/anvil/).

/// Delegate implementation exposing the guard around an arbitrary call.
contract GuardHarnessImpl is Mip4ReserveGuard {
    function probe() external returns (bool active, bool dipped) {
        return _dippedIntoReserve();
    }

    function doGuarded(address target, uint256 value, bytes calldata data) external reserveGuarded {
        (bool ok,) = target.call{value: value}(data);
        require(ok, "inner call failed");
    }

    receive() external payable {}
}

/// Unguarded delegate implementation — dips and stays dipped.
contract SpenderImpl {
    function spend(address payable to, uint256 amount) external {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "spend failed");
    }

    receive() external payable {}
}

/// Receives value and immediately bounces it back — creates a transient dip
/// that recovers within the guarded frame.
contract Rebounder {
    receive() external payable {
        (bool ok,) = payable(msg.sender).call{value: msg.value}("");
        require(ok, "bounce failed");
    }
}

/// Orchestrates multi-step scenarios inside one transaction/call so the
/// tx-scoped failing set spans all steps. Each step reports outcomes instead
/// of reverting, so integration harnesses can assert via eth_call.
contract Orchestrator {
    /// Unguarded dip by `spender`, then a guarded call by `harness`.
    /// Returns whether the guarded call survived (innocence rule says it must).
    function dipThenGuardedCall(address spender, address harness, address payable recipient, uint256 guardedAmount)
        external
        returns (bool guardedCallSurvived)
    {
        SpenderImpl(payable(spender)).spend(recipient, 1 ether);
        try GuardHarnessImpl(payable(harness)).doGuarded(recipient, guardedAmount, "") {
            guardedCallSurvived = true;
        } catch {
            guardedCallSurvived = false;
        }
    }

    /// Guarded call expected to dip: returns (reverted, wasReserveDipped, balanceRestored).
    function guardedDip(address harness, address payable recipient, uint256 amount)
        external
        returns (bool reverted, bool wasReserveDipped, uint256 harnessBalanceAfter)
    {
        try GuardHarnessImpl(payable(harness)).doGuarded(recipient, amount, "") {
            reverted = false;
        } catch (bytes memory reason) {
            reverted = true;
            wasReserveDipped = reason.length == 4 && bytes4(reason) == Mip4ReserveGuard.ReserveDipped.selector;
        }
        harnessBalanceAfter = harness.balance;
    }
}
