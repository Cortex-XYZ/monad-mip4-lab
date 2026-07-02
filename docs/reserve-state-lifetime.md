# Reserve State Lifetime

## Purpose

Determine when `dippedIntoReserve()` becomes true, how long that observation persists, and what event causes it to clear during transaction execution.

## Current Verified Facts

A real Monad Testnet delegated-authority experiment observed:

```text
beforeDip = false
duringDip = true
afterDip = false
```

The authority balance moved from 19 MON to 9 MON and then returned to 19 MON. This observation is consistent with multiple possible state models and does not establish which model is implemented.

Monad's official Reserve Balance docs describe the execution policy in terms of whether the delegated EOA decrements and ends below 10 MON. The docs also describe excessive intermediate debits as allowed when the ending balance is sufficient. That supports the need to distinguish `dippedIntoReserve()` sampling behavior from transaction-level revert policy.

## Open Questions

- Does the precompile expose current execution state or transaction-local history?
- Is reserve state scoped to an account, call frame, checkpoint, or transaction?
- Is the result recomputed directly from current balances?
- Does restoring the balance always clear the result?
- Can nested calls observe different reserve state at the same execution point?
- How does precompile sampling align with the official ending-balance policy language?

## Next Steps

- Design a minimal call sequence with observations before debit, after debit, after nested calls, after refund, and before transaction completion.
- Repeat with and without balance restoration.
- Record call depth, caller, observed balance, and precompile result at every checkpoint.
- Treat all state-lifetime models as hypotheses until the experiments distinguish them.
