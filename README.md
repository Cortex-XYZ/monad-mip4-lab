# Monad MIP-4 Lab

Research notes and experiments investigating MIP-4 (Reserve Balance Introspection).

## Questions

- Is MIP-4 live on testnet?
- Does the documented selector work?
- Does input validation match the specification?
- Can Solidity contracts call the precompile?
- Does Monad Foundry simulate the behavior correctly?

## Results

### Verified

- Precompile exists at `0x1001`
- Selector `0x3a61584e` returns ABI-encoded bool
- Invalid calldata reverts with `input is invalid`
- Solidity integration works
- Monad Foundry simulates the precompile

### Pending

- Determine exact reserve-balance trigger conditions
- Produce a transaction where `dippedIntoReserve()` returns true

