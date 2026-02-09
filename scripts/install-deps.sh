#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Install all dependencies for the Private Guardian Network
# Usage: ./scripts/install-deps.sh [all|foundry|wasmvm|grpcurl|solana]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

COMPONENT="${1:-all}"

# ─── System packages (jq, curl, etc.) ──────────────────────────────────────
install_system_deps() {
    log_info "Installing system dependencies (jq, curl)..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq jq curl wget || true
    elif command -v yum &>/dev/null; then
        sudo yum install -y jq curl wget || true
    fi
    command -v jq &>/dev/null && log_success "jq installed" || log_warn "jq not found — install manually"
}

# ─── Foundry (anvil, cast, forge) ──────────────────────────────────────────
install_foundry() {
    log_info "Installing Foundry..."
    if command -v anvil &>/dev/null; then
        log_info "Foundry already installed: $(anvil --version | head -1)"
        log_info "Upgrading..."
    fi
    curl -L https://foundry.paradigm.xyz | bash
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup

    # Copy binaries to shared location so scripts find them via PATH
    mkdir -p /solana/wormhole/.foundry/bin
    cp "$HOME/.foundry/bin/"* /solana/wormhole/.foundry/bin/ 2>/dev/null || true

    # Set environment variables
    log_info "Setting Foundry env vars in ~/.bashrc..."
    grep -q "FOUNDRY_CACHE_DIR" "$HOME/.bashrc" 2>/dev/null || \
        cat >> "$HOME/.bashrc" <<'EOF'

# Foundry — cache/data stored in /solana/wormhole (not ~/.foundry)
export FOUNDRY_CACHE_DIR="/solana/wormhole/.foundry/cache"
export FOUNDRY_DATA_DIR="/solana/wormhole/.foundry/data"
export PATH="/solana/wormhole/.foundry/bin:$PATH"
EOF
    log_success "Foundry installed"
}

# ─── libwasmvm (required by guardiand) ─────────────────────────────────────
install_wasmvm() {
    log_info "Installing libwasmvm.x86_64.so..."
    command -v go &>/dev/null || { log_error "Go is required"; return 1; }

    local ver="v1.1.1" lib="libwasmvm.x86_64.so"
    local gomodcache; gomodcache="${GOMODCACHE:-$(go env GOMODCACHE)}"
    [[ -z "$gomodcache" ]] && gomodcache="$(go env GOPATH)/pkg/mod"

    go get -d "github.com/CosmWasm/wasmvm@${ver}" 2>&1 | grep -v "^go:" || true

    local lib_path
    lib_path=$(find "$gomodcache" -name "$lib" -path "*wasmvm@${ver}*" 2>/dev/null | head -1)
    if [[ -z "$lib_path" ]]; then
        local tmp; tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
        (cd "$tmp" && go mod init temp && go get "github.com/CosmWasm/wasmvm@${ver}") 2>&1 | grep -v "^go:" || true
        lib_path=$(find "$gomodcache" -name "$lib" -path "*wasmvm@${ver}*" 2>/dev/null | head -1)
    fi
    [[ -z "$lib_path" ]] && { log_error "Cannot find ${lib}"; return 1; }

    local dest="/usr/local/lib"
    if [[ "$EUID" -ne 0 ]]; then dest="$HOME/.local/lib"; fi
    mkdir -p "$dest"
    cp "$lib_path" "${dest}/${lib}" && chmod 755 "${dest}/${lib}"
    [[ "$EUID" -eq 0 ]] && ldconfig 2>/dev/null || true
    log_success "Installed ${dest}/${lib}"
    [[ "$EUID" -ne 0 ]] && log_warn "Add to shell: export LD_LIBRARY_PATH=\"\$LD_LIBRARY_PATH:${dest}\""
}

# ─── grpcurl ───────────────────────────────────────────────────────────────
install_grpcurl() {
    log_info "Installing grpcurl..."
    command -v go &>/dev/null || { log_error "Go is required"; return 1; }
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
    log_success "grpcurl installed"
}

# ─── Solana CLI ────────────────────────────────────────────────────────────
install_solana() {
    log_info "Installing Solana CLI..."
    sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
    log_success "Solana CLI installed"
}

# ─── Main ──────────────────────────────────────────────────────────────────
case "$COMPONENT" in
    all)
        install_system_deps
        install_foundry
        install_wasmvm
        install_grpcurl
        install_solana
        echo ""
        log_success "All dependencies installed"
        log_info "Reload shell: source ~/.bashrc"
        log_info "Then verify:  make status"
        ;;
    foundry)  install_foundry ;;
    wasmvm)   install_wasmvm ;;
    grpcurl)  install_grpcurl ;;
    solana)   install_solana ;;
    *)
        echo "Usage: $0 [all|foundry|wasmvm|grpcurl|solana]"
        exit 1
        ;;
esac
