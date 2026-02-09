#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Deploy Wormhole contracts to an EVM chain (Anvil or Avalanche)
# Usage: ./scripts/deploy-evm.sh <anvil|avalanche> [config-file]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CHAIN="${1:?Usage: $0 <anvil|avalanche> [config-file]}"
CONFIG="${2:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
load_config "$CONFIG"
ensure_dirs

# Use contracts from BASE_DIR (copied there by ensure_dirs / make init)
CONTRACTS="${BASE_DIR}/contracts/evm"
[[ ! -d "$CONTRACTS" ]] || [[ -z "$(ls -A "$CONTRACTS" 2>/dev/null)" ]] && \
    CONTRACTS="${WORKSPACE_ROOT}/contracts/evm"
command_exists cast || { log_error "cast not found. Run: make install-deps"; exit 1; }

case "$CHAIN" in
    anvil)
        RPC_URL="$GETH_RPC_HTTP"
        WORMHOLE_CHAIN_ID=2
        PRIVATE_KEY="${ANVIL_PRIVATE_KEY}"
        ;;
    avalanche)
        RPC_URL="$AVALANCHE_RPC_HTTP"
        WORMHOLE_CHAIN_ID=6
        PRIVATE_KEY="${PRIVATE_KEY:-$AVALANCHE_DEPLOYER_KEY}"
        [[ -z "$PRIVATE_KEY" ]] && { log_error "PRIVATE_KEY or AVALANCHE_DEPLOYER_KEY not set"; exit 1; }
        ;;
    *) log_error "Unknown chain: $CHAIN (use anvil or avalanche)"; exit 1 ;;
esac

log_info "Deploying Wormhole to ${CHAIN} (${RPC_URL})"

IMPL=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Implementation.bytecode")" --json | jq -r '.contractAddress')
log_success "Implementation: ${IMPL}"

SETUP=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Setup.bytecode")" --json | jq -r '.contractAddress')
log_success "Setup: ${SETUP}"

NATIVE_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
GUARDIAN_ARRAY="[$(echo "$GUARDIAN_ADDRESSES" | sed 's/,/,/g')]"

SETUP_DATA=$(cast calldata \
    "setup(address,address[],uint16,uint16,bytes32,uint256)" \
    "$IMPL" "$GUARDIAN_ARRAY" "$WORMHOLE_CHAIN_ID" "$WORMHOLE_CHAIN_ID" \
    "0x0000000000000000000000000000000000000000000000000000000000000004" "$NATIVE_CHAIN_ID")

CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" "$SETUP" "$SETUP_DATA")
WORMHOLE=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Wormhole.bytecode")${CONSTRUCTOR_ARGS:2}" --json | jq -r '.contractAddress')

log_success "Wormhole deployed: ${WORMHOLE}"
echo ""
if [[ "$CHAIN" == "anvil" ]]; then
    log_info "Update config → GETH_CONTRACT=\"${WORMHOLE}\""
else
    log_info "Update config → AVALANCHE_CONTRACT=\"${WORMHOLE}\""
fi
