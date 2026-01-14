#!/bin/bash
# Deploy Wormhole Core Bridge to Solana
# Usage: ./scripts/deploy-solana.sh [command]
#
# Commands:
#   deploy      - Deploy the program
#   initialize  - Initialize with guardian set
#   status      - Check deployment status
#   all         - Deploy and initialize (default)

set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${WORKSPACE_ROOT}/configs/guardian-0.conf"
[[ -f "$CONFIG" ]] && source "$CONFIG"

SOLANA_RPC="${SOLANA_RPC:-http://20.64.169.42:8899}"
SOLANA_KEYPAIR="${SOLANA_DEPLOYER_KEY:-../Solana-Validator-Node/keys/faucet.json}"
CONTRACTS_DIR="${WORKSPACE_ROOT}/contracts/solana"
PROGRAM_SO="${CONTRACTS_DIR}/bridge.so"
PROGRAM_ID_FILE="${CONTRACTS_DIR}/program-id.json"

# Resolve keypair path
if [[ "$SOLANA_KEYPAIR" != /* ]]; then
    SOLANA_KEYPAIR="${WORKSPACE_ROOT}/${SOLANA_KEYPAIR}"
fi

COMMAND="${1:-all}"

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command_exists solana; then
        log_error "Solana CLI not installed"
        log_info "Install: sh -c \"\$(curl -sSfL https://release.solana.com/stable/install)\""
        exit 1
    fi
    
    if [[ ! -f "$PROGRAM_SO" ]]; then
        log_error "Program binary not found: $PROGRAM_SO"
        exit 1
    fi
    
    if [[ ! -f "$SOLANA_KEYPAIR" ]]; then
        log_error "Deployer keypair not found: $SOLANA_KEYPAIR"
        exit 1
    fi
    
    # Configure Solana CLI
    solana config set --url "$SOLANA_RPC" > /dev/null
    solana config set --keypair "$SOLANA_KEYPAIR" > /dev/null
    
    log_info "RPC: $SOLANA_RPC"
    log_info "Keypair: $SOLANA_KEYPAIR"
    
    # Check balance
    BALANCE=$(solana balance --url "$SOLANA_RPC" 2>/dev/null || echo "0 SOL")
    log_info "Balance: $BALANCE"
}

generate_program_id() {
    log_info "Generating program keypair..."
    
    PROGRAM_KEYPAIR="${CONTRACTS_DIR}/program-keypair.json"
    
    if [[ -f "$PROGRAM_KEYPAIR" ]]; then
        log_warn "Program keypair already exists: $PROGRAM_KEYPAIR"
        PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR")
    else
        solana-keygen new --no-bip39-passphrase -o "$PROGRAM_KEYPAIR" --force
        PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR")
    fi
    
    echo "{\"programId\": \"$PROGRAM_ID\"}" > "$PROGRAM_ID_FILE"
    log_success "Program ID: $PROGRAM_ID"
    echo ""
    log_info "Update configs with: SOLANA_CONTRACT=\"$PROGRAM_ID\""
}

deploy_program() {
    log_info "Deploying Wormhole Core Bridge..."
    
    PROGRAM_KEYPAIR="${CONTRACTS_DIR}/program-keypair.json"
    
    if [[ ! -f "$PROGRAM_KEYPAIR" ]]; then
        log_error "Program keypair not found. Run: $0 generate"
        exit 1
    fi
    
    PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR")
    log_info "Program ID: $PROGRAM_ID"
    
    # Check if already deployed
    if solana program show "$PROGRAM_ID" --url "$SOLANA_RPC" 2>/dev/null | grep -q "Program Id"; then
        log_warn "Program already deployed at $PROGRAM_ID"
        return 0
    fi
    
    # Deploy
    log_info "Deploying program (this may take a while)..."
    solana program deploy \
        --url "$SOLANA_RPC" \
        --keypair "$SOLANA_KEYPAIR" \
        --program-id "$PROGRAM_KEYPAIR" \
        "$PROGRAM_SO"
    
    log_success "Program deployed: $PROGRAM_ID"
}

initialize_bridge() {
    log_info "Initializing Wormhole Core Bridge..."
    
    if [[ ! -f "$PROGRAM_ID_FILE" ]]; then
        log_error "Program ID file not found. Deploy first: $0 deploy"
        exit 1
    fi
    
    PROGRAM_ID=$(jq -r '.programId' "$PROGRAM_ID_FILE")
    log_info "Program ID: $PROGRAM_ID"
    
    # Guardian addresses (from config)
    GUARDIANS="${GUARDIAN_ADDRESSES:-0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe,0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c}"
    
    log_info "Guardian addresses: $GUARDIANS"
    
    # Check if already initialized by checking bridge config account
    BRIDGE_CONFIG=$(solana program show "$PROGRAM_ID" --url "$SOLANA_RPC" 2>&1 || echo "")
    
    if echo "$BRIDGE_CONFIG" | grep -q "Upgradeable program"; then
        log_info "Program is deployed and upgradeable"
    fi
    
    # Initialize using the Wormhole SDK approach
    # The bridge needs to be initialized with guardian set
    log_info "To initialize the bridge, use the Wormhole SDK or CLI:"
    echo ""
    echo "  # Using @certusone/wormhole-sdk"
    echo "  import { postVaaSolana } from '@certusone/wormhole-sdk'"
    echo ""
    echo "  # Or use the existing deploy-solana.js script:"
    echo "  cd ../Solana-WormHole && node src/cli/deploy-solana.js initialize"
    echo ""
    
    log_success "Program ready at: $PROGRAM_ID"
    log_info "Update configs: SOLANA_CONTRACT=\"$PROGRAM_ID\""
}

show_status() {
    log_info "Checking Solana Wormhole status..."
    
    echo ""
    echo "RPC: $SOLANA_RPC"
    
    # Check connection
    if ! solana cluster-version --url "$SOLANA_RPC" 2>/dev/null; then
        log_error "Cannot connect to Solana RPC"
        exit 1
    fi
    
    # Check program
    if [[ -f "$PROGRAM_ID_FILE" ]]; then
        PROGRAM_ID=$(jq -r '.programId' "$PROGRAM_ID_FILE")
        echo ""
        log_info "Program ID: $PROGRAM_ID"
        solana program show "$PROGRAM_ID" --url "$SOLANA_RPC" 2>/dev/null || log_warn "Program not found on chain"
    else
        log_warn "Program ID file not found"
    fi
    
    # Check deployer balance
    echo ""
    log_info "Deployer balance:"
    solana balance --url "$SOLANA_RPC" --keypair "$SOLANA_KEYPAIR"
}

# Main
case "$COMMAND" in
    generate)
        check_prerequisites
        generate_program_id
        ;;
    deploy)
        check_prerequisites
        deploy_program
        ;;
    initialize)
        check_prerequisites
        initialize_bridge
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    all)
        check_prerequisites
        generate_program_id
        deploy_program
        initialize_bridge
        ;;
    *)
        echo "Usage: $0 [generate|deploy|initialize|status|all]"
        echo ""
        echo "Commands:"
        echo "  generate    Generate program keypair"
        echo "  deploy      Deploy program to Solana"
        echo "  initialize  Initialize bridge with guardians"
        echo "  status      Check deployment status"
        echo "  all         Generate, deploy, and initialize (default)"
        exit 1
        ;;
esac
