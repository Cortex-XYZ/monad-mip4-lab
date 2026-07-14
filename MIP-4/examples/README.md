# MIP-4 Examples

Runnable projects that demonstrate or probe MIP-4 (Reserve Balance Introspection) behavior.

Each example is a self-contained project folder named for what it does, with its own README, toolchain config, and dependencies. Examples may use different frameworks (Foundry, Hardhat, viem/TS, …) and pin dependencies independently.

## Examples

- [`reserve-probes/`](reserve-probes/) — Foundry project with the probe contracts (`ReserveProbe`, `ReserveTransfer`, `DelegatedDrain`, `TestnetDelegatedProbe`) and their tests. The recorded local reserve-tracker regressions use Monad Foundry `v1.7.1-monad-v1.0.0`.
- [`mip4-sca/`](mip4-sca/) — MIP-4-aware ERC-4337 smart account (Foundry + viem/TS): a 7702-delegated `Simple7702Account` whose execute path uses the `0x1001` precompile to revert only the UserOperation that dips below the 10 MON reserve, instead of poisoning the whole bundle. Includes unit tests, an `anvil --monad` integration suite, a testnet demo, and an Alto bundler config. Requires Monad Foundry.

Examples with CI-runnable checks are added to the matrix in [`.github/workflows/test.yml`](../../.github/workflows/test.yml).
