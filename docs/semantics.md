# MIP-4 Semantics Review

## Purpose

Separate specification statements, apparent implementation behavior, experimental evidence, inferences, and unresolved questions so downstream tooling does not rely on unsupported assumptions.

## Current Verified Facts

- The documented precompile address and selector are callable on Monad Testnet.
- A real authorization-list transaction produced `dippedIntoReserve() == true` during the recorded delegated EOA balance transition.
- A current-balance Testnet comparison produced `dippedIntoReserve() == true` for both sponsor-submitted and delegated-authority-submitted type-4 transactions when the delegated authority balance decremented below 10 MON during execution.
- The comparable local cheatcode-delegation experiment did not reproduce that reserve-dip observation.
- These facts establish a verified sufficient condition and a local/Testnet divergence, not the complete MIP-4 state machine.

## What the Specification Says

Monad's official Reserve Balance docs state that `user_reserve_balance` is 10 MON. For EIP-7702-delegated EOAs, the documented blocked case is a balance decrement that leaves the EOA below 10 MON. The docs also state that balances ending above or at 10 MON are fine, unchanged or increasing balances are fine, and delegated EOAs cannot use the emptying exception.

See [Official Monad Reserve Balance Documentation Notes](official-reserve-balance.md).

## What the Implementation Appears to Do

Observed Testnet behavior appears to expose a reserve violation during a delegated EOA's temporary transition below 10 MON and to return `false` again after its balance is restored. The exact boundary is verified for the sponsor-submitted Testnet path. The broader mechanism and full state machine remain unverified.

## What We Have Verified Experimentally

- The precompile is callable at `0x0000000000000000000000000000000000001001`.
- Selector `0x3a61584e` returns an ABI-encoded boolean.
- Malformed calldata used in the recorded experiment reverted with `input is invalid`.
- A real Testnet authorization-list transaction produced `dippedIntoReserve() == true` during a 19 MON to 9 MON transition for a protocol-created delegated EOA.
- In the same Testnet path, reaching exactly 10 MON produced `dippedIntoReserve() == false`.
- In the same Testnet path, reaching 10 MON minus 1 wei produced `dippedIntoReserve() == true`.
- In the current-balance sender/sponsor comparison, both sponsor-submitted and authority-submitted transactions produced `false -> true -> false` while the delegated authority balance decremented below 10 MON.
- Local `vm.signAndAttachDelegation()` reproduced delegated routing but not that reserve-dip observation.

## What We Can Infer

- Delegated execution routing and reserve-balance tracking are distinct behaviors.
- The successful Testnet setup is a verified sufficient condition.
- The official docs and the boundary experiment agree that the delegated-EOA boundary is below 10 MON for the tested path.
- A separate sponsor is not required to observe `dippedIntoReserve() == true` in the tested current-balance path.
- The current evidence does not establish the complete MIP-4 state machine or prove which parts of the successful setup are required.

## Open Questions

- What happens when execution starts below reserve?
- How do sender and sponsor roles affect tracking in cases beyond the current-balance below-threshold comparison?
- What is the lifetime and scope of reserve state?
- Which account classes and balance changes participate?

## Next Steps

- Complete the below-reserve and lifetime experiments, and add sender/sponsor boundary variants only if needed.
- Link each semantic claim to a specification section, implementation reference, transaction, or reproducible command.
- Mark each claim as specified, verified, inferred, hypothesis, or unverified.
