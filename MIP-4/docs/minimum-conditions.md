# Minimum Conditions for a Reserve Dip

## Purpose

Identify the smallest set of conditions required to observe:

```solidity
dippedIntoReserve() == true
```

## Current Verified Facts

The first verified sufficient condition was:

```text
protocol-created EIP-7702 delegated EOA
+ real Monad Testnet authorization-list transaction
+ balance decreases from above 10 MON to below 10 MON during execution
= dippedIntoReserve() == true
```

Monad Foundry v1.7.1 now reproduces the same reserve-dip state with `vm.signAndAttachDelegation()`. In isolated Forge tests, an EIP-7702 delegated EOA moving from 11 MON to 9 MON returns `false -> true`; restoring it to 11 MON returns `false -> true -> false`. This proves that a real type-4 transaction and protocol-created delegation are not required merely to observe `dippedIntoReserve() == true` locally.

Monad's official Reserve Balance docs say that EIP-7702-delegated EOAs hit the documented blocked case when the balance decrements and ends below 10 MON. They also say delegated EOAs ending above or at 10 MON, unchanged, or increasing are fine. This is specified behavior, not a replacement for repo-local experiment evidence.

## Candidate Conditions

| Condition | Current status |
| --- | --- |
| Delegated EOA | Unverified as required |
| Real type-4 authorization-list transaction | Not required for the tested Forge observation; still required for type-4 RPC evidence |
| Protocol-created delegation | Not required for the tested Forge observation |
| Balance crossing below 10 MON after a decrement | Verified for Testnet and local Forge delegated-EOA paths |
| Sponsor-submitted transaction | Not required for observing `true` in the tested current-balance path |
| Touched-account classification | Hypothesis |

## Current Answer Map

This table separates Monad documentation claims from repo-verified observations. Official docs can answer execution-policy questions, but they do not replace local evidence for what `dippedIntoReserve()` returns at a specific checkpoint.

| Question | Current answer | Basis | What remains |
| --- | --- | --- | --- |
| Is EIP-7702 delegation required, or can another account class trigger the same observation? | For the documented delegated-account blocked case, EIP-7702 delegation is the relevant account class. Undelegated senders have a separate emptying exception path. | Specified by Monad docs; repo true-path evidence is EIP-7702 delegated EOA only. | Test whether other account classes can make `dippedIntoReserve()` return `true`, or explicitly keep this repo scoped to delegated EOAs. |
| Is a real type-4 authorization-list transaction required, or can another transaction path reproduce it? | It is not required to make the tracker return `true`. Monad Foundry v1.7.1 reproduces the observation in `forge test` with cheatcode-created delegation. | Repo-local Forge regression plus Testnet evidence. | Use Anvil or Testnet when the question specifically concerns type-4 transaction metadata, RPC behavior, or protocol enforcement. |
| Is protocol-created delegation required, or should Foundry cheatcode-created delegation behave the same? | Protocol-created delegation is not required for the tested tracker observation. `vm.signAndAttachDelegation()` produces `false -> true` on Monad Foundry v1.7.1. | Repo-local Forge regression. | Keep the regression pinned across Monad Foundry upgrades. |
| Is the important condition simply `balance < 10 MON` after a decrement, or does touched-account/checkpoint classification matter? | The docs specify that delegated EOAs revert when the balance decrements and drops below 10 MON. The repo verified the `< 10 MON` boundary for one Testnet path. | Specified by Monad docs; partially verified by repo boundary tests. | Determine whether touched-account or checkpoint classification changes when `dippedIntoReserve()` becomes true. |
| Does the observation depend on call depth, caller role, or transaction lifetime? | Caller role is partly answered: a separate sponsor is not required in the tested current-balance path. Call depth and transaction lifetime remain open. | Repo sender/sponsor comparison. | Run lifetime and nested-call experiments with observations before debit, after debit, after nested calls, after refund, and before transaction completion. |
| Does no-restore behave differently from drain-restore? | Both paths populate the tracker locally. No-restore produces `false -> true`; drain-restore produces `false -> true -> false`. On Testnet, a below-reserve decrement reverts at transaction completion. | Local Forge and Testnet evidence. | Test whether nested calls or other account classes change when the flag clears. |
| Does an SCA / ERC-4337 path change the condition set or just expose the same condition through EntryPoint? | The `mip4-sca` implementation exposes the same delegated-account condition through EntryPoint and uses a guard to isolate a newly introduced dip. | Forge guard regressions, Anvil RPC integration, and the documented Testnet demo. | Extend coverage to paymasters, additional account implementations, and multi-operation state interactions. |

## Sender vs Sponsor Experiment Plan

The sender/sponsor candidate condition should be tested by preserving the same delegated-probe path and changing only the transaction sender where possible.

Prepared command:

```sh
scripts/run-testnet-sender-sponsor-case.sh preflight
scripts/run-testnet-sender-sponsor-case.sh sponsor
scripts/run-testnet-sender-sponsor-case.sh authority
```

Default experiment:

```text
authority starts at 19 MON
probeDrainRestore drains 9 MON + 1 wei
probe records before/during/after balances and dippedIntoReserve() values
```

The `authority` sender mode necessarily differs from the sponsor mode because the delegated authority pays gas. For that case, the in-probe `lastBeforeBalance` may be lower than the pre-transaction chain balance. That gas-spend difference should be recorded as part of the sender-classification observation, not hidden.

The direct authority-sender case also signs the authorization with `cast wallet sign-auth --self-broadcast`, because the same account signs the EIP-7702 authorization and submits the transaction carrying that authorization.

Status: executed for a current-balance comparison.

Before running the default experiment, confirm:

```sh
cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL"
cast balance "$SPONSOR" --rpc-url "$MONAD_RPC_URL"
```

The default run expects the authority to start at 19 MON. The sponsor must also have enough MON to pay the full transaction gas for the sponsor-submitted case. Prior successful sponsor-submitted probe transactions used a `500000` gas limit and reported `gasUsed = 500000`, so this should be treated as a real funding requirement rather than a cosmetic limit.

If the authority is not at 19 MON, either restore the clean starting condition or set `SKIP_START_BALANCE_CHECK=1` and document the run as non-standard.

For a funded account that is above 19 MON, a non-standard comparison can still preserve the important sender variable by computing the drain from the observed start balance:

```sh
SKIP_START_BALANCE_CHECK=1 \
TARGET_DURING_BALANCE_WEI=9999999999999999999 \
scripts/run-testnet-sender-sponsor-case.sh sponsor

SKIP_START_BALANCE_CHECK=1 \
TARGET_DURING_BALANCE_WEI=9999999999999999999 \
scripts/run-testnet-sender-sponsor-case.sh authority
```

This should be documented as a current-balance sender/sponsor comparison, not as the original 19 MON default experiment.

## Sender vs Sponsor Experiment Result

The current-balance comparison was executed on Monad Testnet with the same authority, delegated implementation, refund sink, target balance, and `probeDrainRestore` path. The changed variable was the transaction sender.

| Case | Transaction | Transaction sender | Start chain balance | In-probe before balance | During balance | After balance | Observed dips |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sponsor submits | `0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33` | Sponsor | 20.447430148844345 MON | 20.447430148844345 MON | 9.999999999999999999 MON | 20.447430148844345 MON | `false -> true -> false` |
| Authority submits directly | `0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa` | Delegated authority | 20.447430148844345 MON | 20.392319724039345 MON | 9.944889575194999999 MON | 20.392319724039345 MON | `false -> true -> false` |

For this tested path, a sponsor-submitted transaction is not required to observe `dippedIntoReserve() == true`. The direct authority-sender transaction also produced `lastDuringDip = true`.

The authority-sender case is not identical to the sponsor case because the authority pays gas. That difference explains why `lastBeforeBalance` and `lastDuringBalance` were lower in the authority-sender run.

## Boundary Experiment Result

Issue #1 isolates the `balance crossing below 10 MON` candidate condition by preserving the successful Testnet path and changing only the drain amount.

| Case | Start balance | Drain amount | During balance | Observed result | Transaction |
| --- | --- | --- | --- | --- | --- |
| Exact boundary | 19 MON | 9 MON | 10 MON | `false -> false -> false` | `0x9020ebbc1a1a52ea4a4b610051a02f105d3c0e12d682b2c088cbd6e4934fb529` |
| One wei below boundary | 19 MON | 9 MON + 1 wei | 10 MON - 1 wei | `false -> true -> false` | `0xa1bf42734c6534728fb5554047f38fd26fc326888c3004a28b5e38284dfc4a6e` |

For the tested path, the observed boundary is:

```text
balance < 10 MON
```

This result is verified for the sponsor-submitted real Monad Testnet EIP-7702 authorization-list path. It does not prove which other candidate conditions are required.

## Open Questions

- Which conditions are required, optional, or incidental?
- Does an undelegated EOA or contract account produce the same observation?
- Does touched-account classification change the observation for other account classes?

## Next Steps

- Vary one candidate condition at a time while preserving the known sufficient condition where possible.
- Record negative results as evidence rather than treating them as proof that a condition is impossible.
- Add nested-call, account-class, and below-reserve recovery rows as they are experimentally isolated.
