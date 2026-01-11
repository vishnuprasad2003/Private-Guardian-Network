#!/bin/bash
# =============================================================================
# INSTALL DEPENDENCIES
# =============================================================================
# Installs all required dependencies for running a guardian node.
# Run this on each VM before starting the guardian.
#
# Usage: ./scripts/setup/install-deps.sh [--all | --minimal]
#   --all      Install all dependencies (default)
#   --minimal  Install only required dependencies (no Solana, no Geth)
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

INSTALL_MODE="${1:---all}"

echo "=============================================="
echo "Private Guardian Network - Dependency Setup"
echo "=============================================="
echo "Mode: $INSTALL_MODE"
echo ""

# Update package list
log_step "Updating package list..."
sudo apt-get update -qq

# Install basic tools
log_step "Installing basic tools..."
sudo apt-get install -y -qq curl wget git jq build-essential software-properties-common

# Install Go (required for guardiand)
log_step "Checking Go..."
if ! command -v go &> /dev/null; then
    log_info "Installing Go 1.21.5..."
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
    rm go1.21.5.linux-amd64.tar.gz
    
    # Add to PATH
    if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    export PATH=$PATH:/usr/local/go/bin
fi
log_info "Go: $(go version)"

# Install Node.js (required for API server)
log_step "Checking Node.js..."
if ! command -v node &> /dev/null; then
    log_info "Installing Node.js 20.x..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
fi
log_info "Node.js: $(node --version)"
log_info "npm: $(npm --version)"

# Install Foundry (required for contract deployment and Anvil)
log_step "Checking Foundry (Anvil, Cast, Forge)..."
if ! command -v cast &> /dev/null; then
    log_info "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    
    # Add to PATH for current session
    export PATH="$HOME/.foundry/bin:$PATH"
    
    # Add to bashrc
    if ! grep -q '.foundry/bin' ~/.bashrc; then
        echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
    fi
    
    # Run foundryup to install the tools
    "$HOME/.foundry/bin/foundryup"
fi

if command -v cast &> /dev/null; then
    log_info "Foundry installed:"
    log_info "  Anvil: $(anvil --version 2>/dev/null | head -1)"
    log_info "  Cast:  $(cast --version 2>/dev/null | head -1)"
    log_info "  Forge: $(forge --version 2>/dev/null | head -1)"
else
    log_warn "Foundry not in PATH. Add to PATH:"
    echo '  export PATH="$HOME/.foundry/bin:$PATH"'
fi

# Optional: Install Geth (only needed for heavy production with consensus client)
if [ "$INSTALL_MODE" = "--all" ]; then
    log_step "Checking Geth (optional)..."
    if ! command -v geth &> /dev/null; then
        log_info "Installing Geth..."
        sudo add-apt-repository -y ppa:ethereum/ethereum
        sudo apt-get update -qq
        sudo apt-get install -y -qq ethereum
    fi
    if command -v geth &> /dev/null; then
        log_info "Geth: $(geth version 2>/dev/null | head -1)"
    fi
fi

# Optional: Install Solana CLI
if [ "$INSTALL_MODE" = "--all" ]; then
    log_step "Checking Solana CLI..."
    if ! command -v solana &> /dev/null; then
        log_warn "Solana CLI not installed. Install if needed for Solana deployment:"
        echo '  sh -c "$(curl -sSfL https://release.solana.com/stable/install)"'
        echo '  export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"'
    else
        log_info "Solana: $(solana --version)"
    fi
fi

echo ""
echo "=============================================="
echo -e "${GREEN}Dependencies installed successfully!${NC}"
echo "=============================================="
echo ""
echo "IMPORTANT: Restart your terminal or run:"
echo "  source ~/.bashrc"
echo ""
echo "Next steps:"
echo ""
echo "  1. Clone Wormhole repository (if not done):"
echo "     git clone https://github.com/wormhole-foundation/wormhole.git ../WormHole-Official-GitHub-Repo"
echo ""
echo "  2. Build guardiand:"
echo "     cd ../WormHole-Official-GitHub-Repo/node"
echo "     go build -o ../build/bin/guardiand ."
echo "     cd -"
echo ""
echo "  3. Install npm packages:"
echo "     npm install"
echo ""
echo "  4. Copy and edit config:"
echo "     cp config/guardian.conf.example config/guardian.conf"
echo "     nano config/guardian.conf"
echo ""
echo "  5. Start Anvil (local Ethereum node):"
echo "     bin/anvil start"
echo ""
echo "  6. Deploy contracts:"
echo "     export PRIVATE_KEY=\"0x...\""
echo "     ./scripts/deploy/deploy-evm.sh geth http://localhost:8545 \"GUARDIAN_ADDRESS\""
echo ""
echo "  7. Start guardian:"
echo "     sudo hostname guardian-0"
echo "     bin/guardian start"
echo ""
echo "  8. Start API server:"
echo "     bin/api start"
echo ""
echo "=============================================="
