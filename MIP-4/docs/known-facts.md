# Known Facts

## Purpose

Record facts that have been verified by this repository's experiments and keep them separate from hypotheses and open questions.

Per-claim status labels and citations are consolidated in [MIP-4 semantics review](semantics.md).

## Verified Facts

- The MIP-4 reserve-balance precompile is callable at `0x0000000000000000000000000000000000001001` on Monad Testnet.
- Selector `0x3a61584e` returns an ABI-encoded boolean.
- Malformed calldata in the recorded Testnet check reverted with `input is invalid`.
- Solidity contracts in this repo can call the precompile.
- Local Monad Foundry can simulate the MIP-4 precompile and EIP-7702 delegated execution routing.
- Local Monad Foundry did not reproduce reserve-balance violation tracking in the recorded `vm.signAndAttachDelegation()` experiment.
- A real Monad Testnet EIP-7702 authorization-list transaction produced `dippedIntoReserve() == true` while a protocol-created delegated EOA moved from 19 MON to 9 MON during execution and returned to 19 MON afterward.
- In the same sponsor-submitted Testnet authorization-list path, moving from 19 MON to exactly 10 MON produced `lastDuringDip = false`.
- In the same sponsor-submitted Testnet authorization-list path, moving from 19 MON to 10 MON minus 1 wei produced `lastDuringDip = true`.
- In a current-balance Testnet comparison using the same delegated probe, both sponsor-submitted and authority-submitted type-4 authorization-list transactions produced `lastDuringDip = true` when the delegated authority balance was decremented below 10 MON during execution.
- In a below-reserve Testnet authorization-list path, a delegated EOA starting at 9 MON and remaining unchanged succeeded with `false -> false -> false`.
- In a below-reserve Testnet authorization-list path, a delegated EOA starting at 9 MON and attempting to decrement to 8 MON reverted. Because the transaction reverted, checkpoint writes and logs did not persist; the verified observation is the failed transaction outcome.

## Official Documentation Claims

These claims come from Monad's official Reserve Balance documentation, not from this repo's experiments:

- `user_reserve_balance` is 10 MON.
- For EIP-7702-delegated EOAs, the documented blocked case is a balance decrement that leaves the EOA below 10 MON.
- Delegated EOA transactions ending above or at 10 MON are documented as fine.
- Delegated EOA balance changes that are unchanged or increasing are documented as fine.
- Delegated EOAs cannot use the undelegated-account emptying exception.

See [Official Monad Reserve Balance Documentation Notes](official-reserve-balance.md).

## Hypotheses

- The observed boundary behavior may depend on the same conditions as the successful Testnet path: protocol-created EIP-7702 delegation, type-4 authorization-list transaction, sponsor-submitted call, and delegated authority execution.

## Verified Boundary Cases

| Case | Transaction | Start balance | Drain amount | During balance | End balance | Observed dips |
| --- | --- | --- | --- | --- | --- | --- |
| Exact boundary | `0x9020ebbc1a1a52ea4a4b610051a02f105d3c0e12d682b2c088cbd6e4934fb529` | 19 MON | 9 MON | 10 MON | 19 MON | `false -> false -> false` |
| One wei below boundary | `0xa1bf42734c6534728fb5554047f38fd26fc326888c3004a28b5e38284dfc4a6e` | 19 MON | 9 MON + 1 wei | 9.999999999999999999 MON | 19 MON | `false -> true -> false` |

## Boundary Conclusion

For the tested path, reserve violation occurs when the delegated authority balance is below 10 MON, not when it is exactly 10 MON:

```text
balance < 10 MON
```

This is verified for the sponsor-submitted real Monad Testnet EIP-7702 authorization-list path. It does not prove the complete MIP-4 state machine.

## Verified Sender vs Sponsor Cases

These cases used the current funded authority balance rather than the original 19 MON default. They compare transaction sender classification while preserving the same delegated authority, implementation, refund sink, and `probeDrainRestore` path.

| Case | Transaction | `txFrom` | Start chain balance | Drain amount | During balance | End / after balance | Observed dips |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sponsor submits | `0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33` | `0xF156a49d339918cAae23243C661BCca0537f0de4` | 20.447430148844345 MON | 10.447430148844345001 MON | 9.999999999999999999 MON | 20.447430148844345 MON | `false -> true -> false` |
| Authority submits directly | `0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa` | `0x1ef26b741ddd257073f01e81e220fE61262F43b5` | 20.447430148844345 MON | 10.447430148844345001 MON | 9.944889575194999999 MON | 20.392319724039345 MON | `false -> true -> false` |

In the authority-submitted case, the authority paid gas. The in-probe `lastBeforeBalance` was therefore lower than the pre-transaction chain balance:

```text
startChainBalance = 20447430148844345000
lastBeforeBalance = 20392319724039345000
```

## Sender vs Sponsor Conclusion

For the tested current-balance path, a separate sponsor is not required to observe:

```solidity
dippedIntoReserve() == true
```

Both sender modes produced `false -> true -> false` when the delegated authority balance decremented below 10 MON during execution. This does not prove that all sender and sponsor cases are equivalent, because the authority-submitted transaction necessarily includes authority gas spend and a lower in-probe starting balance.

## Verified Below-Reserve Cases

These cases used the below-reserve authority and the same delegated probe interface.

| Case | Transaction | Start balance | Intended movement | Outcome | Observed dips |
| --- | --- | --- | --- | --- | --- |
| Below reserve, unchanged | `0xc12ed9c4301ff17813161dc87df7374b57d603183c9cf305f137ceb8a8309b4a` | 9 MON | 9 MON -> 9 MON -> 9 MON | Success | `false -> false -> false` |
| Below reserve, decremented | `0xb3a7e0544f21aca52a2226c5cd92f5388e851cf02209db6dda6c6e4bfad57326` | 9 MON | 9 MON -> 8 MON intended | Reverted | Checkpoint writes reverted |

## Below-Reserve Conclusion

For the tested below-reserve path, starting below reserve is not itself a reserve violation when the delegated EOA balance is unchanged. Attempting to decrement that below-reserve delegated EOA failed on Testnet.

## Open Questions

- Does the boundary behavior depend on sender, sponsor, or delegated account classification?
- Does the same boundary behavior reproduce outside the successful Testnet authorization-list path?
- Does `dippedIntoReserve()` expose the same state model as the official execution-policy description, or a lower-level implementation checkpoint?
- Does the below-reserve recovery case, 9 MON -> 11 MON, have saved Testnet evidence?

## Next Steps

- Add saved evidence for the below-reserve recovery path if needed.
- Keep Issue #1 scoped to this tested path if closing it; open follow-up issues for other sender or account-class variants.
