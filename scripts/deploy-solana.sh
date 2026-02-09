#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Deploy Wormhole Core Bridge to Solana
# Usage: ./scripts/deploy-solana.sh <generate|deploy|initialize|status|all>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${WORKSPACE_ROOT}/configs/guardian-0.conf"
[[ -f "$CONFIG" ]] && load_config "$CONFIG"
ensure_dirs

SOLANA_RPC="${SOLANA_RPC:-http://localhost:8899}"
SOLANA_KEYPAIR="${SOLANA_DEPLOYER_KEY:-../../Solana-Validator-Node/keys/faucet.json}"
CONTRACTS_DIR="${BASE_DIR}/contracts/solana"
PROGRAM_SO="${CONTRACTS_DIR}/bridge.so"
PROGRAM_ID_FILE="${CONTRACTS_DIR}/program-id.json"

# Resolve relative keypair path
[[ "$SOLANA_KEYPAIR" != /* ]] && SOLANA_KEYPAIR="$(cd "${WORKSPACE_ROOT}" && realpath -m "$SOLANA_KEYPAIR")"

COMMAND="${1:-all}"

# ─── Helpers for paths with spaces ──────────────────────────────────────────
_safe_keypair() {
    local kp="$1"
    if [[ "$kp" == *" "* ]]; then
        local tmp="/tmp/solana-kp-$$.json"
        cp "$kp" "$tmp"; echo "$tmp"
    else
        echo "$kp"
    fi
}
_cleanup_tmp() { [[ "${1:-}" == /tmp/solana-kp-* ]] && rm -f "$1" 2>/dev/null || true; }

# ─── Steps ──────────────────────────────────────────────────────────────────
check_prerequisites() {
    log_info "Checking prerequisites..."
    command_exists solana || { log_error "Solana CLI not installed"; exit 1; }
    [[ -f "$PROGRAM_SO" ]] || { log_error "bridge.so not found at ${PROGRAM_SO}"; exit 1; }
    [[ -f "$SOLANA_KEYPAIR" ]] || { log_error "Deployer keypair not found: ${SOLANA_KEYPAIR}"; exit 1; }
    solana config set --url "$SOLANA_RPC" > /dev/null
    log_info "RPC: ${SOLANA_RPC}"
    local tmp; tmp=$(_safe_keypair "$SOLANA_KEYPAIR")
    solana balance --url "$SOLANA_RPC" --keypair "$tmp" 2>&1 | head -1 | while read -r bal; do log_info "Balance: $bal"; done
    _cleanup_tmp "$tmp"
}

generate_program_id() {
    log_info "Generating program keypair..."
    local kp="${CONTRACTS_DIR}/program-keypair.json"
    if [[ -f "$kp" ]]; then
        log_warn "Keypair already exists: ${kp}"
    else
        local tmp; tmp=$(_safe_keypair "$kp")
        solana-keygen new --no-bip39-passphrase -o "$tmp" --force
        [[ "$tmp" != "$kp" ]] && { cp "$tmp" "$kp"; _cleanup_tmp "$tmp"; }
    fi
    local tmp2; tmp2=$(_safe_keypair "$kp")
    local pid; pid=$(solana-keygen pubkey "$tmp2")
    _cleanup_tmp "$tmp2"
    echo "{\"programId\": \"$pid\"}" > "$PROGRAM_ID_FILE"
    log_success "Program ID: ${pid}"
    log_info "Update config → SOLANA_CONTRACT=\"${pid}\""
}

deploy_program() {
    log_info "Deploying Wormhole Core Bridge..."
    local kp="${CONTRACTS_DIR}/program-keypair.json"
    [[ -f "$kp" ]] || { log_error "Program keypair not found. Run: $0 generate"; exit 1; }
    local tmp_kp; tmp_kp=$(_safe_keypair "$kp")
    local pid; pid=$(solana-keygen pubkey "$tmp_kp")
    log_info "Program ID: ${pid}"
    if solana program show "$pid" --url "$SOLANA_RPC" 2>/dev/null | grep -q "Program Id"; then
        log_warn "Already deployed at ${pid}"; _cleanup_tmp "$tmp_kp"; return 0
    fi
    local tmp_deployer; tmp_deployer=$(_safe_keypair "$SOLANA_KEYPAIR")
    solana program deploy --url "$SOLANA_RPC" --keypair "$tmp_deployer" --program-id "$tmp_kp" "$PROGRAM_SO"
    _cleanup_tmp "$tmp_kp"; _cleanup_tmp "$tmp_deployer"
    log_success "Deployed: ${pid}"
}

initialize_bridge() {
    log_info "Initializing Wormhole Core Bridge..."
    [[ -f "$PROGRAM_ID_FILE" ]] || { log_error "Deploy first: $0 deploy"; exit 1; }
    local pid; pid=$(jq -r '.programId' "$PROGRAM_ID_FILE")
    local guardian_set; guardian_set=$(echo "${GUARDIAN_ADDRESSES}" | sed 's/0x//g;s/,/","/g;s/^/["/;s/$/"]/')
    local scripts_dir="${WORKSPACE_ROOT}/../wormhole/solana/scripts"
    [[ -f "${scripts_dir}/initialize-core.ts" ]] || { log_error "Init script not found"; exit 1; }
    [[ -d "${scripts_dir}/node_modules" ]] || { log_info "Installing npm deps..."; (cd "$scripts_dir" && npm install); }
    log_info "Initializing with guardian set..."
    (cd "$scripts_dir" && \
     RPC_URL="$SOLANA_RPC" \
     CORE_BRIDGE_PROGRAM_ID="$pid" \
     PRIVATE_KEY="$SOLANA_KEYPAIR" \
     GUARDIAN_SET="$guardian_set" \
     FEE="${SOLANA_BRIDGE_FEE:-100000}" \
     EXPIRATION_TIME="${SOLANA_BRIDGE_EXPIRATION:-86400}" \
     npx tsx initialize-core.ts)
    log_success "Bridge initialized — Program ID: ${pid}"
}

show_status() {
    log_info "Solana Wormhole status"
    echo "  RPC: ${SOLANA_RPC}"
    solana cluster-version --url "$SOLANA_RPC" 2>/dev/null || { log_error "Cannot connect"; exit 1; }
    if [[ -f "$PROGRAM_ID_FILE" ]]; then
        local pid; pid=$(jq -r '.programId' "$PROGRAM_ID_FILE")
        echo "  Program: ${pid}"
        solana program show "$pid" --url "$SOLANA_RPC" 2>/dev/null || log_warn "Not found on chain"
    fi
    local tmp; tmp=$(_safe_keypair "$SOLANA_KEYPAIR")
    echo "  Deployer balance: $(solana balance --url "$SOLANA_RPC" --keypair "$tmp" 2>&1 | head -1)"
    _cleanup_tmp "$tmp"
}

case "$COMMAND" in
    generate)    check_prerequisites; generate_program_id ;;
    deploy)      check_prerequisites; deploy_program ;;
    initialize)  check_prerequisites; initialize_bridge ;;
    status)      check_prerequisites; show_status ;;
    all)         check_prerequisites; generate_program_id; deploy_program; initialize_bridge ;;
    *) echo "Usage: $0 <generate|deploy|initialize|status|all>"; exit 1 ;;
esac
