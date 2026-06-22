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
| Balance crossing below 10 MON | Hypothesis |
| Sponsor-submitted transaction | Unverified as required |
| Touched-account classification | Hypothesis |

## Open Questions

- Which conditions are required, optional, or incidental?
- Is crossing the threshold required, or is spending while already below reserve sufficient?
- Does an undelegated EOA or contract account produce the same observation?
- Does the transaction sender need to differ from the delegated authority?

## Next Steps

- Vary one candidate condition at a time while preserving the known sufficient condition where possible.
- Record negative results as evidence rather than treating them as proof that a condition is impossible.
- Update the table only when a condition is experimentally isolated.
