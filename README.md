# Monad MIP Research Lab

A common home for evidence-based research into Monad Improvement Proposals (MIPs).

This repository treats protocol behavior as a research problem: claims should be supported by reproducible evidence before they are treated as verified. Each MIP under investigation gets its own top-level folder containing all of its research documents, experiment scripts, and runnable example projects.

## MIPs

| MIP | Topic | Folder |
| --- | --- | --- |
| MIP-4 | Reserve Balance Introspection | [`MIP-4/`](MIP-4/) |

## Repository Conventions

Every MIP folder follows the same layout (omit directories that don't apply — a docs-only MIP just has `README.md` and `docs/`):

```text
MIP-N/
├── README.md      Overview, open questions, verified results, document index
├── docs/          Research writeups, findings logs, plans, presentations
├── scripts/       Experiment runners (e.g. bash + cast testnet drivers)
└── examples/      Runnable code projects, one self-contained folder per example
```

- **All code lives under `examples/`.** Each example is a self-contained project folder named for what it does (e.g. `MIP-4/examples/reserve-probes/`), with its own toolchain config and dependencies. Different examples may use different frameworks (Foundry, Hardhat, viem/TS, …) and pin dependencies independently.
- **Secrets are per-MIP.** Keystore passwords, deployed addresses, and env files live in `MIP-N/.secrets/`, which is gitignored. Experiment scripts resolve paths relative to their MIP folder.
- **Monad Foundry.** Foundry-based examples that exercise Monad-specific behavior (such as the `0x1001` reserve-balance precompile) require the Monad fork of Foundry; standard Foundry cannot simulate the precompile.

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

Conclusions should distinguish verified sufficient conditions from hypotheses and unverified behavior. Work that depends on unresolved semantics should be marked as blocked on further experiments.

### Research Board

Open work is tracked in the [Research Board](https://github.com/orgs/Cortex-XYZ/projects/1), which is linked to this repository.

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

## Adding a New MIP

1. Create `MIP-N/` with a `README.md` describing the proposal, open questions, and a document index.
2. Add `docs/`, `scripts/`, and `examples/` as the research produces them, following the layout above.
3. If an example has CI-runnable checks (e.g. a Foundry project), add its path to the matrix in [`.github/workflows/test.yml`](.github/workflows/test.yml).

## Contributing Research

1. Select a `Ready` issue from the research board.
2. State the claim or hypothesis being tested.
3. Record the exact environment, transaction path, balances, callers, commands, and outputs.
4. Separate observed facts from reasoning and conclusions.
5. Update the relevant document or test with evidence.
6. Move an issue to `Verified` only when the supporting evidence is committed and reviewable.

Negative results should be recorded as observations, not generalized beyond the tested environment.
