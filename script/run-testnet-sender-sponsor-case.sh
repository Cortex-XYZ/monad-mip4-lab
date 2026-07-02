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
  script/run-testnet-sender-sponsor-case.sh preflight
  script/run-testnet-sender-sponsor-case.sh sponsor
  script/run-testnet-sender-sponsor-case.sh authority

Purpose:
  Compare reserve tracking when the same delegated authority is executed through:
    preflight  Read-only balance and gas checks. Does not sign or broadcast.
    sponsor    Sponsor submits the type-4 authorization-list transaction.
    authority  Delegated authority submits the type-4 authorization-list transaction directly.

Required environment:
  MONAD_RPC_URL
  AUTHORITY

Required tools:
  cast
  python3

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
  SPONSOR                    Sponsor address for preflight balance checks.
  TESTNET_DELEGATED_PROBE     Implementation address. If omitted, inferred from AUTHORITY's current 7702 code.
  TESTNET_REFUND_SINK         Refund sink address. If omitted, parsed from .secrets/sink-deploy.txt when available.
  GAS_LIMIT                   Defaults to 500000.
  DRAIN_AMOUNT_WEI            Defaults to 9000000000000000001.
  TARGET_DURING_BALANCE_WEI   Optional. If set, compute DRAIN_AMOUNT_WEI from the
                              observed start balance so sponsor mode reaches this during balance.
  EXPECTED_START_BALANCE_WEI  Defaults to 19000000000000000000.
  SKIP_START_BALANCE_CHECK    Set to 1 to record a non-standard run instead of refusing.

Default experiment:
  Drain 9 MON + 1 wei from an authority that starts at 19 MON.
  In sponsor mode, the authority does not pay gas.
  In authority mode, the authority pays gas, so the in-probe before balance can be lower
  than the pre-transaction chain balance. This is part of the sender classification being tested.
USAGE
}

mode="${1:-}"
if [[ "$mode" == "-h" || "$mode" == "--help" ]]; then
  usage
  exit 0
fi

case "$mode" in
  preflight|sponsor|authority)
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
drain_amount_wei="${DRAIN_AMOUNT_WEI:-9000000000000000001}"
target_during_balance_wei="${TARGET_DURING_BALANCE_WEI:-}"
expected_start_balance_wei="${EXPECTED_START_BALANCE_WEI:-19000000000000000000}"
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

if [[ "$mode" == "preflight" ]]; then
  gas_price="$(cast gas-price --rpc-url "$MONAD_RPC_URL")"
  authority_balance="$(cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"
  max_gas_cost_wei="$(python3 - "$gas_limit" "$gas_price" <<'PY'
import sys
print(int(sys.argv[1], 10) * int(sys.argv[2], 10))
PY
)"
  authority_delta_wei="$(python3 - "$expected_start_balance_wei" "$authority_balance" <<'PY'
import sys
expected = int(sys.argv[1], 10)
observed = int(sys.argv[2], 10)
print(max(expected - observed, 0))
PY
)"

  echo "case=sender-sponsor-preflight"
  echo "authority=$AUTHORITY"
  echo "implementation=$implementation"
  echo "refund_sink=$refund_sink"
  echo "authority_balance_wei=$authority_balance"
  echo "expected_start_balance_wei=$expected_start_balance_wei"
  echo "authority_top_up_needed_wei=$authority_delta_wei"
  echo "gas_price_wei=$gas_price"
  echo "gas_limit=$gas_limit"
  echo "max_gas_cost_wei=$max_gas_cost_wei"

  if [[ -n "${SPONSOR:-}" ]]; then
    sponsor_balance="$(cast balance "$SPONSOR" --rpc-url "$MONAD_RPC_URL")"
    sponsor_delta_wei="$(python3 - "$max_gas_cost_wei" "$sponsor_balance" <<'PY'
import sys
expected = int(sys.argv[1], 10)
observed = int(sys.argv[2], 10)
print(max(expected - observed, 0))
PY
)"
    echo "sponsor=$SPONSOR"
    echo "sponsor_balance_wei=$sponsor_balance"
    echo "sponsor_minimum_top_up_needed_wei=$sponsor_delta_wei"
  else
    echo "sponsor=unset"
    echo "sponsor_balance_wei=unknown"
    echo "sponsor_minimum_top_up_needed_wei=unknown"
  fi

  exit 0
fi

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

uint_check() {
  python3 - "$@" <<'PY'
import sys

op = sys.argv[1]
values = [int(x, 10) for x in sys.argv[2:]]

if op == "lt":
    ok = values[0] < values[1]
elif op == "subeq":
    ok = values[0] - values[1] == values[2]
else:
    raise SystemExit(f"unknown op: {op}")

raise SystemExit(0 if ok else 1)
PY
}

mapfile -t authority_wallet_args < <(wallet_args_for authority)
mapfile -t sponsor_wallet_args < <(wallet_args_for sponsor)

case "$mode" in
  sponsor)
    sender_label="sponsor"
    sender_account="$sponsor_account"
    sender_wallet_args=("${sponsor_wallet_args[@]}")
    sign_auth_extra_args=()
    ;;
  authority)
    sender_label="authority"
    sender_account="$authority_account"
    sender_wallet_args=("${authority_wallet_args[@]}")
    sign_auth_extra_args=(--self-broadcast)
    ;;
esac

start_chain_balance="$(cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"
if [[ "${SKIP_START_BALANCE_CHECK:-0}" != "1" && "$start_chain_balance" != "$expected_start_balance_wei" ]]; then
  cat >&2 <<EOF
authority balance does not match the default starting condition
expected: $expected_start_balance_wei
observed: $start_chain_balance

Refusing to run because this experiment should preserve the known reserve-dip path where possible.
Set SKIP_START_BALANCE_CHECK=1 only for an explicitly non-standard run.
EOF
  exit 1
fi

if [[ -n "$target_during_balance_wei" ]]; then
  drain_amount_wei="$(python3 - "$start_chain_balance" "$target_during_balance_wei" <<'PY'
import sys

start = int(sys.argv[1], 10)
target = int(sys.argv[2], 10)

if target >= start:
    raise SystemExit("TARGET_DURING_BALANCE_WEI must be lower than the observed start balance")

print(start - target)
PY
)"
fi

echo "case=sender-sponsor-$sender_label"
echo "authority=$AUTHORITY"
echo "implementation=$implementation"
echo "refund_sink=$refund_sink"
echo "transaction_sender_mode=$sender_label"
echo "transaction_sender_account=$sender_account"
echo "start_chain_balance_wei=$start_chain_balance"
echo "drain_amount_wei=$drain_amount_wei"
if [[ -n "$target_during_balance_wei" ]]; then
  echo "target_during_balance_wei=$target_during_balance_wei"
fi
echo "gas_limit=$gas_limit"

auth="$(cast wallet sign-auth "$implementation" \
  --rpc-url "$MONAD_RPC_URL" \
  "${sign_auth_extra_args[@]}" \
  "${authority_wallet_args[@]}")"

echo "sending type-4 authorization-list transaction..."
receipt="$(cast send "$AUTHORITY" \
  "probeDrainRestore(address,uint256)" "$refund_sink" "$drain_amount_wei" \
  --auth "$auth" \
  --rpc-url "$MONAD_RPC_URL" \
  "${sender_wallet_args[@]}" \
  --gas-limit "$gas_limit")"

echo "$receipt"

tx_hash="$(awk '/^transactionHash[[:space:]]/ { print $2; exit }' <<<"$receipt")"
tx_type="$(awk '/^type[[:space:]]/ { print $2; exit }' <<<"$receipt")"
status="$(awk '/^status[[:space:]]/ { print $2; exit }' <<<"$receipt")"
gas_used="$(awk '/^gasUsed[[:space:]]/ { print $2; exit }' <<<"$receipt")"

tx_from="$(cast tx "$tx_hash" from --rpc-url "$MONAD_RPC_URL")"
tx_to="$(cast tx "$tx_hash" to --rpc-url "$MONAD_RPC_URL")"
tx_nonce="$(cast tx "$tx_hash" nonce --rpc-url "$MONAD_RPC_URL")"
end_chain_balance="$(cast balance "$AUTHORITY" --rpc-url "$MONAD_RPC_URL")"

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
  gasUsed=$gas_used
  txFrom=$tx_from
  txTo=$tx_to
  txNonce=$tx_nonce
  startChainBalance=$start_chain_balance
  endChainBalance=$end_chain_balance
  lastBeforeBalance=$last_before_balance
  lastDuringBalance=$last_during_balance
  lastAfterBalance=$last_after_balance
  lastBeforeDip=$last_before_dip
  lastDuringDip=$last_during_dip
  lastAfterDip=$last_after_dip
EOF

if [[ "$status" != "1" ]]; then
  echo "transaction did not succeed; observations above are still useful evidence" >&2
  exit 0
fi

if [[ "$last_after_balance" != "$last_before_balance" ]]; then
  echo "unexpected lastAfterBalance: restore did not return to in-probe before balance" >&2
  exit 1
fi

if ! uint_check subeq "$last_before_balance" "$drain_amount_wei" "$last_during_balance"; then
  echo "unexpected lastDuringBalance: does not equal lastBeforeBalance - drain amount" >&2
  exit 1
fi

if ! uint_check lt "$last_during_balance" "10000000000000000000"; then
  echo "unexpected lastDuringBalance: did not drop below 10 MON" >&2
  exit 1
fi
