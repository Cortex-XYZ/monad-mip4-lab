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
