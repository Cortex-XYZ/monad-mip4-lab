# ReserveGuard Feasibility Assessment

## Answer

A narrow ReserveGuard abstraction is feasible and has been implemented in [`examples/mip4-sca`](../examples/mip4-sca). It samples the MIP-4 precompile before and after a guarded call and reverts only when that call introduces a new `false -> true` transition.

## Current Verified Facts

- Solidity contracts can call the MIP-4 precompile.
- Monad Foundry v1.7.1 reproduces an unmocked delegated-account reserve dip inside `forge test`.
- The unmocked guard regression verifies that a new dip reverts and unwinds the balance transfer.
- Deterministic transition tests verify the guard's policy for new dips, pre-existing dips, healthy calls, and environments where the precompile is unavailable.
- The `anvil --monad` suite verifies the guarded flow over RPC with type-4 authorization-list transactions.
- The exact 10 MON boundary is verified on Testnet for the sponsor-submitted delegated-EOA path. State lifetime across deeper call stacks and other account classes remains open.

## Proposed Abstractions

| Implemented behavior | Current evidence |
| --- | --- |
| Raw `(active, dipped)` probe | Forge call-shape and availability tests |
| `false -> true` | Reverts and unwinds in both the real-dip and mocked regressions |
| `true -> true` | Succeeds; the guarded frame did not introduce the dip |
| `false -> false` | Succeeds |
| Precompile unavailable | Guard is a no-op, preserving portability |
| Guarded ERC-4337 execute paths | Forge unit tests and Anvil RPC integration |

## Open Questions

- Does a before/after sample remain sufficient across deeper nested calls and callbacks?
- Should production integrations fail open when the precompile is unavailable, or require an explicit Monad-only deployment mode?
- How should paymasters and multi-operation bundles expose reserve failures to wallets and users?
- Which account implementations beyond the tested EIP-7702 smart account should adopt the guard?

## Next Steps

- Add nested-call and callback regressions.
- Test paymaster-funded and multi-operation state interactions.
- Keep the guard policy narrow: it detects a newly introduced dip; it does not claim to model the complete reserve state machine.
