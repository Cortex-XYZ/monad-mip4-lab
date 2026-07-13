# Official Monad Reserve Balance Documentation Notes

## Purpose

Capture the parts of Monad's official Reserve Balance documentation that are relevant to this repo's MIP-4 experiments, while keeping official documentation claims separate from repo-verified Testnet evidence.

## Sources

- Documentation index: <https://docs.monad.xyz/llms.txt>
- Reserve Balance page: <https://docs.monad.xyz/developer-essentials/reserve-balance>
- Formal reserve balance specification: <https://category-labs.github.io/category-research/monad-initial-spec-proposal.pdf>
- Coq proofs: <https://category-labs.github.io/category-research/reserve-balance-coq-proofs>

Reviewed: 2026-06-25.

## What the Official Docs Say

- `user_reserve_balance` is currently 10 MON.
- Reserve Balance exists because Monad consensus operates on a delayed view of execution state under asynchronous execution.
- For reserve accounting, MON spent by an EOA is separated into gas spend and value spend.
- If a delegated EOA is called by another sender, its gas spend is zero and its value spend is MON sent out while executing that delegated EOA's code.
- For EIP-7702-delegated EOAs, the docs describe the relevant blocked case as a balance decrement that leaves the EOA below 10 MON.
- The docs state that delegated EOA transactions ending above or at 10 MON are fine.
- The docs state that delegated EOA balance changes that are unchanged or increasing are fine.
- Delegated EOAs cannot use the undelegated-account emptying exception.
- For the simpler execution-policy model, the docs distinguish excessive intermediate debits from the ending-balance check.

## How This Maps to Repo Evidence

The official docs align with Issue #1's verified Testnet boundary result:

| Case | Official-doc expectation | Repo Testnet result |
| --- | --- | --- |
| 19 MON -> 10 MON -> 19 MON | no reserve violation for above-or-at 10 MON | `false -> false -> false` |
| 19 MON -> 10 MON - 1 wei -> 19 MON | reserve violation while below 10 MON | `false -> true -> false` |

The unchanged below-reserve case is now repo-verified: a delegated EOA starting at 9 MON and remaining unchanged succeeded with `false -> false -> false`. The increasing/recovery case, such as 9 MON -> 11 MON, still needs saved Testnet evidence before it is marked verified here.

## Questions This Helps Answer

- The threshold boundary for delegated EOAs is specified as below 10 MON, not at 10 MON.
- A delegated EOA must decrement and end below 10 MON to hit the documented blocked case.
- Delegated EOAs do not get the emptying exception that undelegated senders may get.
- Below-reserve starting states are not automatically described as violations if the balance is unchanged or increases.

## Questions Still Open for This Repo

- How exactly does `dippedIntoReserve()` sample reserve state during nested calls?
- Does the precompile expose current balance state, ending-balance policy state, or another implementation checkpoint?
- Does Monad Foundry's cheatcode-delegation path intentionally omit reserve tracking, or is the divergence a tooling limitation?
- Do sender-versus-sponsor variants produce the same observations as the sponsor-submitted Testnet path?

## Usage Guidance

When updating research docs:

- Put official documentation claims under "what the docs say" or "specified behavior."
- Put transaction observations under "verified experimentally."
- Keep hypotheses separate when they combine documentation claims with incomplete local evidence.

The per-claim status vocabulary these categories feed into is defined in [semantics.md](semantics.md).
