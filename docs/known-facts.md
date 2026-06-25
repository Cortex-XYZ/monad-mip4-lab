# Known Facts

## Purpose

Record facts that have been verified by this repository's experiments and keep them separate from hypotheses and open questions.

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

## Open Questions

- Does the boundary behavior depend on sender, sponsor, or delegated account classification?
- Does the same boundary behavior reproduce outside the successful Testnet authorization-list path?

## Next Steps

- Use the same evidence format for below-reserve initial-state tests.
- Keep Issue #1 scoped to this tested path if closing it; open follow-up issues for other sender or account-class variants.
