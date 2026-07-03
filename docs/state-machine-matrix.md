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
| 19 MON | 10 MON | 19 MON | EIP-7702 delegated EOA | Real Monad Testnet authorization-list transaction | Sponsor | Sponsor | No | `false -> false -> false` | `0x9020ebbc1a1a52ea4a4b610051a02f105d3c0e12d682b2c088cbd6e4934fb529` |
| 19 MON | 9.999999999999999999 MON | 19 MON | EIP-7702 delegated EOA | Real Monad Testnet authorization-list transaction | Sponsor | Sponsor | Yes | `false -> true -> false` | `0xa1bf42734c6534728fb5554047f38fd26fc326888c3004a28b5e38284dfc4a6e` |
| 20.447430148844345 MON | 9.999999999999999999 MON | 20.447430148844345 MON | EIP-7702 delegated EOA | Real Monad Testnet authorization-list transaction | Sponsor | Sponsor | Yes | `false -> true -> false` | `0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33` |
| 20.447430148844345 MON | 9.944889575194999999 MON | 20.392319724039345 MON | EIP-7702 delegated EOA | Real Monad Testnet authorization-list transaction | Delegated authority | Delegated authority | Yes | `false -> true -> false` | `0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa` |
| 11 MON | 9 MON | 11 MON | Cheatcode-delegated EOA | Local Monad Foundry `vm.signAndAttachDelegation()` | Sponsor | Sponsor | Yes | `false -> false -> false` | `test/DelegatedDrain.t.sol` |

## Open Questions

- Does the observed `< 10 MON` boundary also hold for other sender, sponsor, and account-class combinations?
- What happens when an account starts below reserve?
- Does sender classification change reserve tracking in cases other than the current-balance below-threshold comparison?
- Which difference between protocol-created and cheatcode-created delegation explains the observed divergence?
- Does the result depend on touched-account or checkpoint classification?

## Next Steps

- Add below-reserve initial-state observations.
- Compare additional sponsor-submitted and authority-submitted boundary variants if needed.
- Attach transaction hashes, commands, and raw outputs to each matrix row.
