# Minimum Conditions for a Reserve Dip

## Purpose

Identify the smallest set of conditions required to observe:

```solidity
dippedIntoReserve() == true
```

## Current Verified Facts

The following is a verified sufficient condition:

```text
protocol-created EIP-7702 delegated EOA
+ real Monad Testnet authorization-list transaction
+ balance decreases from above 10 MON to below 10 MON during execution
= dippedIntoReserve() == true
```

Local `vm.signAndAttachDelegation()` reproduced delegated execution routing but did not reproduce the same reserve-dip result. No individual condition in the sufficient-condition set has yet been shown to be independently required.

Monad's official Reserve Balance docs say that EIP-7702-delegated EOAs hit the documented blocked case when the balance decrements and ends below 10 MON. They also say delegated EOAs ending above or at 10 MON, unchanged, or increasing are fine. This is specified behavior, not a replacement for repo-local experiment evidence.

## Candidate Conditions

| Condition | Current status |
| --- | --- |
| Delegated EOA | Unverified as required |
| Real type-0x04 authorization-list transaction | Unverified as required |
| Protocol-created delegation | Unverified as required |
| Balance crossing below 10 MON | Verified for the successful Testnet path |
| Sponsor-submitted transaction | Not required for observing `true` in the tested current-balance path |
| Touched-account classification | Hypothesis |

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
- Does the documented below-reserve behavior reproduce in this repo's below-reserve initial-state experiments?
- Does an undelegated EOA or contract account produce the same observation?
- Does the transaction sender need to differ from the delegated authority?

## Next Steps

- Vary one candidate condition at a time while preserving the known sufficient condition where possible.
- Record negative results as evidence rather than treating them as proof that a condition is impossible.
- Update the table only when a condition is experimentally isolated.
