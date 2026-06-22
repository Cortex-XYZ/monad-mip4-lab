# Monad MIP-4 Lab

Research notes and experiments investigating MIP-4 (Reserve Balance Introspection) on Monad.

This repository treats protocol behavior as a research problem: claims should be supported by reproducible evidence before they are treated as verified.

## Open Research Questions

- Is the reserve boundary `< 10 MON` or `<= 10 MON`?
- What happens when an account begins below reserve?
- Does reserve tracking depend on whether the delegated EOA or a sponsor submits the transaction?
- Why does local Monad Foundry reproduce delegated execution but not the observed Testnet reserve-dip behavior?
- How long does reserve state persist during transaction execution?
- Which abstractions, if any, are supported by enough evidence for future ReserveGuard tooling?

## Results

### Verified

- Precompile exists at `0x1001`
- Selector `0x3a61584e` returns ABI-encoded bool
- Invalid calldata reverts with `input is invalid`
- Solidity integration works
- Monad Foundry simulates the precompile and delegated execution routing
- A real Monad Testnet authorization-list transaction produced `dippedIntoReserve() == true` while a protocol-created delegated EOA moved from 19 MON to 9 MON

The Testnet result is a verified sufficient condition, not a complete description of the MIP-4 state machine.

### Pending

- Determine the exact reserve threshold boundary
- Determine below-reserve initial-state behavior
- Determine whether sender and sponsor roles affect reserve tracking
- Explain the reserve-tracking divergence between local Monad Foundry and Monad Testnet

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

### Research Board

Open work is tracked in the [MIP-4 Research Board](https://github.com/orgs/Cortex-XYZ/projects/1), which is linked to this repository.

The board uses four research-specific statuses:

- `Backlog`: unresolved, dependent, or not ready for execution
- `Ready`: well-scoped with a clear experiment or research deliverable
- `In Progress`: actively being investigated or documented
- `Verified`: supported by verified evidence recorded in merged docs or tests

`Verified` is intentionally different from “done.” Completing a task does not establish that its hypothesis is correct.

### Labels

- `research`: conceptual or protocol investigation
- `experiment`: runnable tests or reproductions
- `tooling`: libraries, scripts, SDKs, or developer tooling
- `documentation`: notes and research writeups
- `blocked`: depends on unresolved evidence
- `good first research task`: small, bounded task for collaborators

## Research Documents

- [State-machine matrix](docs/state-machine-matrix.md)
- [Minimum conditions for a reserve dip](docs/minimum-conditions.md)
- [Monad Foundry fidelity](docs/foundry-fidelity.md)
- [Reserve-state lifetime](docs/reserve-state-lifetime.md)
- [MIP-4 semantics review](docs/semantics.md)
- [ReserveGuard feasibility assessment](docs/reserveguard-feasibility.md)
- [ERC-4337 research plan](research/4337-plan.md)

These documents contain current verified facts, open questions, and next steps. Placeholder or partial documents should not be read as completed findings.

## Contributing Research

1. Select a `Ready` issue from the research board.
2. State the claim or hypothesis being tested.
3. Record the exact environment, transaction path, balances, callers, commands, and outputs.
4. Separate observed facts from reasoning and conclusions.
5. Update the relevant document or test with evidence.
6. Move an issue to `Verified` only when the supporting evidence is committed and reviewable.

Do not infer the complete MIP-4 state machine from a single successful reproduction. Negative results should be recorded as observations, not generalized beyond the tested environment.
