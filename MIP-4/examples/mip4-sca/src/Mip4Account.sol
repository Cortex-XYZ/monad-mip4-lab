// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/accounts/Simple7702Account.sol";
import "./Mip4ReserveGuard.sol";

/// @title Mip4Account
/// @notice Simple7702Account with reserve-dip guard on execute paths.
contract Mip4Account is Simple7702Account, Mip4ReserveGuard {
    function execute(address target, uint256 value, bytes calldata data) external virtual override reserveGuarded {
        _requireForExecute();

        bool ok = Exec.call(target, value, data, gasleft());
        if (!ok) {
            Exec.revertWithReturnData();
        }
    }

    function executeBatch(Call[] calldata calls) external virtual override reserveGuarded {
        _requireForExecute();

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            Call calldata call = calls[i];
            bool ok = Exec.call(call.target, call.value, call.data, gasleft());
            if (!ok) {
                if (callsLength == 1) {
                    Exec.revertWithReturnData();
                } else {
                    revert ExecuteError(i, Exec.getReturnData(0));
                }
            }
        }
    }
}
