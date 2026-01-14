#!/bin/bash
# Deploy Wormhole contracts to EVM chains
# Usage: ./scripts/deploy-evm.sh <chain>  (anvil or avalanche)

set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ $# -lt 1 ]] && { log_error "Usage: $0 <anvil|avalanche>"; exit 1; }

CHAIN="$1"
load_config "${WORKSPACE_ROOT}/configs/guardian-0.conf" || exit 1
CONTRACTS="${WORKSPACE_ROOT}/contracts/evm"

command_exists cast || { log_error "cast not installed. Install Foundry"; exit 1; }

case "$CHAIN" in
    anvil)
        RPC_URL="$GETH_RPC_HTTP"
        WORMHOLE_CHAIN_ID=2
        PRIVATE_KEY="${ANVIL_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
        ;;
    avalanche)
        RPC_URL="$AVALANCHE_RPC_HTTP"
        WORMHOLE_CHAIN_ID=6
        PRIVATE_KEY="${PRIVATE_KEY:-$AVALANCHE_DEPLOYER_KEY}"
        [[ -z "$PRIVATE_KEY" ]] && { log_error "PRIVATE_KEY not set"; exit 1; }
        ;;
    *) log_error "Unknown chain: $CHAIN"; exit 1 ;;
esac

log_info "Deploying to $CHAIN ($RPC_URL)"

IMPL=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Implementation.bytecode")" --json | jq -r '.contractAddress')
log_success "Implementation: $IMPL"

SETUP=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Setup.bytecode")" --json | jq -r '.contractAddress')
log_success "Setup: $SETUP"

NATIVE_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
GUARDIAN_ARRAY="[$(echo "$GUARDIAN_ADDRESSES" | sed 's/,/,/g')]"

SETUP_DATA=$(cast calldata "setup(address,address[],uint16,uint16,bytes32,uint256)" \
    "$IMPL" "$GUARDIAN_ARRAY" "$WORMHOLE_CHAIN_ID" "$WORMHOLE_CHAIN_ID" \
    "0x0000000000000000000000000000000000000000000000000000000000000004" "$NATIVE_CHAIN_ID")

CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" "$SETUP" "$SETUP_DATA")
WORMHOLE=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$CONTRACTS/Wormhole.bytecode")${CONSTRUCTOR_ARGS:2}" --json | jq -r '.contractAddress')

log_success "Wormhole deployed: $WORMHOLE"
echo ""
log_info "Update configs/guardian-0.conf:"
[[ "$CHAIN" == "anvil" ]] && echo "  GETH_CONTRACT=\"$WORMHOLE\"" || echo "  AVALANCHE_CONTRACT=\"$WORMHOLE\""
