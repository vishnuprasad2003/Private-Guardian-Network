#!/bin/bash
# Block until Anvil RPC is up and GETH_CONTRACT has bytecode (registry loaded).
# Usage: ./scripts/wait-anvil.sh [config-file] [timeout-seconds]
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
TIMEOUT="${2:-${WAIT_ANVIL_TIMEOUT:-120}}"
load_config "$CONFIG"

RPC_URL="${GETH_RPC_HTTP:-http://127.0.0.1:${ANVIL_PORT:-8545}}"
CONTRACT="${GETH_CONTRACT:-}"

command_exists curl || { log_error "curl is required for wait-anvil"; exit 1; }

rpc_call() {
    curl -s --max-time 3 -X POST -H 'Content-Type: application/json' \
        --data "$1" "$RPC_URL" 2>/dev/null || true
}

log_info "Waiting for Anvil at ${RPC_URL} (timeout ${TIMEOUT}s)"
deadline=$(( $(date +%s) + TIMEOUT ))

while true; do
    chain_id=$(rpc_call '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}')
    if [[ "$chain_id" == *'"result"'* ]]; then
        if [[ -n "$CONTRACT" ]]; then
            code=$(rpc_call "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"${CONTRACT}\",\"latest\"]}")
            if [[ "$code" == *'"result":"0x"'* || "$code" != *'"result"'* ]]; then
                [[ $(date +%s) -ge $deadline ]] && { log_error "Registry ${CONTRACT} has no bytecode after ${TIMEOUT}s — check anvil-state.json / GETH_CONTRACT (do not redeploy on VM)"; exit 1; }
                sleep 2; continue
            fi
        fi
        log_success "Anvil is ready"
        exit 0
    fi
    [[ $(date +%s) -ge $deadline ]] && { log_error "Anvil RPC not ready after ${TIMEOUT}s"; exit 1; }
    sleep 2
done
