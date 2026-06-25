#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/run-testnet-boundary-case.sh" exact
"$ROOT_DIR/script/run-testnet-boundary-case.sh" below
