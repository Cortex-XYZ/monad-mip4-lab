#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.secrets/addresses.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.secrets/addresses.env"
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-testnet-below-reserve-case.sh noop
  scripts/run-testnet-below-reserve-case.sh drain
  scripts/run-testnet-below-reserve-case.sh recover

Required environment:
  MONAD_RPC_URL
  BELOW_AUTHORITY
  TESTNET_DELEGATED_PROBE

Wallet environment:
  SPONSOR_ACCOUNT          Defaults to monad-sponsor.
  KEYSTORE_PASSWORD_FILE   Optional shared password file.
  SPONSOR_PRIVATE_KEY      Optional raw sponsor key.

  BELOW_AUTHORITY_PRIVATE_KEY is required for signing the EIP-7702 authorization.

Optional environment:
  TESTNET_REFUND_SINK      Defaults to .secrets/sink-deploy.txt.
  BELOW_SOURCE_SINK        Source sink for recover case; defaults to TESTNET_REFUND_SINK.
  GAS_LIMIT                Defaults to 500000.

Cases:
  noop     9 MON -> 9 MON
  drain    9 MON -> 8 MON
  recover  9 MON -> 11 MON, requiring a source sink with 2 MON
USAGE
}

case_name="${1:-}"
if [[ "$case_name" == "-h" || "$case_name" == "--help" ]]; then
  usage
  exit 0
fi

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 1
  fi
}

require_env MONAD_RPC_URL
require_env BELOW_AUTHORITY
require_env TESTNET_DELEGATED_PROBE
require_env BELOW_AUTHORITY_PRIVATE_KEY

gas_limit="${GAS_LIMIT:-500000}"
sponsor_account="${SPONSOR_ACCOUNT:-monad-sponsor}"

refund_sink="${TESTNET_REFUND_SINK:-}"
if [[ -z "$refund_sink" && -f "$ROOT_DIR/.secrets/sink-deploy.txt" ]]; then
  refund_sink="$(awk '/Deployed to:/ { print $3; exit }' "$ROOT_DIR/.secrets/sink-deploy.txt")"
fi

if [[ -z "$refund_sink" ]]; then
  echo "missing TESTNET_REFUND_SINK and could not parse .secrets/sink-deploy.txt" >&2
  exit 1
fi

source_sink="${BELOW_SOURCE_SINK:-$refund_sink}"

expected_before_balance_wei="9000000000000000000"

case "$case_name" in
  noop)
    label="below-reserve-noop"
    signature="probeNoop()"
    args=()
    expected_during_balance_wei="9000000000000000000"
    expected_after_balance_wei="9000000000000000000"
    ;;
  drain)
    label="below-reserve-drain-no-restore"
    signature="probeDrainNoRestore(address,uint256)"
    args=("$refund_sink" "1000000000000000000")
    expected_during_balance_wei="8000000000000000000"
    expected_after_balance_wei="8000000000000000000"
    ;;
  recover)
    label="below-reserve-recover"
    signature="probeReceiveFrom(address,uint256)"
    args=("$source_sink" "2000000000000000000")
    expected_during_balance_wei="11000000000000000000"
    expected_after_balance_wei="11000000000000000000"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

before_chain_balance="$(cast balance "$BELOW_AUTHORITY" --rpc-url "$MONAD_RPC_URL")"
if [[ "$before_chain_balance" != "$expected_before_balance_wei" ]]; then
  cat >&2 <<EOF
below-reserve authority balance does not match the required starting condition
expected: $expected_before_balance_wei
observed: $before_chain_balance
EOF
  exit 1
fi

sponsor_wallet_args=()
if [[ -n "${SPONSOR_PRIVATE_KEY:-}" ]]; then
  sponsor_wallet_args=(--private-key "$SPONSOR_PRIVATE_KEY")
else
  sponsor_wallet_args=(--account "$sponsor_account")
  if [[ -n "${KEYSTORE_PASSWORD_FILE:-}" ]]; then
    sponsor_wallet_args+=(--password-file "$KEYSTORE_PASSWORD_FILE")
  fi
fi

echo "case=$label"
echo "below_authority=$BELOW_AUTHORITY"
echo "implementation=$TESTNET_DELEGATED_PROBE"
echo "refund_sink=$refund_sink"
echo "expected_before_balance_wei=$expected_before_balance_wei"
echo "expected_during_balance_wei=$expected_during_balance_wei"
echo "expected_after_balance_wei=$expected_after_balance_wei"

auth="$(cast wallet sign-auth "$TESTNET_DELEGATED_PROBE" \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$BELOW_AUTHORITY_PRIVATE_KEY")"

echo "sending type-4 authorization-list transaction..."
set +e
receipt="$(cast send "$BELOW_AUTHORITY" \
  "$signature" "${args[@]}" \
  --auth "$auth" \
  --rpc-url "$MONAD_RPC_URL" \
  "${sponsor_wallet_args[@]}" \
  --gas-limit "$gas_limit" 2>&1)"
send_status=$?
set -e

echo "$receipt"

if [[ "$send_status" -ne 0 ]]; then
  echo "cast send failed with exit code $send_status" >&2
  exit "$send_status"
fi

tx_hash="$(awk '/^transactionHash[[:space:]]/ { print $2; exit }' <<<"$receipt")"
tx_type="$(awk '/^type[[:space:]]/ { print $2; exit }' <<<"$receipt")"
status="$(awk '/^status[[:space:]]/ { print $2; exit }' <<<"$receipt")"

last_before_balance="$(cast call "$BELOW_AUTHORITY" "lastBeforeBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_during_balance="$(cast call "$BELOW_AUTHORITY" "lastDuringBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_after_balance="$(cast call "$BELOW_AUTHORITY" "lastAfterBalance()(uint256)" --rpc-url "$MONAD_RPC_URL" | awk '{ print $1 }')"
last_before_dip="$(cast call "$BELOW_AUTHORITY" "lastBeforeDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_during_dip="$(cast call "$BELOW_AUTHORITY" "lastDuringDip()(bool)" --rpc-url "$MONAD_RPC_URL")"
last_after_dip="$(cast call "$BELOW_AUTHORITY" "lastAfterDip()(bool)" --rpc-url "$MONAD_RPC_URL")"

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

if [[ "$status" != "1" ]]; then
  exit 0
fi

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
