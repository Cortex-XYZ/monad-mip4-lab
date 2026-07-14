# Reserve State Lifetime

## Purpose

Determine when `dippedIntoReserve()` becomes true, how long that observation persists, and what event causes it to clear during transaction execution.

## Current Verified Facts

Real Monad Testnet and Monad Foundry v1.7.1 delegated-authority experiments observed:

```text
beforeDip = false
duringDip = true
afterDip = false
```

On Testnet, the authority balance moved from 19 MON to 9 MON and then returned to 19 MON. The local Forge regression reproduced the same transition from 11 MON to 9 MON and back to 11 MON. A separate local no-restore path returned `false -> true` while the balance remained at 9 MON.

These observations show that the tracker becomes true after the tested debit and clears after the tested restoration. They do not yet establish whether the implementation recomputes from the current balance or updates another transaction-local checkpoint.

Monad's official Reserve Balance docs describe the execution policy in terms of whether the delegated EOA decrements and ends below 10 MON. The final MIP-4 text specifies that `dippedIntoReserve()` substitutes the current execution state for the post-execution state and considers all accounts touched in the transaction, regardless of call depth. This separates the mid-execution observation from the transaction's final enforcement outcome.

## Open Questions

- Does the implementation recompute directly from current balances or maintain an equivalent incremental failing set?
- Can different call frames observe different results as balances change within the same transaction?
- Does restoring the balance always clear the result?
- Can nested calls observe different reserve state at the same execution point?
- How does precompile sampling align with the official ending-balance policy language?

## Next Steps

- Design a minimal call sequence with observations before debit, after debit, after nested calls, after refund, and before transaction completion.
- Extend the existing with-restoration and no-restore regressions across nested calls and callbacks.
- Record call depth, caller, observed balance, and precompile result at every checkpoint.
- Treat all state-lifetime models as hypotheses until the experiments distinguish them.
