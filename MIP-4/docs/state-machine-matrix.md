# MIP-4 State Machine Matrix

## Purpose

Track observed `dippedIntoReserve()` behavior across balance transitions, account types, transaction paths, and caller roles without treating the full MIP-4 state machine as known.

## Current Verified Facts

- A real Monad Testnet authorization-list transaction involving a protocol-created EIP-7702 delegated EOA produced `duringDip = true` when the authority balance moved from 19 MON to 9 MON.
- In that Testnet experiment, the observations were `beforeDip = false`, `duringDip = true`, and `afterDip = false` after the balance returned to 19 MON.
- In the sponsor-submitted Testnet path, a delegated EOA moving from 19 MON to exactly 10 MON did not dip, while moving to 10 MON minus 1 wei did dip.
- In a current-balance Testnet comparison, both sponsor-submitted and delegated-authority-submitted type-4 transactions dipped when the delegated authority was decremented below 10 MON.
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and remaining unchanged succeeded with `false -> false -> false`.
- In a below-reserve Testnet path, a delegated EOA starting at 9 MON and decrementing to 8 MON reverted. Because the transaction reverted, checkpoint writes and logs did not persist; the verified observation is the failed transaction outcome, not a persisted `duringDip = true` value.
- A local Monad Foundry experiment using `vm.signAndAttachDelegation()` routed delegated execution but returned `false` before, during, and after an 11 MON to 9 MON to 11 MON transition.
- The Testnet transition above is a verified sufficient condition, not a complete description of the state machine.

## Observation Matrix

| Case | Environment | Account | Transaction path | Transaction sender | Balance movement | Outcome | Observed `dippedIntoReserve()` result | Evidence status | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| First true path | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 19 MON -> 9 MON -> 19 MON | Success | `false -> true -> false` | Verified sufficient condition | `findings.md` |
| Exact boundary | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 19 MON -> 10 MON -> 19 MON | Success | `false -> false -> false` | Verified | `0x9020ebbc1a1a52ea4a4b610051a02f105d3c0e12d682b2c088cbd6e4934fb529` |
| One wei below boundary | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 19 MON -> 9.999999999999999999 MON -> 19 MON | Success | `false -> true -> false` | Verified | `0xa1bf42734c6534728fb5554047f38fd26fc326888c3004a28b5e38284dfc4a6e` |
| Sponsor current-balance comparison | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 20.447430148844345 MON -> 9.999999999999999999 MON -> 20.447430148844345 MON | Success | `false -> true -> false` | Verified | `0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33` |
| Authority current-balance comparison | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Delegated authority | 20.447430148844345 MON -> 9.944889575194999999 MON -> 20.392319724039345 MON | Success | `false -> true -> false` | Verified with gas-accounting caveat | `0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa` |
| Below reserve, unchanged | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 9 MON -> 9 MON -> 9 MON | Success | `false -> false -> false` | Verified | `0xc12ed9c4301ff17813161dc87df7374b57d603183c9cf305f137ceb8a8309b4a` |
| Below reserve, decremented | Monad Testnet | EIP-7702 delegated EOA | Type-4 authorization-list transaction | Sponsor | 9 MON -> 8 MON intended | Reverted | Checkpoint writes reverted; receipt status is `0` | Verified failed outcome | `0xb3a7e0544f21aca52a2226c5cd92f5388e851cf02209db6dda6c6e4bfad57326` |
| Local delegated simulation | Local Monad Foundry | Cheatcode-delegated EOA | `vm.signAndAttachDelegation()` | Sponsor | 11 MON -> 9 MON -> 11 MON | Success | `false -> false -> false` | Local-only fidelity gap | `examples/reserve-probes/test/DelegatedDrain.t.sol` |

## Open Questions

- Does the observed `< 10 MON` boundary also hold for other sender, sponsor, and account-class combinations?
- Does sender classification change reserve tracking in cases other than the current-balance below-threshold comparison?
- Which difference between protocol-created and cheatcode-created delegation explains the observed divergence?
- Does the result depend on touched-account or checkpoint classification?
- Can the below-reserve recovery case, 9 MON -> 11 MON, be reproduced with saved Testnet evidence?

## Next Steps

- Add saved evidence for the below-reserve recovery path if needed.
- Compare additional sponsor-submitted and authority-submitted boundary variants if needed.
- Attach transaction hashes, commands, and raw outputs to each matrix row.
