# Monad Foundry Fidelity

## Answer

Monad Foundry v1.7.1 reproduces the MIP-4 reserve tracker inside `forge test`. The earlier local/Testnet divergence came from testing with `1.5.0-stable-monad`, not from an inherent Forge limitation.

The repo-local regression uses `vm.signAndAttachDelegation()` with an EIP-7702 delegated EOA funded before each isolated test transaction:

```text
11 MON -> 9 MON             false -> true
11 MON -> 9 MON -> 11 MON   false -> true -> false
```

Both cases pass on `v1.7.1-monad-v1.0.0`. The same experiment on `1.5.0-stable-monad` returned `false` throughout. The toolchain version is therefore part of the experiment definition.

## Compatibility Table

| Capability | Monad Foundry 1.5.0 | Monad Foundry 1.7.1 | `anvil --monad` | Monad Testnet |
| --- | --- | --- | --- | --- |
| MIP-4 precompile available | yes | yes | yes | yes |
| EIP-7702 delegated routing | yes | yes | yes | yes |
| Reserve tracker changes after a delegated-account dip | no in the recorded regression | yes | yes | yes |
| Real type-4 authorization-list transaction over RPC | not tested | not a `forge test` transaction | yes | yes |
| Protocol end-of-transaction reserve enforcement | not established | not established by the Forge regression | not reproduced; Anvil tracks but does not revert | verified by Testnet receipts |

## Reproduction

The Forge regression is [`examples/reserve-probes/test/DelegatedDrain.t.sol`](../examples/reserve-probes/test/DelegatedDrain.t.sol). Its project configuration enables Monad execution and test isolation:

```toml
evm_version = "prague"
network = "monad"
isolate = true
```

Run it with the pinned Monad Foundry release:

```sh
cd MIP-4/examples/reserve-probes
forge test --match-contract DelegatedDrainTest -vvv
```

The `mip4-sca` project adds an unmocked guarded-account regression and an 18-case `anvil --monad` RPC integration suite.

## What This Resolves

- A real type-4 transaction is not required merely to reproduce reserve tracking locally.
- Protocol-created delegation is not required for the tested Forge observation; cheatcode-created delegation is sufficient on v1.7.1.
- The old `false -> false` result remains useful as a version-specific regression record, but it no longer describes the current local workflow.

## Remaining Boundaries

- `vm.signAndAttachDelegation()` does not reproduce a real type-4 transaction envelope. Use `anvil --monad` when authorization-list and RPC behavior are part of the question.
- Use Testnet when the question depends on public-node behavior, live protocol enforcement, or a persisted transaction receipt.
- Keep the Monad Foundry version pinned in CI and retain the real-dip regression so future upgrades cannot silently remove tracker behavior.
