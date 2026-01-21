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

SOLANA_RPC="${SOLANA_RPC:-http://localhost:8899}"
SOLANA_KEYPAIR="${SOLANA_DEPLOYER_KEY:-../Solana-Validator-Node/keys/faucet.json}"
CONTRACTS_DIR="/solana/wormhole/contracts/solana"
PROGRAM_SO="${CONTRACTS_DIR}/bridge.so"
PROGRAM_ID_FILE="${CONTRACTS_DIR}/program-id.json"

# Resolve keypair path (handle relative paths and spaces)
if [[ "$SOLANA_KEYPAIR" != /* ]]; then
    # Resolve relative to workspace root using realpath or manual resolution
    if command -v realpath >/dev/null 2>&1; then
        SOLANA_KEYPAIR="$(realpath -m "${WORKSPACE_ROOT}/${SOLANA_KEYPAIR}")"
    else
        # Manual resolution: cd to workspace root, then resolve the relative path
        # This handles paths with ../ correctly
        SOLANA_KEYPAIR="$(cd "${WORKSPACE_ROOT}" && cd "$(dirname "${SOLANA_KEYPAIR}")" && pwd)/$(basename "${SOLANA_KEYPAIR}")"
    fi
fi

COMMAND="${1:-all}"

# Helper function to get a keypair path that works with Solana CLI (handles spaces)
get_solana_keypair_path() {
    local keypair="$1"
    if [[ "$keypair" == *" "* ]]; then
        # Create temp copy without spaces
        local temp_keypair="/tmp/solana-keypair-$$-$(basename "$keypair")"
        cp "$keypair" "$temp_keypair" 2>/dev/null || {
            log_error "Failed to copy keypair to temp location"
            exit 1
        }
        echo "$temp_keypair"
    else
        echo "$keypair"
    fi
}

# Cleanup function for temp keypairs
cleanup_temp_keypair() {
    local temp_keypair="$1"
    [[ -n "$temp_keypair" ]] && [[ "$temp_keypair" == /tmp/solana-keypair-* ]] && rm -f "$temp_keypair" 2>/dev/null || true
}

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
    
    # Configure Solana CLI (set URL only, we'll pass keypair explicitly)
    solana config set --url "$SOLANA_RPC" > /dev/null
    
    log_info "RPC: $SOLANA_RPC"
    log_info "Keypair: $SOLANA_KEYPAIR"
    
    # Check balance (use temp keypair if path has spaces)
    TEMP_KEYPAIR=$(get_solana_keypair_path "$SOLANA_KEYPAIR")
    BALANCE_OUTPUT=$(solana balance --url "$SOLANA_RPC" --keypair "$TEMP_KEYPAIR" 2>&1)
    BALANCE_EXIT=$?
    cleanup_temp_keypair "$TEMP_KEYPAIR"
    
    if [[ $BALANCE_EXIT -eq 0 ]]; then
        log_info "Balance: $BALANCE_OUTPUT"
        # Check if balance is actually 0 (not just contains "0" in the string)
        BALANCE_VALUE=$(echo "$BALANCE_OUTPUT" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
        if [[ -z "$BALANCE_VALUE" ]] || [[ "$BALANCE_VALUE" == "0" ]]; then
            log_warn "Deployer account has 0 SOL. Deployment will fail."
            log_info "Airdrop SOL: solana airdrop 2 --url $SOLANA_RPC --keypair $SOLANA_KEYPAIR"
        fi
    else
        log_warn "Could not check balance: $BALANCE_OUTPUT"
    fi
}

generate_program_id() {
    log_info "Generating program keypair..."
    
    PROGRAM_KEYPAIR="${CONTRACTS_DIR}/program-keypair.json"
    
    if [[ -f "$PROGRAM_KEYPAIR" ]]; then
        log_warn "Program keypair already exists: $PROGRAM_KEYPAIR"
        # Use temp file if path has spaces (workaround for solana-keygen)
        if [[ "$PROGRAM_KEYPAIR" == *" "* ]]; then
            TEMP_KEYPAIR="/tmp/solana-temp-keypair-$$.json"
            cp "$PROGRAM_KEYPAIR" "$TEMP_KEYPAIR"
            PROGRAM_ID=$(solana-keygen pubkey "$TEMP_KEYPAIR" 2>&1) || {
                rm -f "$TEMP_KEYPAIR" 2>/dev/null
                log_error "Failed to read program keypair"
                exit 1
            }
            rm -f "$TEMP_KEYPAIR" 2>/dev/null
        else
            PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR" 2>&1) || {
                log_error "Failed to read program keypair"
                exit 1
            }
        fi
    else
        # Create new keypair - use temp location if output path has spaces
        if [[ "$PROGRAM_KEYPAIR" == *" "* ]]; then
            TEMP_KEYPAIR="/tmp/solana-temp-keypair-$$.json"
            solana-keygen new --no-bip39-passphrase -o "$TEMP_KEYPAIR" --force
            PROGRAM_ID=$(solana-keygen pubkey "$TEMP_KEYPAIR" 2>&1) || {
                rm -f "$TEMP_KEYPAIR" 2>/dev/null
                log_error "Failed to generate program keypair"
                exit 1
            }
            # Copy to final location
            mkdir -p "$(dirname "$PROGRAM_KEYPAIR")"
            cp "$TEMP_KEYPAIR" "$PROGRAM_KEYPAIR"
            rm -f "$TEMP_KEYPAIR" 2>/dev/null
        else
            solana-keygen new --no-bip39-passphrase -o "$PROGRAM_KEYPAIR" --force
            PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR" 2>&1) || {
                log_error "Failed to generate program keypair"
                exit 1
            }
        fi
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
    
    # Read program ID (use temp file if path has spaces)
    if [[ "$PROGRAM_KEYPAIR" == *" "* ]]; then
        TEMP_READ_KEYPAIR="/tmp/solana-read-keypair-$$.json"
        cp "$PROGRAM_KEYPAIR" "$TEMP_READ_KEYPAIR"
        PROGRAM_ID=$(solana-keygen pubkey "$TEMP_READ_KEYPAIR" 2>&1) || {
            rm -f "$TEMP_READ_KEYPAIR" 2>/dev/null
            log_error "Failed to read program ID from keypair"
            exit 1
        }
        rm -f "$TEMP_READ_KEYPAIR" 2>/dev/null
    else
        PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR" 2>&1) || {
            log_error "Failed to read program ID from keypair"
            exit 1
        }
    fi
    log_info "Program ID: $PROGRAM_ID"
    
    # Check if already deployed
    if solana program show "$PROGRAM_ID" --url "$SOLANA_RPC" 2>/dev/null | grep -q "Program Id"; then
        log_warn "Program already deployed at $PROGRAM_ID"
        return 0
    fi
    
    # Deploy
    log_info "Deploying program (this may take a while)..."
    # Use temp keypairs if paths have spaces
    TEMP_DEPLOYER_KEYPAIR=$(get_solana_keypair_path "$SOLANA_KEYPAIR")
    TEMP_PROGRAM_KEYPAIR=""
    if [[ "$PROGRAM_KEYPAIR" == *" "* ]]; then
        TEMP_PROGRAM_KEYPAIR="/tmp/solana-program-keypair-$$.json"
        cp "$PROGRAM_KEYPAIR" "$TEMP_PROGRAM_KEYPAIR"
        PROGRAM_KEYPAIR_ARG="$TEMP_PROGRAM_KEYPAIR"
    else
        PROGRAM_KEYPAIR_ARG="$PROGRAM_KEYPAIR"
    fi
    
    # Ensure PROGRAM_SO is an absolute path
    if [[ "$PROGRAM_SO" != /* ]]; then
        PROGRAM_SO="$(realpath -m "${WORKSPACE_ROOT}/${PROGRAM_SO}")"
    fi
    
    # Deploy using the keypair file path (Solana will derive program ID from it)
    DEPLOY_EXIT=0
    solana program deploy \
        --url "$SOLANA_RPC" \
        --keypair "$TEMP_DEPLOYER_KEYPAIR" \
        --program-id "$PROGRAM_KEYPAIR_ARG" \
        "$PROGRAM_SO" || DEPLOY_EXIT=$?
    
    # Clean up temp copies
    cleanup_temp_keypair "$TEMP_DEPLOYER_KEYPAIR"
    [[ -n "$TEMP_PROGRAM_KEYPAIR" ]] && rm -f "$TEMP_PROGRAM_KEYPAIR" 2>/dev/null || true
    
    if [[ $DEPLOY_EXIT -ne 0 ]]; then
        log_error "Program deployment failed"
        exit 1
    fi
    
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
    
    # Guardian addresses (from config) - convert to JSON array without 0x prefix
    GUARDIANS="${GUARDIAN_ADDRESSES:-0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe,0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c}"
    GUARDIAN_SET=$(echo "$GUARDIANS" | sed 's/0x//g' | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    log_info "Guardian addresses: $GUARDIANS"
    
    # Resolve keypair path
    KEYPAIR_PATH="$SOLANA_KEYPAIR"
    if [[ "$KEYPAIR_PATH" != /* ]]; then
        KEYPAIR_PATH="$(realpath -m "${WORKSPACE_ROOT}/${KEYPAIR_PATH}")"
    fi
    
    # Use the initialization script from WormHole repo
    SOLANA_DIR="${WORKSPACE_ROOT}/../WormHole-Official-GitHub-Repo/solana"
    SCRIPTS_DIR="${SOLANA_DIR}/scripts"
    INIT_SCRIPT="${SCRIPTS_DIR}/initialize-core.ts"
    
    if [[ ! -f "$INIT_SCRIPT" ]]; then
        log_error "Initialization script not found: $INIT_SCRIPT"
        show_manual_init_instructions "$PROGRAM_ID" "$GUARDIAN_SET" "$KEYPAIR_PATH"
        exit 1
    fi
    
    # Check if dependencies are installed in scripts directory
    if [[ ! -d "${SCRIPTS_DIR}/node_modules/@certusone" ]]; then
        log_warn "Dependencies not installed in WormHole scripts directory"
        log_info "Installing dependencies..."
        cd "$SCRIPTS_DIR" || exit 1
        npm install 2>&1 | tail -10
        cd "${WORKSPACE_ROOT}" || exit 1
    fi
    
    # Check for npx
    if ! command_exists npx; then
        log_error "npx not found. Please install Node.js"
        show_manual_init_instructions "$PROGRAM_ID" "$GUARDIAN_SET" "$KEYPAIR_PATH"
        exit 1
    fi
    
    log_info "Initializing bridge with guardian set..."
    
    # Run the initialization script using npx tsx from scripts directory
    cd "$SCRIPTS_DIR" || exit 1
    INIT_EXIT=0
    TX_SIG=$(RPC_URL="$SOLANA_RPC" \
    CORE_BRIDGE_PROGRAM_ID="$PROGRAM_ID" \
    PRIVATE_KEY="$KEYPAIR_PATH" \
    GUARDIAN_SET="$GUARDIAN_SET" \
    FEE="${SOLANA_BRIDGE_FEE:-100000}" \
    EXPIRATION_TIME="${SOLANA_BRIDGE_EXPIRATION:-86400}" \
    npx tsx initialize-core.ts 2>&1) || INIT_EXIT=$?
    
    cd "${WORKSPACE_ROOT}" || exit 1
    
    if [[ -n "$TX_SIG" ]] && [[ "$TX_SIG" =~ ^[A-Za-z0-9]+$ ]]; then
        log_success "Transaction: $TX_SIG"
    fi
    
    if [[ $INIT_EXIT -ne 0 ]]; then
        log_error "Bridge initialization failed"
        show_manual_init_instructions "$PROGRAM_ID" "$GUARDIAN_SET" "$KEYPAIR_PATH"
        exit 1
    fi
    
    log_success "Bridge initialized successfully!"
    log_info "Program ID: $PROGRAM_ID"
}

show_manual_init_instructions() {
    local PROGRAM_ID="$1"
    local GUARDIAN_SET="$2"
    local KEYPAIR_PATH="$3"
    
    log_warn "Manual initialization required:"
    echo ""
    echo "  # Install dependencies:"
    echo "  cd ../WormHole-Official-GitHub-Repo/solana/scripts && npm install"
    echo ""
    echo "  # Then run initialization:"
    echo "  export RPC_URL=\"$SOLANA_RPC\""
    echo "  export CORE_BRIDGE_PROGRAM_ID=\"$PROGRAM_ID\""
    echo "  export PRIVATE_KEY=\"$KEYPAIR_PATH\""
    echo "  export GUARDIAN_SET='$GUARDIAN_SET'"
    echo "  npx tsx initialize-core.ts"
    echo ""
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
    TEMP_KEYPAIR=$(get_solana_keypair_path "$SOLANA_KEYPAIR")
    solana balance --url "$SOLANA_RPC" --keypair "$TEMP_KEYPAIR"
    cleanup_temp_keypair "$TEMP_KEYPAIR"
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
