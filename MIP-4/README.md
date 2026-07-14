# Monad MIP-4 Lab

Research notes and experiments investigating MIP-4 (Reserve Balance Introspection) on Monad.

This repository treats protocol behavior as a research problem: claims should be supported by reproducible evidence before they are treated as verified.

## Onboarding

**If you're new to Monad and Reserve Balance State machine, go through this learning resource**: [Monad Reserve Balance Tutorial](https://monadreservebalance.vercel.app/)

## Open Research Questions

- Does the observed `< 10 MON` reserve boundary from the sponsor-submitted Testnet authorization-list path hold in other execution contexts?
- Does below-reserve recovery, such as `9 MON -> 11 MON`, have saved Testnet evidence?
- Does sender classification affect reserve tracking beyond the current-balance sponsor-vs-authority comparison?
- How long does reserve state persist during transaction execution?
- Which account classes other than EIP-7702 delegated EOAs can enter the tracked reserve state?
- Which ReserveGuard policies remain reliable across nested calls and bundled operations?
- How should MIP-4-aware smart accounts handle reserve dips inside ERC-4337 bundles?

## Results

### Verified

- Precompile exists at `0x1001`
- Selector `0x3a61584e` returns ABI-encoded bool
- Invalid calldata reverts with `input is invalid`
- Solidity integration works
- Monad Foundry v1.7.1 simulates the precompile, delegated execution routing, and reserve-dip tracking in isolated `forge test` transactions
- In local Forge, an EIP-7702 delegated EOA moving from 11 MON to 9 MON produced `false -> true`; restoring it to 11 MON produced `false -> true -> false`
- A real Monad Testnet authorization-list transaction produced `dippedIntoReserve() == true` while a protocol-created delegated EOA moved from 19 MON to 9 MON
- In the same Testnet path, a delegated EOA reaching exactly 10 MON did not trigger `dippedIntoReserve()`, while reaching 10 MON minus 1 wei did trigger it
- In a current-balance Testnet comparison, both sponsor-submitted and delegated-authority-submitted type-4 transactions produced `dippedIntoReserve() == true` while the delegated authority balance decremented below 10 MON during execution
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and remaining unchanged succeeded with `false -> false -> false`
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and attempting to decrement to 8 MON reverted
- `examples/mip4-sca` contains a MIP-4-aware ERC-4337 smart account example that guards EIP-7702 delegated account execution against newly introduced reserve dips

The Testnet result is a verified sufficient condition, not a complete description of the MIP-4 state machine.

### Pending

- Save evidence for below-reserve recovery behavior, if needed
- Determine whether sender and sponsor roles affect reserve tracking in cases beyond the current-balance below-threshold comparison
- Review the `mip4-sca` example against the ERC-4337 research plan and update any stale issue state
- Extend local regressions to additional account classes, call depths, and transaction paths

## Research Workflow

Research claims should progress through an explicit evidence chain:

```text
Claim
↓
Evidence
↓
Reasoning
↓
Conclusion
```

Conclusions should distinguish verified sufficient conditions from hypotheses and unverified behavior. The full MIP-4 state machine is not yet known, and work that depends on unresolved semantics should be marked as blocked on further experiments.

### Issues

Open work and completed investigations are tracked in the repository's [GitHub Issues](https://github.com/Cortex-XYZ/monad-mip-lab/issues). An issue is ready to close when its evidence is committed and the relevant research documents state what was verified and what remains open.

### Labels

- `research`: conceptual or protocol investigation
- `experiment`: runnable tests or reproductions
- `tooling`: libraries, scripts, SDKs, or developer tooling
- `documentation`: notes and research writeups
- `blocked`: depends on unresolved evidence
- `good first research task`: small, bounded task for collaborators

## Research Documents

- [State-machine matrix](docs/state-machine-matrix.md)
- [Known facts](docs/known-facts.md)
- [Official Reserve Balance documentation notes](docs/official-reserve-balance.md)
- [Minimum conditions for a reserve dip](docs/minimum-conditions.md)
- [Monad Foundry fidelity](docs/foundry-fidelity.md)
- [Reserve-state lifetime](docs/reserve-state-lifetime.md)
- [MIP-4 semantics review](docs/semantics.md)
- [ReserveGuard feasibility assessment](docs/reserveguard-feasibility.md)
- [ERC-4337 research plan](docs/plans/4337-plan.md)

These documents separate verified observations, official protocol behavior, current conclusions, and open questions.

## Contributing Research

1. Select an open issue with a clear experiment or research deliverable.
2. State the claim or hypothesis being tested.
3. Record the exact environment, transaction path, balances, callers, commands, and outputs.
4. Separate observed facts from reasoning and conclusions.
5. Update the relevant document or test with evidence.
6. Close an issue only when the supporting evidence is committed and reviewable.

Do not infer the complete MIP-4 state machine from a single successful reproduction. Negative results should be recorded as observations, not generalized beyond the tested environment.
