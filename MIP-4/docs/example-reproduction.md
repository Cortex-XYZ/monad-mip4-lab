# MIP-4 Example Reproduction Guide

## Purpose

This guide is for developers who want to reproduce MIP-4 reserve-balance behavior through hands-on testnet experiments. It covers three progressively deeper examples, starting from the raw protocol enforcement mechanism and ending with a production-grade ERC-4337 bundler integration.

No prior knowledge of MIP-4, reserve balance, or account abstraction is assumed. Each concept is introduced when it is needed. Developers who prefer to read theory first should start with [mip-4-explained.md](mip-4-explained.md) and [minimum-conditions.md](minimum-conditions.md) before returning here.

---

## Knowledge Prerequisites

### What is reserve balance?

Monad decouples consensus from execution. Validators agree on the *ordering* of transactions before those transactions have actually run. This creates a window — currently **3 blocks (~1.2 seconds)** — where a transaction is committed to blockspace before its effects are known.

To prevent a denial-of-service attack where a sender drains their account between the time a transaction is ordered and when it executes, Monad requires every EOA to keep a minimum balance set aside. This is the **reserve balance**, currently set at **10 MON** for every EOA.

The rule: if a transaction decrements an EOA's balance and leaves it below 10 MON, the transaction reverts.

The boundary is strict:

| Ending balance | Result |
| --- | --- |
| ≥ 10 MON | Passes |
| < 10 MON | Reverts |
| Exactly 10 MON | Passes |

### The emptying transaction exception

Most users never encounter the reserve rule. An **undelegated EOA** sending its **first transaction within the prior k=3 blocks** qualifies for the emptying transaction exception — it may dip below 10 MON in that single transaction. This is why ordinary wallets can still send their full balance.

EIP-7702-delegated EOAs **do not** get this exception. That is why they are the primary subject of these experiments.

### What is MIP-4?

MIP-4 introduces a precompile at `0x0000000000000000000000000000000000001001` with a single method, `dippedIntoReserve()`. It lets a contract ask, during execution:

> "If the transaction ended right now, would Monad's reserve-balance rule consider this a violation?"

The answer is a single `bool`. It is a transaction-wide signal — it reports whether *any* touched account is currently in violation, not just the calling contract.

The check is **O(1)** because Monad tracks reserve-violation state incrementally as balances change. Calling the precompile reads already-maintained state rather than scanning all touched accounts.

For a full technical treatment, see [mip-4-explained.md](mip-4-explained.md).

### How to trigger `dippedIntoReserve() == true`

The verified sufficient condition from this repository's experiments:

```text
EIP-7702-delegated EOA
+ real Monad Testnet type-4 authorization-list transaction
+ balance decrements from above 10 MON to below 10 MON during execution
= dippedIntoReserve() == true
```

Plain smart contracts and undelegated EOA transfers do not satisfy this condition. See [minimum-conditions.md](minimum-conditions.md) for the full evidence record.

### What is EIP-7702?

EIP-7702 lets an existing EOA temporarily run smart contract code. The EOA's owner signs an authorization pointing to an implementation contract. A sponsor submits a type-4 transaction carrying that authorization. After the transaction, the EOA's code slot contains a delegation designator (`0xef0100` followed by the implementation address), and any call to the EOA address executes the implementation's code in the context of the EOA — its address, balance, and storage.

The EOA remains an EOA to the protocol. That is why Monad's reserve-balance rule still applies to it, and why `dippedIntoReserve()` can return `true` inside delegated execution.

### What is ERC-4337?

ERC-4337 is a standard for account abstraction without protocol changes. Instead of users submitting transactions directly, they sign **UserOperations** — signed intents describing what they want to do. A **bundler** collects UserOperations from many users and submits them in a single `EntryPoint.handleOps()` transaction.

The EntryPoint calls each account's `execute` function using a low-level call. If one UserOperation's execution reverts, the EntryPoint catches the failure and continues to the next operation. One bad UserOp does not kill the entire bundle — unless the revert propagates past the EntryPoint's containment boundary.

On Monad, that containment breaks when a UserOp leaves a touched EOA in reserve violation. The protocol's end-of-transaction reserve check reverts the entire `handleOps` transaction, undoing all operations including the ones that succeeded. MIP-4 + `Mip4Account` restores the per-op isolation by detecting the violation inside the failing op's frame and reverting that frame before execution ends — which unwinds the offending balance change and clears the failing set before the protocol's check runs.

---

## Tool Prerequisites

| Tool | Required for | Install |
| --- | --- | --- |
| Monad Foundry (`forge`, `cast`) | All examples | `foundryup --network monad` |
| Node.js ≥ 20 | Example 3 (TypeScript demo) | https://nodejs.org |
| Python 3 | Example 2 script (math helpers) | https://python.org |
| Git | Cloning this repository | https://git-scm.com |

All examples in this guide target Monad Testnet. Monad Foundry is required for `forge` and `cast` commands throughout. Install it with:

```bash
foundryup --network monad
```

Confirm it is active before running any command:

```bash
forge --version
# should show: forge Version: x.x.x-stable-monad
```

---

## Environment Setup

### Clone the repository

```bash
git clone https://github.com/Cortex-XYZ/monad-mip-lab.git
cd monad-mip-lab
```

### Create the secrets file

The scripts in this repository resolve private keys and deployed addresses from `MIP-4/.secrets/addresses.env` or `MIP-4/.env`. This file is gitignored at the repository root and should never be committed.

```bash
cat > MIP-4/.env << 'EOF'
MONAD_RPC_URL="https://testnet-rpc.monad.xyz"
SPONSOR_PRIVATE_KEY="0xYOUR_MAIN_WALLET_PRIVATE_KEY"
AUTHORITY="0xYOUR_SECOND_WALLET_ADDRESS"
AUTHORITY_PRIVATE_KEY="0xYOUR_SECOND_WALLET_PRIVATE_KEY"
TESTNET_DELEGATED_PROBE="0x<deployed address from this repo>"
TESTNET_REFUND_SINK="0x<deployed address from this repo>"
EOF
```

`TESTNET_DELEGATED_PROBE` and `TESTNET_REFUND_SINK` are already deployed on Monad Testnet and verified on Monadscan. You do not need to redeploy them.

Source the file before running any experiment:

```bash
source MIP-4/.env
```

### Get testnet MON

| Example | Minimum MON needed |
| --- | --- |
| Example 1 | ~0.5 MON (gas only) |
| Example 2 | ~13 MON in second wallet, ~1 MON in main wallet for gas |
| Example 3 | ~35 MON across both wallets |

Faucet: https://testnet.monad.xyz

### Verify the precompile is live

```bash
cast call 0x0000000000000000000000000000000000001001 \
  0x3a61584e \
  --rpc-url "$MONAD_RPC_URL"
```

Expected result: `0x0000000000000000000000000000000000000000000000000000000000000000` (ABI-encoded `false`).

---

## Example 1 — Reserve Balance Enforcement (EOA Transfers)

**What this demonstrates:** The raw reserve-balance enforcement mechanism at the protocol level. No contracts, no MIP-4 precompile. Two back-to-back EOA transfers where the second dips below 10 MON — the second transaction is cancelled by consensus.

**Note:** This demonstrates the enforcement mechanism that MIP-4 is built on. `dippedIntoReserve()` is not called here — there is no contract code executing inside the EOA that could call it. This is the scenario MIP-4 is designed to handle more gracefully.

### Setup

Ensure your main wallet (sponsor) is above 10 MON:

```bash
cast balance $SPONSOR_ADDRESS --ether --rpc-url "$MONAD_RPC_URL"
```

Check your current nonce:

```bash
cast nonce $SPONSOR_ADDRESS --rpc-url "$MONAD_RPC_URL"
```

### Run

Replace `YOURNONCE` with the result of the nonce check. Transaction 1 burns the emptying exception. Transaction 2 sends enough MON to drop below 10 MON.

```bash
cast send $AUTHORITY \
  --value 0.001ether \
  --nonce YOURNONCE \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$SPONSOR_PRIVATE_KEY" \
  --async \
&& cast send $AUTHORITY \
  --value 2ether \
  --nonce $((YOURNONCE + 1)) \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$SPONSOR_PRIVATE_KEY"
```

### Expected result

Transaction 1 succeeds. Transaction 2 is included in the block but its value transfer is cancelled:

```
Value: X MON — [CANCELLED]
Status: Fail
```

The second transaction still pays gas even though the transfer was cancelled. This is the protocol enforcement in action.

### What to check on Monadscan

Look up the second transaction hash on https://testnet.monadscan.com. Confirm:
- Status: Fail
- Value: `[CANCELLED]`
- Gas fee: still charged

---

## Example 2 — EIP-7702 Delegated Drain/Restore

**What this demonstrates:** `dippedIntoReserve()` returning `true` on a real Monad Testnet transaction. A sponsor submits a type-4 authorization-list transaction that attaches contract code to the authority EOA. The contract drains the EOA below 10 MON, calls the MIP-4 precompile (observing `true`), then restores the balance. The expected pattern is `false → true → false`.

This is the first verified sufficient condition for `dippedIntoReserve() == true` from this repository's experiments. See [minimum-conditions.md](minimum-conditions.md).

### Contracts used

| Contract | Address | Purpose |
| --- | --- | --- |
| `TestnetDelegatedProbe` | `0x603ef3AeAF3485E389dFA43d22185c866109652B` | Implementation attached to authority EOA via EIP-7702; calls `dippedIntoReserve()` before, during, and after drain |
| `TestnetRefundSink` | `0xE1e3319C6C3cC0033Cc46cfF53bCa2C29Cefc0f0` | Receives drained MON and refunds it on request |

Both are verified on Monadscan.

### Setup

Confirm the authority has no existing delegation:

```bash
cast code $AUTHORITY --rpc-url "$MONAD_RPC_URL"
```

Expected: `0x`

Confirm the authority balance is above 10 MON:

```bash
cast balance $AUTHORITY --ether --rpc-url "$MONAD_RPC_URL"
```

Confirm the refund sink has enough MON to cover the drain (default drain targets 9.9 MON during, so the sink needs at least `authority_balance - 9.9` MON):

```bash
cast balance $TESTNET_REFUND_SINK --ether --rpc-url "$MONAD_RPC_URL"
```

If the sink is empty, fund it:

```bash
cast send $TESTNET_REFUND_SINK \
  --value 3ether \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$SPONSOR_PRIVATE_KEY"
```

### Preflight

Run the preflight check before spending gas. It validates all conditions and prints the calculated drain amount without submitting a transaction:

```bash
bash MIP-4/scripts/run-testnet-7702-drain-restore.sh preflight
```

Confirm the printed values look correct — authority address, implementation address, start balance, drain amount, and target during-balance.

### Run

```bash
bash MIP-4/scripts/run-testnet-7702-drain-restore.sh run
```

To target a specific during-balance (must be below 10 MON):

```bash
TARGET_DURING_MON=9.5 bash MIP-4/scripts/run-testnet-7702-drain-restore.sh run
```

### Expected result

```
lastBeforeDip=false   ← above reserve before drain
lastDuringDip=true    ← below reserve — MIP-4 precompile observed
lastAfterDip=false    ← balance restored by refund sink

false -> true -> false confirmed. MIP-4 dippedIntoReserve() observed on Monad testnet. ✔
```

### Why the delegation is the key

The transaction type in the receipt will be `4` — an EIP-7702 authorization-list transaction. Before the transaction, `cast code $AUTHORITY` returns `0x`. After, it returns `0xef0100` followed by the `TestnetDelegatedProbe` address — the EIP-7702 delegation designator.

Without the delegation, there is no contract code running inside the EOA, so nothing can call `dippedIntoReserve()`. Plain contract experiments (where a smart contract's balance changes, not an EOA's) return `false → false → false` regardless of the drain amount. See [minimum-conditions.md](minimum-conditions.md) for the evidence record.

### Clearing the delegation afterward

The delegation persists after the transaction. To restore the authority to a plain EOA:

```bash
AUTH=$(cast wallet sign-auth 0x0000000000000000000000000000000000000000 \
  --private-key "$AUTHORITY_PRIVATE_KEY" \
  --rpc-url "$MONAD_RPC_URL")

cast send $AUTHORITY \
  --auth "$AUTH" \
  --value 0 \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$SPONSOR_PRIVATE_KEY"
```

Confirm: `cast code $AUTHORITY --rpc-url "$MONAD_RPC_URL"` returns `0x`.

---

## Example 3 — ERC-4337 Bundler with MIP-4 Guard

**What this demonstrates:** A production-grade integration of MIP-4 into an ERC-4337 smart account. Three EIP-7702-delegated EOAs (Alice, Bob, Carol) submit UserOperations through the canonical EntryPoint v0.8. Bob's operation would leave him below 10 MON. The `Mip4Account` guard detects this mid-execution via `dippedIntoReserve()`, reverts only Bob's frame, and the bundle commits with Alice and Carol's operations landing successfully.

Expected outcome: `success=true / success=false / success=true`

### Contracts used

| Contract | Address | Purpose |
| --- | --- | --- |
| EntryPoint v0.8 (canonical) | `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108` | Orchestrates the bundle; not deployed by this repo |
| `Mip4Account` | Deployed per-run (see below) | EIP-7702 implementation with `reserveGuarded` modifier on `execute` |
| `UnguardedAccount` | `0x6750919E4a48CcEDA04d1e2b406328d6350861b7` | Control implementation without the guard (for contrast run) |

### How the guard works

`Mip4Account` overrides `execute` with the `reserveGuarded` modifier from `Mip4ReserveGuard`:

```solidity
modifier reserveGuarded() {
    (, bool d0) = _dippedIntoReserve();  // probe before execution
    _;                                    // run the operation
    (bool active, bool d1) = _dippedIntoReserve();  // probe after
    if (active && !d0 && d1) revert ReserveDipped();
}
```

The condition `active && !d0 && d1` is the **innocence rule** — it reverts only if:
- MIP-4 is present on this chain (`active`)
- The reserve was healthy before this operation (`!d0`) — if it was already violated, reverting this frame cannot fix someone else's dip
- This operation newly caused a violation (`d1`)

When `ReserveDipped()` is thrown, the EntryPoint's `innerHandleOp` uses a low-level call to invoke each account's `execute`. A low-level call returns `false` on revert rather than propagating it. Bob's revert is absorbed, his balance change unwinds, the failing set clears, and execution continues with Carol's operation.

### Setup

**Working directory:**

```bash
cd MIP-4/examples/mip4-sca
```

**Environment file.** Create `.env` from the example:

```bash
cp .env.example .env
```

Fill in `FUNDER_KEY` with your main wallet private key. Leave `MIP4_ACCOUNT_IMPL` empty for now.

**Install demo dependencies:**

```bash
cd demo && npm install && cd ..
```

**Deploy `Mip4Account` implementation:**

```bash
forge script script/DeployMip4Account.s.sol \
  --rpc-url "$MONAD_TESTNET_RPC" \
  --private-key "$FUNDER_KEY" \
  --broadcast
```

The script prints the deployed address. Add it to `.env`:

```
MIP4_ACCOUNT_IMPL=0x<deployed address>
```

**Verify the implementation on Monadscan:**

```bash
forge verify-contract <IMPL_ADDRESS> src/Mip4Account.sol:Mip4Account \
  --chain 10143 \
  --verifier sourcify \
  --verifier-url https://sourcify-api-monad.blockvision.org/
```

Confirm `entryPoint()` returns the canonical address:

```bash
cast call <IMPL_ADDRESS> "entryPoint()(address)" --rpc-url "$MONAD_TESTNET_RPC"
# expected: 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108
```

**Fund Alice, Bob, and Carol.** The setup script generates three fresh EOAs, funds each with 10.6 MON from the funder wallet, delegates each to `Mip4Account`, and deposits 0.5 MON per account into the EntryPoint:

```bash
cd demo
npm run setup:testnet
```

The script is idempotent — safe to re-run if it fails partway through. If Carol's funding reverts with a reserve rule error, wait a few seconds and retry (the funder may have sent too many transactions in rapid succession).

### Run

```bash
npm run demo:direct
```

### Expected result

```
Alice op: send 0.05 MON (balance 10.6 MON)
Bob op: send 1 MON (balance 10.6 MON)
Carol op: send 0.05 MON (balance 10.6 MON)

BUNDLE TX COMMITTED: 0x...

  Alice  UserOperationEvent success=true
         UserOperationRevertReason = 0x417680f0 (ReserveDipped())
  Bob    UserOperationEvent success=false
  Carol  UserOperationEvent success=true

  Bob balance delta: 0 MON (execution unwound, still >= 10 MON reserve)

One dipping op did NOT kill the bundle — Alice's and Carol's ops landed. ✔
```

The `UserOperationRevertReason = 0x417680f0` is the `ReserveDipped()` error selector — on-chain attribution of the exact reason Bob's operation failed.

### Contrast run (optional but recommended)

Re-delegates Bob to the unguarded control account and submits the same bundle. Without the guard, the entire bundle reverts:

```bash
npm run demo:direct -- --contrast
```

Expected: the bundle transaction itself reverts. Alice and Carol's operations fail alongside Bob's despite having nothing to do with the reserve violation. This is the failure mode the guard prevents.

## References

- **MIP-4 specification (Final)** — `monad-crypto/MIPs`, `MIPs/MIP-4.md`. Precompile address, selector, gas cost, calldata semantics, CALL-only requirement.
- **Reserve Balance** — Monad Developer Documentation, `developer-essentials/reserve-balance`. Reserve threshold (10 MON), emptying exception, EIP-7702 behavior.
- **EIP-7702** — `ethereum/EIPs`, EIP-7702. Set EOA account code.
- **ERC-4337** — `ethereum/EIPs`, ERC-4337. Account abstraction using alt mempool.
- **EntryPoint v0.8** — `eth-infinitism/account-abstraction`, tag `v0.8.0`. Canonical EntryPoint on Monad Testnet: `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`.
- **mip-4-explained.md** — this repository, `MIP-4/docs/`. Full technical treatment of reserve balance and MIP-4 semantics.
- **minimum-conditions.md** — this repository, `MIP-4/docs/`. Evidence record for verified sufficient conditions.
- **findings.md** — this repository, `MIP-4/docs/`. Chronological verification log.
- **mip4-sca SPEC.md** — this repository, `MIP-4/examples/mip4-sca/docs/`. Full specification for the ERC-4337 smart account integration.
