# Monad Foundry Fidelity

## Purpose

Track which relevant Monad Testnet behaviors are faithfully reproduced by local Monad Foundry and identify fidelity gaps that affect MIP-4 research.

## Current Verified Facts

- `vm.signAndAttachDelegation()` reproduced EIP-7702 delegated execution routing locally.
- In the measured local transition `11 MON -> 9 MON -> 11 MON`, `dippedIntoReserve()` returned `false` before, during, and after the temporary drain.
- In the measured Testnet transition `19 MON -> 9 MON -> 19 MON`, `dippedIntoReserve()` returned `false`, then `true`, then `false`.
- These experiments establish a behavioral divergence. They do not yet identify its cause.

## Compatibility Table

| Feature                     | Local Monad Foundry | Monad Testnet |
| --------------------------- | ------------------- | ------------- |
| Delegated execution routing | yes                 | yes           |
| Reserve violation tracking  | no                  | yes           |

The reserve-tracking row describes the specific experiments above, not a claim that local Monad Foundry can never reproduce reserve tracking.

## Open Questions

- Does local execution omit a real type-0x04 transaction path or authorization-list metadata?
- Does protocol-created delegation have state or classification absent from the cheatcode?
- Are touched-account or checkpoint rules different locally?
- Is the divergence a Monad Foundry limitation, configuration issue, or bug?

## Next Steps

- Minimize the local and Testnet transactions to comparable inputs.
- Compare transaction envelopes, authorization metadata, account code, callers, and traces.
- Check current Monad Foundry documentation and known issues before classifying the divergence.
- Keep this investigation blocked on evidence until the smallest differing condition is isolated.
