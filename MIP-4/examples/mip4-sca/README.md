# mip4-sca — MIP-4-Aware ERC-4337 Smart Wallet on Monad

A 7702-delegated ERC-4337 smart account whose execute path uses Monad's
MIP-4 reserve-balance introspection precompile (`0x1001`) to detect when a
UserOperation dips an account below the 10 MON reserve — and reverts **just
that op**, so one bad op no longer kills an entire bundle at Monad's
end-of-transaction protocol check.

**Read [`docs/SPEC.md`](docs/SPEC.md) first** — it is the driving document:
problem, MIP-4 primer, architecture, component specs, flows, and the
production-readiness story. Background evidence for the MIP-4 semantics this
project relies on lives in the lab's [MIP-4 research docs](../../docs/).

## The problem, in one paragraph

On Monad, an EOA that has delegated code via EIP-7702 must keep a 10 MON
reserve. The check runs **at the end of the whole transaction**: if any
delegated account involved in the transaction ended a frame below reserve
(the "failing set"), the entire transaction reverts. An ERC-4337 bundle is
one transaction containing many users' UserOperations — so a single op that
dips its own account below 10 MON reverts *everyone's* ops and burns the
bundler's gas. MIP-4 adds a precompile that lets a contract ask, mid-
transaction, "has anything dipped into reserve so far?" — which is exactly
what an account needs to fail fast on its own op instead of poisoning the
bundle.

## How it works

The design is two small pieces layered on a stock account:

- **`src/Mip4ReserveGuard.sol`** — a reusable guard primitive with no
  storage and no constructor, inheritable by any account implementation.
  `_dippedIntoReserve()` calls the `0x1001` precompile (selector
  `0x3a61584e`, plain `CALL`, gas-capped at 50k) and reports
  `(active, dipped)`. The `reserveGuarded` modifier samples the flag
  **before and after** the wrapped body and reverts with `ReserveDipped()`
  only on a `false → true` transition — i.e. only when *this frame* newly
  caused a dip. If someone else's earlier op already dipped, an innocent
  guarded op does not revert (the "innocence rule"). Off Monad the
  precompile is absent, `active` stays false, and the guard is a no-op —
  the account degrades gracefully to a stock Simple7702Account.
- **`src/Mip4Account.sol`** — eth-infinitism `Simple7702Account` (v0.8.0,
  canonical EntryPoint v0.8) with `execute`/`executeBatch` overridden to add
  the `reserveGuarded` modifier. The revert unwinds the op's state changes
  inside `EntryPoint.innerHandleOp`, which catches it and emits
  `UserOperationEvent(success=false)` — the bundle transaction itself
  survives, and the account never enters the failing set.
- **`src/UnguardedAccount.sol`** — control contract for demos and
  differential tests: byte-for-byte the same account minus the guard, used
  to show the whole-bundle revert the guard prevents.

## Layout

| Path | What |
|---|---|
| `src/Mip4ReserveGuard.sol` | Guard primitive: `reserveGuarded` modifier + raw precompile probe |
| `src/Mip4Account.sol` | Reference account: `Simple7702Account` + guard on execute paths |
| `src/UnguardedAccount.sol` | Guard-less control for contrast runs |
| `test/` | Forge unit tests (guard pass-through, precompile call-shape, access control, ERC-1271, differential parity vs stock account) |
| `demo/src/integration-anvil.ts` | Integration suite against real Monad semantics via `anvil --monad`: dip→revert+unwind, transient recovery, innocence rule, full 3-op EntryPoint bundle |
| `demo/src/*` | Monad testnet demo: setup, Path A (direct `handleOps` + `--contrast` run), Path B (self-hosted Alto bundler) |
| `script/DeployMip4Account.s.sol` | Deterministic CREATE2 deploy of the implementation |
| `script/DeployUnguardedAccount.s.sol` | Same, for the control implementation |
| `bundler/docker-compose.yml` | Self-hosted Alto config for Monad testnet (`--chain-type=monad`) |

## Prerequisites

- **Monad fork of Foundry** (`foundryup --network monad`) — its `forge` and
  `anvil --monad` implement the MIP-4 precompile; standard Foundry does not,
  so `forge test` fails there with `call to non-contract address 0x…1001`.
- Node ≥ 20 (for the demo/integration suite).
- Docker (only for the Alto bundler path).

## Running the tests

```bash
forge test                                      # unit tests
cd demo && npm i && npm run integration:anvil   # real reserve semantics, incl. EntryPoint bundle
```

Each environment covers a different slice of MIP-4 behavior, so the suites
are split deliberately:

| Environment | Covers | Cannot cover |
|---|---|---|
| `forge test` (tested on Monad Foundry v1.7.1) | Unmocked delegated-EOA dip tracking and unwind; deterministic guard-transition tests; precompile call-shape rules; account access control; ERC-1271; parity with the stock account | Real type-4 RPC transactions and node-level integration; end-of-tx reserve enforcement |
| `anvil --monad` (integration suite) | Real type-4 delegation and failing-set tracking: dip → revert + unwind, transient recovery, innocence rule, full 3-op EntryPoint bundle | The end-of-tx reserve *enforcement* (anvil tracks but does not revert) |
| Monad testnet (demo) | Everything, including the whole-bundle protocol revert the guard exists to prevent | — |

## Testnet demo

```bash
cp .env.example .env      # fill FUNDER_KEY (~40 testnet MON)
forge script script/DeployMip4Account.s.sol --rpc-url $MONAD_TESTNET_RPC --private-key $FUNDER_KEY --broadcast
# put the printed implementation address into .env as MIP4_ACCOUNT_IMPL
cd demo
npm run setup:testnet     # fund + 7702-delegate Alice/Bob/Carol + EntryPoint deposits
npm run demo:direct       # Path A: 3-op bundle, Bob's op dips -> true/false/true
npm run demo:direct -- --contrast   # same bundle, Bob unguarded -> WHOLE bundle reverts
# Path B (optional): self-hosted Alto bundler
cd ../bundler && docker compose --env-file ../.env up -d
cd ../demo && npm run demo:alto
```

The direct run shows the guarded outcome (Alice ✓, Bob ✗ reverted alone,
Carol ✓); the `--contrast` run swaps Bob to `UnguardedAccount` and the whole
bundle transaction reverts at Monad's end-of-tx reserve check. Secrets stay
in `.env` (gitignored); generated demo account keys land in
`demo/.accounts.json` (also gitignored).
