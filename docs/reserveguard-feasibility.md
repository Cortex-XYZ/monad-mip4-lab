# ReserveGuard Feasibility Assessment

## Purpose

Assess whether current MIP-4 evidence supports ReserveGuard-style Solidity abstractions without implementing ReserveGuard.

## Current Verified Facts

- Solidity contracts can call the MIP-4 precompile.
- A real Testnet authorization-list transaction has produced `dippedIntoReserve() == true` during a delegated EOA balance transition from 19 MON to 9 MON.
- The exact threshold, state lifetime, sender sensitivity, and below-reserve behavior remain unverified.
- Local Monad Foundry did not reproduce the reserve-dip result in the measured cheatcode-delegation experiment.

## Proposed Abstractions

| Proposed abstraction           | Evidence status            |
| ------------------------------ | -------------------------- |
| `dipped()` wrapper             | likely safe                |
| `assertHealthy()`              | unverified policy decision |
| `reserveHealthy` modifier      | unverified policy decision |
| base `ReserveAware` contract   | blocked                    |
| reserve-aware router/framework | future work                |

“Likely safe” means a thin wrapper can preserve the precompile result. It does not mean the result's complete semantics are known.

## Open Questions

- What policy should `assertHealthy()` enforce, and at which execution checkpoints?
- Can a modifier make a reliable claim if reserve state can clear after balance restoration?
- Which account and transaction contexts are supported?
- How should local tests handle the observed Monad Foundry fidelity gap?

## Next Steps

- Resolve threshold, state-lifetime, and sender/sponsor questions.
- Define explicit safety claims for each proposed abstraction.
- Require evidence for every policy decision before implementation.
- Keep ReserveGuard implementation blocked on further experiments.
