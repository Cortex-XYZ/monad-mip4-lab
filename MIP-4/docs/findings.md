# MIP-4 Findings

## Research Goal

Understand and verify the behavior of MIP-4 (Reserve Balance Introspection) through direct experimentation rather than specification review alone.

## Verification Log

### Finding 1: The MIP-4 precompile is live on Monad Testnet

The MIP-4 specification defines a reserve-balance precompile at address:

```txt
0x0000000000000000000000000000000000001001
```

with function selector:

```txt
0x3a61584e
```

Test:

```bash
cast call \
  --rpc-url https://testnet-rpc.monad.xyz \
  0x0000000000000000000000000000000000001001 \
  0x3a61584e
```

Result:

```txt
0x0000000000000000000000000000000000000000000000000000000000000000
```

Interpretation:

```txt
false
```

Conclusion:

The precompile exists on Monad Testnet and returns a valid ABI-encoded boolean.

Source:

* https://github.com/monad-crypto/MIPs/blob/main/MIPs/MIP-4.md

---

### Finding 2: Input validation matches the specification

Test:

```bash
cast call \
  --rpc-url https://testnet-rpc.monad.xyz \
  0x0000000000000000000000000000000000001001 \
  0x3a61584e00
```

Result:

```txt
execution reverted: input is invalid
```

Conclusion:

Malformed calldata is rejected exactly as described in the specification.

Source:

* https://github.com/monad-crypto/MIPs/blob/main/MIPs/MIP-4.md

---

### Finding 3: Solidity integration works

Minimal wrapper:

```solidity
interface IReserveBalance {
    function dippedIntoReserve() external returns (bool);
}

contract ReserveProbe {
    address constant RESERVE_BALANCE = address(0x1001);

    function probe() external returns (bool) {
        return IReserveBalance(RESERVE_BALANCE).dippedIntoReserve();
    }
}
```

Result:

```bash
forge build
```

completed successfully.

Conclusion:

Solidity contracts can represent and call the MIP-4 precompile interface.

---

### Finding 4: Standard Foundry does not simulate MIP-4

Test:

```bash
forge test -vvv
```

Result:

```txt
call to non-contract address 0x0000000000000000000000000000000000001001
```

Conclusion:

Standard Foundry does not recognize Monad-specific precompiles and therefore cannot simulate MIP-4 behavior.

This is expected because the execution environment does not contain Monad extensions.

---

### Finding 5: Monad Foundry simulates MIP-4

The same test was executed using Monad Foundry.

Result:

```txt
[PASS] testProbeReturnsFalse()
```

Conclusion:

Monad Foundry includes Monad-specific execution behavior and correctly simulates the MIP-4 precompile.

Source:

* https://docs.monad.xyz/tooling-and-infra/toolkits/monad-foundry

---

## Current Understanding

The reserve-balance check is transaction-scoped.

Based on the Monad Initial Specification Proposal, reserve-balance violations are determined by examining touched accounts whose balances changed during execution.

The condition is approximately:

```txt
balance changed
AND account is not a smart contract
AND balance < reserve threshold
```

When this condition becomes true for a touched account, execution enters a reserve-balance violation state.

Source:

* https://category-labs.github.io/category-research/monad-initial-spec-proposal.pdf

Current hypothesis:

`dippedIntoReserve()` exposes that transaction-level violation state during execution.

This has not yet been verified through a successful true-path experiment.

---

## Open Questions

1. What is the exact reserve-balance threshold calculation?
2. Which account types are exempt?
3. What is the smallest transaction that causes a reserve-balance violation?
4. Can `dippedIntoReserve()` be forced to return `true` on Monad Testnet?
5. What application patterns become possible once contracts can observe reserve-balance violations during execution?

---

## Next Experiment

Design and execute a transaction that intentionally causes a reserve-balance violation and verify:

```txt
dippedIntoReserve() == true
```

Once verified, compare the false-path and true-path execution traces and document the differences.

## Delegated EOA local Foundry measurement

Date: 2026-06-22

### Claim tested

A delegated EOA created with `vm.signAndAttachDelegation` should return `true` from `dippedIntoReserve()` after its balance decrements below the 10 MON reserve.

### Experiment

- Monad Foundry: `forge 1.5.0-stable-monad`
- EVM version: `prague`
- Authority EOA balance starts at 11 MON
- Authority delegates to `DelegatedDrain`
- Sponsor calls authority address
- Delegated execution sends 2 MON out
- Authority balance becomes 9 MON
- `dippedIntoReserve()` is called during execution

### Result

Temporary drain and restore:

- beforeBalance: 11 MON
- duringBalance: 9 MON
- afterBalance: 11 MON
- beforeDip: false
- duringDip: false
- afterRestore: false

Final below-reserve no-restore:

- beforeBalance: 11 MON
- duringBalance: 9 MON
- beforeDip: false
- duringDip: false
- transaction did not revert

### Conclusion

`vm.signAndAttachDelegation` verifies EIP-7702 code routing locally, but it does not reproduce Monad reserve-balance violation tracking in this experiment.

Local Monad Foundry is therefore inconclusive for the exact state transition that causes `dippedIntoReserve()` to return true.

Next step: test with a real Monad Testnet type-0x04 transaction carrying an authorization list.

## First verified dippedIntoReserve() == true

Date: 2026-06-22

### Claim tested

A real Monad Testnet EIP-7702 delegated EOA should return true from `dippedIntoReserve()` when its balance is decremented below the 10 MON reserve during execution.

### Setup

- Network: Monad Testnet
- EIP-7702 path: real authorization-list transaction
- Authority EOA delegated to `TestnetDelegatedProbe`
- Sponsor submitted the transaction and paid gas
- Authority started with 19 MON
- Probe drained 10 MON to a refund sink
- Authority temporarily dropped to 9 MON
- Probe called MIP-4 `dippedIntoReserve()`
- Probe refunded 10 MON back to authority
- Probe called MIP-4 again

### Observed result

- lastBeforeBalance: 19 MON
- lastDuringBalance: 9 MON
- lastAfterBalance: 19 MON

- lastBeforeDip: false
- lastDuringDip: true
- lastAfterDip: false

### Conclusion

This is the first verified `dippedIntoReserve() == true`.

A protocol-created EIP-7702 delegated EOA whose balance is decremented from above 10 MON to below 10 MON during transaction execution causes `dippedIntoReserve()` to return true.

Local Monad Foundry with `vm.signAndAttachDelegation` did not reproduce this reserve-balance state transition, even though it reproduced delegated code routing. Therefore, local cheatcode delegation is not equivalent to the real Monad Testnet EIP-7702 authorization path for this reserve-balance experiment.

### Remaining open question

This verifies a sufficient transition, not the complete state machine.

Next boundary tests:

1. Above reserve -> exactly 10 MON should probably return false.
2. Above reserve -> 10 MON minus 1 wei should probably return true.
3. Already below reserve -> unchanged or increased should return false.
4. Already below reserve -> decremented further may return true for delegated EOAs.

## Sender vs sponsor comparison

Date: 2026-07-02

### Claim tested

Changing the transaction sender from a sponsor to the delegated authority may affect reserve-balance tracking.

### Hypothesis

`dippedIntoReserve()` may behave differently when:

- a sponsor submits the type-4 authorization-list transaction; versus
- the delegated authority submits the type-4 authorization-list transaction directly.

### Setup

- Network: Monad Testnet
- EIP-7702 path: real type-4 authorization-list transaction
- Authority: `0x1ef26b741ddd257073f01e81e220fe61262f43b5`
- Sponsor: `0xF156a49d339918cAae23243C661BCca0537f0de4`
- Delegated implementation: `0xa3301516d31ed7d6b63380bead4ba66bc9ed6f2d`
- Refund sink: `0x955B96ac0D1589A27254fF3B5b3dCa214a341cd2`
- Probe: `probeDrainRestore(address,uint256)`
- Target during balance for the sponsor case: `9999999999999999999` wei

This was a current-balance comparison, not the original 19 MON default experiment. The authority was funded above 19 MON before the comparison.

### Steps

Run the same delegated probe path twice:

```sh
KEYSTORE_PASSWORD_FILE=.secrets/keystore-password.txt \
SKIP_START_BALANCE_CHECK=1 \
TARGET_DURING_BALANCE_WEI=9999999999999999999 \
scripts/run-testnet-sender-sponsor-case.sh sponsor

KEYSTORE_PASSWORD_FILE=.secrets/keystore-password.txt \
SKIP_START_BALANCE_CHECK=1 \
TARGET_DURING_BALANCE_WEI=9999999999999999999 \
scripts/run-testnet-sender-sponsor-case.sh authority
```

The authority-submitted case signs the EIP-7702 authorization with `--self-broadcast`, because the same account signs the authorization and submits the transaction that carries it.

### Observed result

Sponsor-submitted transaction:

- Transaction: `0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33`
- Transaction type: `4`
- Status: `1`
- Gas used: `500000`
- `txFrom`: `0xF156a49d339918cAae23243C661BCca0537f0de4`
- `txTo`: `0x1ef26b741ddd257073f01e81e220fE61262F43b5`
- `startChainBalance`: `20447430148844345000`
- `lastBeforeBalance`: `20447430148844345000`
- `lastDuringBalance`: `9999999999999999999`
- `lastAfterBalance`: `20447430148844345000`
- `lastBeforeDip`: `false`
- `lastDuringDip`: `true`
- `lastAfterDip`: `false`

Authority-submitted transaction:

- Transaction: `0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa`
- Transaction type: `4`
- Status: `1`
- Gas used: `500000`
- `txFrom`: `0x1ef26b741ddd257073f01e81e220fE61262F43b5`
- `txTo`: `0x1ef26b741ddd257073f01e81e220fE61262F43b5`
- `startChainBalance`: `20447430148844345000`
- `endChainBalance`: `20392319724039345000`
- `lastBeforeBalance`: `20392319724039345000`
- `lastDuringBalance`: `9944889575194999999`
- `lastAfterBalance`: `20392319724039345000`
- `lastBeforeDip`: `false`
- `lastDuringDip`: `true`
- `lastAfterDip`: `false`

### Conclusion

For this tested current-balance path, a separate sponsor is not required to observe:

```solidity
dippedIntoReserve() == true
```

Both sender modes produced:

```text
false -> true -> false
```

when the delegated authority balance decremented below 10 MON during execution.

This does not prove that all sender and sponsor cases are equivalent. The authority-submitted transaction paid gas from the authority, so its in-probe `lastBeforeBalance` was lower than the pre-transaction chain balance.

### Remaining questions

- Does sender classification affect exact-boundary cases in other variants?
- Are there sender/sponsor differences when the balance starts below reserve?
- Does this result generalize beyond the tested `probeDrainRestore` path?
