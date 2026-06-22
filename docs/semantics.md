# MIP-4 Semantics Review

## Purpose

Separate specification statements, apparent implementation behavior, experimental evidence, inferences, and unresolved questions so downstream tooling does not rely on unsupported assumptions.

## Current Verified Facts

- The documented precompile address and selector are callable on Monad Testnet.
- A real authorization-list transaction produced `dippedIntoReserve() == true` during the recorded delegated EOA balance transition.
- The comparable local cheatcode-delegation experiment did not reproduce that reserve-dip observation.
- These facts establish a verified sufficient condition and a local/Testnet divergence, not the complete MIP-4 state machine.

## What the Specification Says

The repository has verified the documented precompile address and selector against Monad Testnet. A source-by-source semantics review is still needed before broader claims are recorded here.

## What the Implementation Appears to Do

Observed Testnet behavior appears to expose a reserve violation during a delegated EOA's temporary transition below 10 MON and to return `false` again after its balance is restored. The mechanism and exact threshold remain unverified.

## What We Have Verified Experimentally

- The precompile is callable at `0x0000000000000000000000000000000000001001`.
- Selector `0x3a61584e` returns an ABI-encoded boolean.
- Malformed calldata used in the recorded experiment reverted with `input is invalid`.
- A real Testnet authorization-list transaction produced `dippedIntoReserve() == true` during a 19 MON to 9 MON transition for a protocol-created delegated EOA.
- Local `vm.signAndAttachDelegation()` reproduced delegated routing but not that reserve-dip observation.

## What We Can Infer

- Delegated execution routing and reserve-balance tracking are distinct behaviors.
- The successful Testnet setup is a verified sufficient condition.
- The current evidence does not establish the complete MIP-4 state machine or prove which parts of the setup are required.

## Open Questions

- What is the exact reserve threshold boundary?
- What happens when execution starts below reserve?
- How do sender and sponsor roles affect tracking?
- What is the lifetime and scope of reserve state?
- Which account classes and balance changes participate?

## Next Steps

- Complete the threshold, below-reserve, sender/sponsor, and lifetime experiments.
- Link each semantic claim to a specification section, implementation reference, transaction, or reproducible command.
- Mark each claim as specified, verified, inferred, hypothesis, or unverified.
