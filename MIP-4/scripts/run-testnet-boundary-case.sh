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
  scripts/run-testnet-boundary-case.sh exact
  scripts/run-testnet-boundary-case.sh below

Required environment:
  MONAD_RPC_URL
  AUTHORITY

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
  TESTNET_DELEGATED_PROBE   Implementation address. If omitted, inferred from AUTHORITY's current 7702 code.
  TESTNET_REFUND_SINK       Refund sink address. If omitted, parsed from .secrets/sink-deploy.txt when available.
  GAS_LIMIT                 Defaults to 500000.

Cases:
  exact  drains 9 MON from a 19 MON authority, expecting during balance = 10 MON.
  below  drains 9 MON + 1 wei from a 19 MON authority, expecting during balance = 10 MON - 1 wei.
USAGE
}

case_name="${1:-}"
if [[ "$case_name" == "-h" || "$case_name" == "--help" ]]; then
  usage
  exit 0
fi

case "$case_name" in
  exact)
    label="exact-10-mon"
    drain_amount_wei="9000000000000000000"
    expected_before_balance_wei="19000000000000000000"
    expected_during_balance_wei="10000000000000000000"
    expected_after_balance_wei="19000000000000000000"
    ;;
  below)
    label="below-10-mon-minus-1-wei"
    drain_amount_wei="9000000000000000001"
    expected_before_balance_wei="19000000000000000000"
    expected_during_balance_wei="9999999999999999999"
    expected_after_balance_wei="19000000000000000000"
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

gas_limit="${GAS_LIMIT:-500000}"
sponsor_account="${SPONSOR_ACCOUNT:-monad-sponsor}"
authority_account="${AUTHORITY_ACCOUNT:-monad-authority}"

refund_sink="${TESTNET_REFUND_SINK:-}"
if [[ -z "$refund_sink" && -f "$ROOT_DIR/.secrets/sink-deploy.txt" ]]; then
  refund_sink="$(awk '/Deployed to:/ { print $3; exit }' "$ROOT_DIR/.secrets/sink-deploy.txt")"
fi

if [[ -z "$refund_sink" ]]; then
  echo "missing TESTNET_REFUND_SINK and could not parse .secrets/sink-deploy.txt" >&2
  exit 1
fi

implementation="${TESTNET_DELEGATED_PROBE:-}"
if [[ -z "$implementation" ]]; then
  authority_code="$(cast code "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"
  if [[ "$authority_code" =~ ^0xef0100[0-9a-fA-F]{40}$ ]]; then
    implementation="0x${authority_code:8:40}"
  else
    echo "AUTHORITY does not currently contain a 7702 designator; set TESTNET_DELEGATED_PROBE" >&2
    exit 1
  fi
fi

before_chain_balance="$(cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"
if [[ "$before_chain_balance" != "$expected_before_balance_wei" ]]; then
  cat >&2 <<EOF
authority balance does not match the required starting condition
expected: $expected_before_balance_wei
observed: $before_chain_balance

Refusing to run because this experiment is intended to change only the drain amount.
EOF
  exit 1
fi

echo "case=$label"
echo "authority=$AUTHORITY"
echo "implementation=$implementation"
echo "refund_sink=$refund_sink"
echo "drain_amount_wei=$drain_amount_wei"
echo "expected_before_balance_wei=$expected_before_balance_wei"
echo "expected_during_balance_wei=$expected_during_balance_wei"
echo "expected_after_balance_wei=$expected_after_balance_wei"

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

auth="$(cast wallet sign-auth "$implementation" \
  --rpc-url "$MONAD_RPC_URL" \
  "${authority_wallet_args[@]}")"

echo "sending type-4 authorization-list transaction..."
receipt="$(cast send "$AUTHORITY" \
  "probeDrainRestore(address,uint256)" "$refund_sink" "$drain_amount_wei" \
  --auth "$auth" \
  --rpc-url "$MONAD_RPC_URL" \
  "${sponsor_wallet_args[@]}" \
  --gas-limit "$gas_limit")"

echo "$receipt"

tx_hash="$(awk '/^transactionHash[[:space:]]/ { print $2; exit }' <<<"$receipt")"
tx_type="$(awk '/^type[[:space:]]/ { print $2; exit }' <<<"$receipt")"
status="$(awk '/^status[[:space:]]/ { print $2; exit }' <<<"$receipt")"

last_before_balance="$(cast call "$AUTHORITY" "lastBeforeBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_during_balance="$(cast call "$AUTHORITY" "lastDuringBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_after_balance="$(cast call "$AUTHORITY" "lastAfterBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_before_dip="$(cast call "$AUTHORITY" "lastBeforeDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_during_dip="$(cast call "$AUTHORITY" "lastDuringDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_after_dip="$(cast call "$AUTHORITY" "lastAfterDip()(bool)" --rpc-url "$MONAD_RPC_URL")"

cat <<EOF

observed:
  transactionHash=$tx_hash
  transactionType=$tx_type
  status=$status
  lastBeforeBalance=$last_before_balance
  lastDuringBalance=$last_during_balance
  lastAfterBalance=$last_after_balance
  lastBeforeDip=$last_before_dip
  lastDuringDip=$last_during_dip
  lastAfterDip=$last_after_dip
EOF

if [[ "$last_before_balance" != "$expected_before_balance_wei" ]]; then
  echo "unexpected lastBeforeBalance" >&2
  exit 1
fi

if [[ "$last_during_balance" != "$expected_during_balance_wei" ]]; then
  echo "unexpected lastDuringBalance" >&2
  exit 1
fi

if [[ "$last_after_balance" != "$expected_after_balance_wei" ]]; then
  echo "unexpected lastAfterBalance" >&2
  exit 1
fi
