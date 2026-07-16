#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.secrets/addresses.env" ]]; then
  # Optional local convenience file. It should contain public addresses/RPC only.
  # Private keys should be provided through the environment at runtime.
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.secrets/addresses.env"
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-testnet-7702-drain-restore.sh preflight
  scripts/run-testnet-7702-drain-restore.sh run

Purpose:
  Demonstrate MIP-4 reserve introspection via an EIP-7702 delegated EOA.
  The authority is delegated to TestnetDelegatedProbe, which drains its own
  balance below 10 MON and calls dippedIntoReserve() before, during, and
  after the drain. A refund sink restores the balance within the same
  transaction.

  Expected result:
    lastBeforeDip  = false   (above reserve)
    lastDuringDip  = true    (below reserve — MIP-4 precompile observed)
    lastAfterDip   = false   (balance restored)

  Unlike the existing sender-sponsor script, this script accepts any starting
  balance above 10 MON and automatically calculates the drain amount. The
  target during-balance defaults to 9.9 MON and can be overridden in human-
  readable MON (e.g. TARGET_DURING_MON=9.5) rather than wei.

Modes:
  preflight   Read-only checks: balances, drain calculation, gas estimate.
              Does not sign or broadcast anything.
  run         Signs the EIP-7702 authorization and submits the transaction.

Required environment:
  MONAD_RPC_URL
  AUTHORITY               Address of the delegated authority EOA.
  TESTNET_DELEGATED_PROBE Implementation contract address to delegate to.
  TESTNET_REFUND_SINK     Refund sink contract address.

Wallet environment, choose one mode:
  Raw private keys:
    SPONSOR_PRIVATE_KEY
    AUTHORITY_PRIVATE_KEY

  Foundry keystore accounts:
    SPONSOR_ACCOUNT          Defaults to monad-sponsor.
    AUTHORITY_ACCOUNT        Defaults to monad-authority.
    KEYSTORE_PASSWORD_FILE   Optional shared password file.
    SPONSOR_PASSWORD_FILE    Optional sponsor-specific password file.
    AUTHORITY_PASSWORD_FILE  Optional authority-specific password file.

Optional environment:
  TARGET_DURING_MON   Target balance (in MON) after the drain. Must be below
                      10 MON to trigger dippedIntoReserve(). Defaults to 9.9.
                      Example: TARGET_DURING_MON=9.5
  GAS_LIMIT           Defaults to 500000.

Examples:
  # default: drain authority to 9.9 MON during execution
  MONAD_RPC_URL=... AUTHORITY=0x... SPONSOR_PRIVATE_KEY=0x... \
  AUTHORITY_PRIVATE_KEY=0x... TESTNET_DELEGATED_PROBE=0x... \
  TESTNET_REFUND_SINK=0x... \
  scripts/run-testnet-7702-drain-restore.sh run

  # custom target: drain to 9.5 MON during execution
  TARGET_DURING_MON=9.5 \
  scripts/run-testnet-7702-drain-restore.sh run
USAGE
}

mode="${1:-}"
if [[ "$mode" == "-h" || "$mode" == "--help" ]]; then
  usage
  exit 0
fi

case "$mode" in
  preflight|run)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 1
  fi
}

require_env MONAD_RPC_URL
require_env AUTHORITY
require_env TESTNET_DELEGATED_PROBE
require_env TESTNET_REFUND_SINK

gas_limit="${GAS_LIMIT:-500000}"
target_during_mon="${TARGET_DURING_MON:-9.9}"
sponsor_account="${SPONSOR_ACCOUNT:-monad-sponsor}"
authority_account="${AUTHORITY_ACCOUNT:-monad-authority}"

# --------------------------------------------------------------------------
# Validate target_during_mon is below 10 MON
# --------------------------------------------------------------------------
target_valid="$(python3 - "$target_during_mon" <<'PY'
import sys
try:
    v = float(sys.argv[1])
    if v >= 10:
        print("error: TARGET_DURING_MON must be below 10 MON to trigger dippedIntoReserve()", file=sys.stderr)
        sys.exit(1)
    if v < 0:
        print("error: TARGET_DURING_MON must be positive", file=sys.stderr)
        sys.exit(1)
    print("ok")
except ValueError:
    print(f"error: TARGET_DURING_MON={sys.argv[1]} is not a valid number", file=sys.stderr)
    sys.exit(1)
PY
)"

if [[ "$target_valid" != "ok" ]]; then
  exit 1
fi

# --------------------------------------------------------------------------
# Convert TARGET_DURING_MON to wei
# --------------------------------------------------------------------------
target_during_balance_wei="$(python3 - "$target_during_mon" <<'PY'
import sys
mon = float(sys.argv[1])
print(int(mon * 10**18))
PY
)"

# --------------------------------------------------------------------------
# Fetch authority's current balance
# --------------------------------------------------------------------------
start_chain_balance="$(cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"

# --------------------------------------------------------------------------
# Validate starting balance is above 10 MON
# --------------------------------------------------------------------------
python3 - "$start_chain_balance" <<'PY'
import sys
balance = int(sys.argv[1])
reserve = 10 * 10**18
if balance <= reserve:
    print(
        f"error: AUTHORITY balance {balance / 1e18:.4f} MON is not above 10 MON.\n"
        "The authority must start above 10 MON to cross below the reserve threshold during the drain.",
        file=sys.stderr
    )
    sys.exit(1)
PY

# --------------------------------------------------------------------------
# Calculate drain amount: start - target_during
# --------------------------------------------------------------------------
drain_amount_wei="$(python3 - "$start_chain_balance" "$target_during_balance_wei" <<'PY'
import sys
start = int(sys.argv[1])
target = int(sys.argv[2])
if target >= start:
    print(
        f"error: TARGET_DURING_MON is higher than the authority's current balance.\n"
        f"Current balance: {start / 1e18:.4f} MON, target: {target / 1e18:.4f} MON",
        file=sys.stderr
    )
    sys.exit(1)
drain = start - target
print(drain)
PY
)"

drain_amount_mon="$(python3 - "$drain_amount_wei" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1e18:.6f}")
PY
)"

start_chain_balance_mon="$(python3 - "$start_chain_balance" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1e18:.6f}")
PY
)"

# --------------------------------------------------------------------------
# Preflight summary
# --------------------------------------------------------------------------
echo "case=7702-drain-restore"
echo "authority=$AUTHORITY"
echo "implementation=$TESTNET_DELEGATED_PROBE"
echo "refund_sink=$TESTNET_REFUND_SINK"
echo "start_balance=${start_chain_balance_mon} MON (${start_chain_balance} wei)"
echo "target_during_balance=${target_during_mon} MON (${target_during_balance_wei} wei)"
echo "drain_amount=${drain_amount_mon} MON (${drain_amount_wei} wei)"
echo "gas_limit=$gas_limit"

if [[ "$mode" == "preflight" ]]; then
  echo ""
  echo "preflight complete — no transaction submitted."
  echo "Run with 'run' to submit the transaction."
  exit 0
fi

# --------------------------------------------------------------------------
# Wallet helpers
# --------------------------------------------------------------------------
wallet_args_for() {
  local role="$1"
  local private_key_name account_name password_file_name

  case "$role" in
    sponsor)
      private_key_name="SPONSOR_PRIVATE_KEY"
      account_name="$sponsor_account"
      password_file_name="${SPONSOR_PASSWORD_FILE:-${KEYSTORE_PASSWORD_FILE:-}}"
      ;;
    authority)
      private_key_name="AUTHORITY_PRIVATE_KEY"
      account_name="$authority_account"
      password_file_name="${AUTHORITY_PASSWORD_FILE:-${KEYSTORE_PASSWORD_FILE:-}}"
      ;;
    *)
      echo "unknown wallet role: $role" >&2
      exit 1
      ;;
  esac

  if [[ -n "${!private_key_name:-}" ]]; then
    printf '%s\n' "--private-key"
    printf '%s\n' "${!private_key_name}"
    return
  fi

  printf '%s\n' "--account"
  printf '%s\n' "$account_name"

  if [[ -n "$password_file_name" ]]; then
    printf '%s\n' "--password-file"
    printf '%s\n' "$password_file_name"
  fi
}

mapfile -t authority_wallet_args < <(wallet_args_for authority)
mapfile -t sponsor_wallet_args < <(wallet_args_for sponsor)

# --------------------------------------------------------------------------
# Sign the EIP-7702 authorization
# --------------------------------------------------------------------------
echo ""
echo "signing EIP-7702 authorization..."
auth="$(cast wallet sign-auth "$TESTNET_DELEGATED_PROBE" \
  --rpc-url "$MONAD_RPC_URL" \
  "${authority_wallet_args[@]}")"

# --------------------------------------------------------------------------
# Submit the type-4 authorization-list transaction
# --------------------------------------------------------------------------
echo "sending type-4 authorization-list transaction..."
receipt="$(cast send "$AUTHORITY" \
  "probeDrainRestore(address,uint256)" "$TESTNET_REFUND_SINK" "$drain_amount_wei" \
  --auth "$auth" \
  --rpc-url "$MONAD_RPC_URL" \
  "${sponsor_wallet_args[@]}" \
  --gas-limit "$gas_limit")"

echo "$receipt"

tx_hash="$(awk '/^transactionHash[[:space:]]/ { print $2; exit }' <<<"$receipt")"
tx_type="$(awk '/^type[[:space:]]/ { print $2; exit }' <<<"$receipt")"
status="$(awk '/^status[[:space:]]/ { print $2; exit }' <<<"$receipt")"
gas_used="$(awk '/^gasUsed[[:space:]]/ { print $2; exit }' <<<"$receipt")"

# --------------------------------------------------------------------------
# Read back recorded state from the delegated probe
# --------------------------------------------------------------------------
last_before_balance="$(cast call "$AUTHORITY" "lastBeforeBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_during_balance="$(cast call "$AUTHORITY" "lastDuringBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_after_balance="$(cast call "$AUTHORITY" "lastAfterBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_before_dip="$(cast call "$AUTHORITY" "lastBeforeDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_during_dip="$(cast call "$AUTHORITY" "lastDuringDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_after_dip="$(cast call "$AUTHORITY" "lastAfterDip()(bool)" --rpc-url "$MONAD_RPC_URL")"

last_before_balance_mon="$(python3 - "$last_before_balance" <<'PY'
import sys; print(f"{int(sys.argv[1]) / 1e18:.6f}")
PY
)"
last_during_balance_mon="$(python3 - "$last_during_balance" <<'PY'
import sys; print(f"{int(sys.argv[1]) / 1e18:.6f}")
PY
)"
last_after_balance_mon="$(python3 - "$last_after_balance" <<'PY'
import sys; print(f"{int(sys.argv[1]) / 1e18:.6f}")
PY
)"

cat <<EOF

observed:
  transactionHash=$tx_hash
  transactionType=$tx_type
  status=$status
  gasUsed=$gas_used

  lastBeforeBalance=${last_before_balance_mon} MON
  lastDuringBalance=${last_during_balance_mon} MON
  lastAfterBalance=${last_after_balance_mon} MON

  lastBeforeDip=$last_before_dip
  lastDuringDip=$last_during_dip
  lastAfterDip=$last_after_dip

expected:
  lastBeforeDip=false   (above reserve before drain)
  lastDuringDip=true    (below reserve during drain — MIP-4 observed)
  lastAfterDip=false    (balance restored by refund sink)