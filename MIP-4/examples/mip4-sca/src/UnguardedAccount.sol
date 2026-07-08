// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/accounts/Simple7702Account.sol";

/// @title UnguardedAccount
/// @notice Control contract for demos and differential comparison: byte-for-byte
///         the same account as Mip4Account MINUS the MIP-4 reserve guard.
///         execute/executeBatch are the plain BaseAccount implementations, so a
///         UserOperation that dips the account below Monad's 10 MON reserve
///         completes its frame "successfully" — and the protocol then reverts
///         the ENTIRE bundle transaction at the end-of-tx reserve check.
///         Do not delegate real accounts to this on Monad.
contract UnguardedAccount is Simple7702Account {}
