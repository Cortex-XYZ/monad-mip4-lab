// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Mip4ReserveGuard
/// @notice Revert only when this execution frame newly causes a reserve dip.
abstract contract Mip4ReserveGuard {
    error ReserveDipped();

    address internal constant MIP4_PRECOMPILE = 0x0000000000000000000000000000000000001001;

    bytes32 private constant MIP4_SELECTOR = 0x3a61584e00000000000000000000000000000000000000000000000000000000;

    /// Cap forwarded gas in case 0x1001 is unexpected/reverting off-Monad.
    uint256 private constant MIP4_GAS = 50_000;

    function _dippedIntoReserve() internal returns (bool active, bool dipped) {
        assembly ("memory-safe") {
            mstore(0x00, MIP4_SELECTOR)
            let ok := call(MIP4_GAS, MIP4_PRECOMPILE, 0, 0x00, 4, 0x00, 0x20)
            if and(ok, eq(returndatasize(), 32)) {
                active := 1
                dipped := mload(0x00)
            }
        }
    }

    modifier reserveGuarded() {
        (, bool d0) = _dippedIntoReserve();
        _;
        (bool active, bool d1) = _dippedIntoReserve();
        if (active && !d0 && d1) revert ReserveDipped();
    }
}
