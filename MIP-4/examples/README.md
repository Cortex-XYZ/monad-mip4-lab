# MIP-4 Examples

Runnable projects that demonstrate or probe MIP-4 (Reserve Balance Introspection) behavior.

Each example is a self-contained project folder named for what it does, with its own README, toolchain config, and dependencies. Examples may use different frameworks (Foundry, Hardhat, viem/TS, …) and pin dependencies independently.

## Examples

- [`reserve-probes/`](reserve-probes/) — Foundry project with the probe contracts (`ReserveProbe`, `ReserveTransfer`, `DelegatedDrain`, `TestnetDelegatedProbe`) and their tests. Requires Monad Foundry to simulate the `0x1001` precompile.

Examples with CI-runnable checks are added to the matrix in [`.github/workflows/test.yml`](../../.github/workflows/test.yml).
