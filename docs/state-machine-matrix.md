# MIP-4 State Machine Matrix

## Purpose

Track observed `dippedIntoReserve()` behavior across balance transitions, account types, transaction paths, and caller roles without treating the full MIP-4 state machine as known.

## Current Verified Facts

- A real Monad Testnet authorization-list transaction involving a protocol-created EIP-7702 delegated EOA produced `duringDip = true` when the authority balance moved from 19 MON to 9 MON.
- In that Testnet experiment, the observations were `beforeDip = false`, `duringDip = true`, and `afterDip = false` after the balance returned to 19 MON.
- A local Monad Foundry experiment using `vm.signAndAttachDelegation()` routed delegated execution but returned `false` before, during, and after an 11 MON to 9 MON to 11 MON transition.
- The Testnet transition above is a verified sufficient condition, not a complete description of the state machine.

## Observation Matrix

| Start balance | During balance | End balance | Account | Execution path | Transaction sender | Sponsor/caller | Crossed below 10 MON | Observed result | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 19 MON | 9 MON | 19 MON | EIP-7702 delegated EOA | Real Monad Testnet authorization-list transaction | Sponsor | Sponsor | Yes | `false -> true -> false` | `notes/findings.md` |
| 11 MON | 9 MON | 11 MON | Cheatcode-delegated EOA | Local Monad Foundry `vm.signAndAttachDelegation()` | Sponsor | Sponsor | Yes | `false -> false -> false` | `test/DelegatedDrain.t.sol` |

## Open Questions

- Is the boundary condition `< 10 MON` or `<= 10 MON`?
- What happens when an account starts below reserve?
- Does sender classification change reserve tracking?
- Which difference between protocol-created and cheatcode-created delegation explains the observed divergence?
- Does the result depend on touched-account or checkpoint classification?

## Next Steps

- Add exact-boundary observations at 10 MON and 10 MON minus 1 wei.
- Add below-reserve initial-state observations.
- Compare sponsor-submitted and authority-submitted transactions.
- Attach transaction hashes, commands, and raw outputs to each matrix row.
