# MIP-4 Semantics Review

## Purpose

Separate specification statements, apparent implementation behavior, experimental evidence, inferences, and unresolved questions so downstream tooling does not rely on unsupported assumptions.

## Status Legend

Every claim below carries exactly one status label and at least one citation. The labels map to this repository's Claim -> Evidence -> Reasoning -> Conclusion workflow.

| Label | Meaning | Maps to workflow stage |
| --- | --- | --- |
| `specified` | Stated by official Monad docs/spec; not independently reproduced here | Claim + external Evidence |
| `verified` | Reproduced by a repo experiment with saved evidence (matrix row / findings entry) | Evidence-backed Conclusion |
| `inferred` | Follows by reasoning from verified evidence; not directly observed | Reasoning |
| `hypothesis` | Candidate explanation with a designed or designable experiment | Claim awaiting Evidence |
| `unverified` | Open question; no evidence either way | Open |

Citations reference matrix rows by name or document section headings. Transaction hashes are intentionally not inlined here; the hex lives in one place, the matrix and known-facts tables.

## Current Verified Facts

- The documented precompile address and selector are callable on Monad Testnet. `[status: verified]` — findings.md § Finding 1: The MIP-4 precompile is live on Monad Testnet; known-facts.md § Verified Facts.
- A real authorization-list transaction produced `dippedIntoReserve() == true` during the recorded delegated EOA balance transition. `[status: verified]` — findings.md § First verified dippedIntoReserve() == true; state-machine-matrix.md § Observation Matrix, row: First true path.
- A current-balance Testnet comparison produced `dippedIntoReserve() == true` for both sponsor-submitted and delegated-authority-submitted type-4 transactions when the delegated authority balance decremented below 10 MON during execution. `[status: verified]` (gas-accounting caveat on the authority case) — findings.md § Sender vs sponsor comparison; state-machine-matrix.md § Observation Matrix, rows: Sponsor current-balance comparison, Authority current-balance comparison.
- Monad Foundry v1.7.1 reproduces the reserve-dip observation with local cheatcode-created delegation: `false -> true` for no-restore and `false -> true -> false` for drain-restore. `[status: verified]` — findings.md § Monad Foundry v1.7.1 reserve tracking; foundry-fidelity.md § Reproduction; state-machine-matrix.md § Observation Matrix, rows: Local no-restore and Local drain-restore.
- Monad Foundry 1.5.0 returned `false` throughout the same local transitions. `[status: verified]` (historical, version-specific negative result) — findings.md § Historical Monad Foundry 1.5.0 measurement; foundry-fidelity.md § Compatibility Table; state-machine-matrix.md § Observation Matrix, row: Historical local 1.5.0.
- These facts establish multiple sufficient paths and a version-specific tooling difference, not the complete MIP-4 state machine. `[status: inferred]` — minimum-conditions.md § Current Verified Facts; foundry-fidelity.md § What This Resolves.

## What the Specification Says

Each item is `specified`: stated by Monad's official Reserve Balance docs and not independently reproduced in this section.

- `user_reserve_balance` is 10 MON. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say.
- For EIP-7702-delegated EOAs, the documented blocked case is a balance decrement that leaves the EOA below 10 MON. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say.
- Delegated EOA transactions ending above or at 10 MON are fine. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say.
- Unchanged or increasing balances are fine. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say.
- Delegated EOAs cannot use the undelegated-account emptying exception. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say.

See [Official Monad Reserve Balance Documentation Notes](official-reserve-balance.md).

## What the Implementation Appears to Do

- Testnet behavior shows `false -> true -> false` across a delegated EOA's temporary transition below 10 MON, with `false` returning after the balance is restored. `[status: verified]` — state-machine-matrix.md § Observation Matrix, row: First true path; reserve-state-lifetime.md § Current Verified Facts.
- MIP-4 specifies that the precompile evaluates the reserve condition using the current execution state and all accounts touched in the transaction, regardless of call depth. `[status: specified]` — official-reserve-balance.md § What the Official Docs Say; MIP-4 § Semantics.
- The observed `false -> true -> false` transition is consistent with those specified current-state semantics. `[status: verified]` — state-machine-matrix.md § Observation Matrix, rows: First true path and Local drain-restore.
- The exact boundary is verified for the sponsor-submitted Testnet path. `[status: verified]` — state-machine-matrix.md § Observation Matrix, rows: Exact boundary, One wei below boundary; known-facts.md § Boundary Conclusion.
- The broader mechanism and full state machine remain unverified. `[status: unverified]` — reserve-state-lifetime.md § Open Questions; official-reserve-balance.md § Questions Still Open for This Repo.

## What We Have Verified Experimentally

- The precompile is callable at `0x0000000000000000000000000000000000001001`. `[status: verified]` — findings.md § Finding 1: The MIP-4 precompile is live on Monad Testnet (includes the reproducible `cast call`).
- Selector `0x3a61584e` returns an ABI-encoded boolean. `[status: verified]` — findings.md § Finding 1: The MIP-4 precompile is live on Monad Testnet; known-facts.md § Verified Facts.
- Malformed calldata used in the recorded experiment reverted with `input is invalid`. `[status: verified]` — findings.md § Finding 2: Input validation matches the specification.
- A real Testnet authorization-list transaction produced `dippedIntoReserve() == true` during a 19 MON to 9 MON transition for a protocol-created delegated EOA. `[status: verified]` — findings.md § First verified dippedIntoReserve() == true; state-machine-matrix.md § Observation Matrix, row: First true path.
- In the same Testnet path, reaching exactly 10 MON produced `dippedIntoReserve() == false`. `[status: verified]` — state-machine-matrix.md § Observation Matrix, row: Exact boundary; minimum-conditions.md § Boundary Experiment Result.
- In the same Testnet path, reaching 10 MON minus 1 wei produced `dippedIntoReserve() == true`. `[status: verified]` — state-machine-matrix.md § Observation Matrix, row: One wei below boundary; minimum-conditions.md § Boundary Experiment Result.
- In the current-balance sender/sponsor comparison, both sponsor-submitted and authority-submitted transactions produced `false -> true -> false` while the delegated authority balance decremented below 10 MON. `[status: verified]` (gas-accounting caveat) — state-machine-matrix.md § Observation Matrix, rows: Sponsor current-balance comparison, Authority current-balance comparison; minimum-conditions.md § Sender vs Sponsor Experiment Result.
- Local `vm.signAndAttachDelegation()` on Monad Foundry v1.7.1 reproduced reserve tracking for both no-restore and drain-restore balance transitions. `[status: verified]` — findings.md § Monad Foundry v1.7.1 reserve tracking; implementation reference `examples/reserve-probes/test/DelegatedDrain.t.sol`; state-machine-matrix.md § Observation Matrix, rows: Local no-restore and Local drain-restore.
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and remaining unchanged succeeded with `false -> false -> false`. `[status: verified]` — state-machine-matrix.md § Observation Matrix, row: Below reserve, unchanged; known-facts.md § Verified Below-Reserve Cases.
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and attempting to decrement to 8 MON reverted; because the transaction reverted, checkpoint writes did not persist, so the verified observation is the failed outcome. `[status: verified]` (failed-outcome caveat) — state-machine-matrix.md § Observation Matrix, row: Below reserve, decremented; known-facts.md § Verified Below-Reserve Cases.

## What We Can Infer

- A real type-4 transaction and protocol-created delegation are not required merely to make the reserve tracker return `true` locally. `[status: verified]` — foundry-fidelity.md § What This Resolves; minimum-conditions.md § Current Answer Map.
- The successful Testnet setup is a verified sufficient condition. `[status: verified]` (sufficiency only; necessity of individual conditions unknown) — minimum-conditions.md § Current Verified Facts.
- The official docs and the boundary experiment agree that the delegated-EOA boundary is below 10 MON for the tested path. `[status: verified]` (agreement documented) — official-reserve-balance.md § How This Maps to Repo Evidence; known-facts.md § Boundary Conclusion.
- A separate sponsor is not required to observe `dippedIntoReserve() == true` in the tested current-balance path. `[status: verified]` — known-facts.md § Sender vs Sponsor Conclusion; minimum-conditions.md § Sender vs Sponsor Experiment Result.
- The current evidence does not establish the complete MIP-4 state machine or prove whether EIP-7702 delegation itself is required across all account classes. `[status: inferred]` — minimum-conditions.md § Candidate Conditions.

## Open Questions

- When a delegated EOA starts below reserve and then recovers, for example 9 MON to 11 MON, does that path have saved Testnet evidence? `[status: unverified]` — known-facts.md § Below-Reserve Conclusion; state-machine-matrix.md § Open Questions (recovery-case bullet).
- How do sender and sponsor roles affect tracking in cases beyond the current-balance below-threshold comparison? `[status: unverified]` — state-machine-matrix.md § Open Questions; minimum-conditions.md § Open Questions.
- What is the lifetime and scope of reserve state? `[status: unverified]` — reserve-state-lifetime.md § Open Questions.
- Which account classes and balance changes participate? `[status: unverified]` (standing hypothesis: touched-account classification) — findings.md § Current Understanding; minimum-conditions.md § Candidate Conditions, row: Touched-account classification.

## Next Steps

- Complete the lifetime experiments. Add saved evidence for the below-reserve recovery path (9 MON to 11 MON) and sender/sponsor boundary variants only if needed.
