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

## Candidate Conditions

| Condition | Current status |
| --- | --- |
| Delegated EOA | Unverified as required |
| Real type-0x04 authorization-list transaction | Unverified as required |
| Protocol-created delegation | Unverified as required |
| Balance crossing below 10 MON | Verified for the successful Testnet path |
| Sponsor-submitted transaction | Unverified as required |
| Touched-account classification | Hypothesis |

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
- Is crossing the threshold required, or is spending while already below reserve sufficient?
- Does an undelegated EOA or contract account produce the same observation?
- Does the transaction sender need to differ from the delegated authority?

## Next Steps

- Vary one candidate condition at a time while preserving the known sufficient condition where possible.
- Record negative results as evidence rather than treating them as proof that a condition is impossible.
- Update the table only when a condition is experimentally isolated.
