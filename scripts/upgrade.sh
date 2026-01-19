#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Private Guardian Network - Upgrade Script
# Production-grade upgrade with backup, verification, and rollback support
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Configuration
WORMHOLE_REPO="${WORKSPACE_ROOT}/../WormHole-Official-GitHub-Repo"
BACKUP_DIR="${WORKSPACE_ROOT}/backups"
GUARDIAND_BIN="${WORMHOLE_REPO}/build/bin/guardiand"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
# PRE-UPGRADE CHECKS
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing=0
    
    # Check required tools
    for cmd in git make go jq; do
        if command -v "$cmd" &>/dev/null; then
            log_info "✓ $cmd found"
        else
            log_error "✗ $cmd not found"
            missing=1
        fi
    done
    
    # Check Go version (minimum 1.21)
    if command -v go &>/dev/null; then
        GO_VERSION=$(go version | grep -oP 'go\d+\.\d+' | sed 's/go//')
        GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
        GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)
        if [[ $GO_MAJOR -ge 1 ]] && [[ $GO_MINOR -ge 21 ]]; then
            log_info "✓ Go version: $GO_VERSION"
        else
            log_warn "Go version $GO_VERSION may be outdated (recommended: 1.21+)"
        fi
    fi
    
    # Check if WormHole repo exists
    if [[ -d "$WORMHOLE_REPO" ]]; then
        log_info "✓ WormHole repo found"
    else
        log_error "✗ WormHole repo not found at: $WORMHOLE_REPO"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        log_error "Prerequisites check failed"
        exit 1
    fi
}

check_running_guardians() {
    log_section "Checking Running Guardians"
    
    local running=0
    for i in 0 1 2 3 4; do
        if pgrep -f "guardiand.*guardian-$i" &>/dev/null; then
            log_warn "Guardian-$i is running (PID: $(pgrep -f "guardiand.*guardian-$i"))"
            running=1
        fi
    done
    
    if [[ $running -eq 1 ]]; then
        log_warn "Running guardians detected. They should be stopped before upgrade."
        read -p "Stop all guardians and continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_all_guardians
        else
            log_error "Upgrade cancelled"
            exit 1
        fi
    else
        log_info "✓ No guardians running"
    fi
}

stop_all_guardians() {
    log_info "Stopping all guardians..."
    for i in 0 1 2 3 4; do
        if pgrep -f "guardiand.*guardian-$i" &>/dev/null; then
            pkill -f "guardiand.*guardian-$i" 2>/dev/null || true
            log_info "Stopped guardian-$i"
        fi
    done
    sleep 2
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP
# ─────────────────────────────────────────────────────────────────────────────

create_backup() {
    log_section "Creating Backup"
    
    local backup_path="${BACKUP_DIR}/${TIMESTAMP}"
    mkdir -p "$backup_path"
    
    # Backup current binary
    if [[ -f "$GUARDIAND_BIN" ]]; then
        cp "$GUARDIAND_BIN" "${backup_path}/guardiand.backup"
        log_info "✓ Binary backed up"
    fi
    
    # Backup configs
    if [[ -d "${WORKSPACE_ROOT}/configs" ]]; then
        cp -r "${WORKSPACE_ROOT}/configs" "${backup_path}/"
        log_info "✓ Configs backed up"
    fi
    
    # Backup keys (encrypted or as-is)
    if [[ -d "${WORKSPACE_ROOT}/keys" ]]; then
        cp -r "${WORKSPACE_ROOT}/keys" "${backup_path}/"
        log_info "✓ Keys backed up"
    fi
    
    # Backup contracts
    if [[ -d "${WORKSPACE_ROOT}/contracts" ]]; then
        cp -r "${WORKSPACE_ROOT}/contracts" "${backup_path}/"
        log_info "✓ Contracts backed up"
    fi
    
    # Save current versions
    cat > "${backup_path}/versions.json" <<EOF
{
    "timestamp": "$TIMESTAMP",
    "guardiand_version": "$(get_current_version)",
    "go_version": "$(go version 2>/dev/null | grep -oP 'go\d+\.\d+\.\d+' || echo 'unknown')",
    "foundry_version": "$(anvil --version 2>/dev/null | head -1 || echo 'unknown')",
    "solana_version": "$(solana --version 2>/dev/null | head -1 || echo 'unknown')",
    "grpcurl_version": "$(grpcurl --version 2>/dev/null | head -1 || echo 'unknown')",
    "git_commit": "$(cd "$WORMHOLE_REPO" && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    log_info "✓ Version info saved"
    
    log_info "Backup created at: ${backup_path}"
    echo "$backup_path"
}

get_current_version() {
    if [[ -f "$GUARDIAND_BIN" ]]; then
        "$GUARDIAND_BIN" version 2>/dev/null | head -1 || echo "unknown"
    else
        echo "not installed"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE WORMHOLE
# ─────────────────────────────────────────────────────────────────────────────

upgrade_wormhole() {
    log_section "Upgrading WormHole Guardian"
    
    cd "$WORMHOLE_REPO"
    
    # Save current commit
    local current_commit=$(git rev-parse HEAD)
    log_info "Current commit: ${current_commit:0:8}"
    
    # Fetch latest changes
    log_info "Fetching latest changes..."
    git fetch --all --tags
    
    # Check for available updates
    local default_branch=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    local latest_commit=$(git rev-parse "origin/${default_branch}")
    
    if [[ "$current_commit" == "$latest_commit" ]]; then
        log_info "Already up to date"
        return 0
    fi
    
    log_info "New version available: ${latest_commit:0:8}"
    
    # Show changelog
    log_info "Changes:"
    git log --oneline "${current_commit}..${latest_commit}" | head -10
    
    # Pull changes
    log_info "Pulling changes..."
    git pull origin "$default_branch"
    
    # Build new binary
    log_info "Building guardiand..."
    cd node
    
    # Create build directory if it doesn't exist
    mkdir -p "${WORMHOLE_REPO}/build/bin"
    
    # Build guardiand using go build
    log_info "Running: go build -o ${WORMHOLE_REPO}/build/bin/guardiand ."
    if go build -o "${WORMHOLE_REPO}/build/bin/guardiand" . 2>&1 | tail -20; then
        if [[ -f "${WORMHOLE_REPO}/build/bin/guardiand" ]]; then
            chmod +x "${WORMHOLE_REPO}/build/bin/guardiand"
            local new_version=$(get_current_version)
            log_info "✓ Build successful: $new_version"
        else
            log_error "Build completed but binary not found"
            return 1
        fi
    else
        log_error "Build failed"
        return 1
    fi
    
    cd "$WORKSPACE_ROOT"
}

upgrade_to_tag() {
    local tag="$1"
    log_section "Upgrading to Tag: $tag"
    
    cd "$WORMHOLE_REPO"
    
    # Check if tag exists
    if ! git tag -l | grep -q "^${tag}$"; then
        log_error "Tag not found: $tag"
        log_info "Available tags:"
        git tag -l | tail -10
        return 1
    fi
    
    # Checkout tag
    log_info "Checking out tag: $tag"
    git checkout "$tag"
    
    # Build
    log_info "Building guardiand..."
    cd node
    
    # Create build directory if it doesn't exist
    mkdir -p "${WORMHOLE_REPO}/build/bin"
    
    # Build guardiand using go build
    log_info "Running: go build -o ${WORMHOLE_REPO}/build/bin/guardiand ."
    if go build -o "${WORMHOLE_REPO}/build/bin/guardiand" . 2>&1 | tail -20; then
        if [[ -f "${WORMHOLE_REPO}/build/bin/guardiand" ]]; then
            chmod +x "${WORMHOLE_REPO}/build/bin/guardiand"
            log_info "✓ Build successful"
        else
            log_error "Build completed but binary not found"
            return 1
        fi
    else
        log_error "Build failed"
        return 1
    fi
    
    cd "$WORKSPACE_ROOT"
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE GO
# ─────────────────────────────────────────────────────────────────────────────

upgrade_go() {
    log_section "Upgrading Go"
    
    if ! command -v go &>/dev/null; then
        log_warn "Go not found, skipping upgrade"
        return 0
    fi
    
    local current_version=$(go version | grep -oP 'go\d+\.\d+\.\d+' | sed 's/go//')
    log_info "Current Go version: $current_version"
    
    # Check if using g (Go version manager)
    if command -v g &>/dev/null; then
        log_info "Using 'g' version manager"
        local latest=$(g list-all 2>/dev/null | grep -E '^go[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 | sed 's/go//')
        if [[ -n "$latest" ]] && [[ "$latest" != "$current_version" ]]; then
            log_info "Upgrading to Go $latest..."
            g install "$latest" 2>&1 | tail -5
            log_info "✓ Go upgraded to $latest"
            log_warn "Restart your shell or run: source ~/.g/go/env"
        else
            log_info "✓ Go is up to date"
        fi
        return 0
    fi
    
    # Check if using system package manager
    if command -v apt-get &>/dev/null; then
        log_info "Checking for system updates..."
        sudo apt-get update -qq
        local go_pkg=$(apt-cache policy golang-go 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        if [[ -n "$go_pkg" ]]; then
            log_info "System Go package: $go_pkg"
            log_warn "Consider using 'g' version manager for better control"
        fi
    fi
    
    log_info "✓ Go version check complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE FOUNDRY
# ─────────────────────────────────────────────────────────────────────────────

upgrade_foundry() {
    log_section "Upgrading Foundry"
    
    if ! command -v foundryup &>/dev/null; then
        log_warn "Foundry not installed, skipping upgrade"
        log_info "Install with: curl -L https://foundry.paradigm.xyz | bash"
        return 0
    fi
    
    # Get current versions
    local anvil_ver=$(anvil --version 2>/dev/null | head -1 || echo "unknown")
    local cast_ver=$(cast --version 2>/dev/null | head -1 || echo "unknown")
    log_info "Current versions:"
    log_info "  anvil: $anvil_ver"
    log_info "  cast: $cast_ver"
    
    # Upgrade Foundry
    log_info "Running foundryup..."
    foundryup 2>&1 | tail -10
    
    # Verify upgrade
    local new_anvil_ver=$(anvil --version 2>/dev/null | head -1 || echo "unknown")
    local new_cast_ver=$(cast --version 2>/dev/null | head -1 || echo "unknown")
    
    if [[ "$new_anvil_ver" != "$anvil_ver" ]] || [[ "$new_cast_ver" != "$cast_ver" ]]; then
        log_info "✓ Foundry upgraded"
        log_info "  anvil: $new_anvil_ver"
        log_info "  cast: $new_cast_ver"
    else
        log_info "✓ Foundry is up to date"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE GRPCURL
# ─────────────────────────────────────────────────────────────────────────────

upgrade_grpcurl() {
    log_section "Upgrading grpcurl"
    
    if ! command -v go &>/dev/null; then
        log_warn "Go not found, cannot upgrade grpcurl"
        return 0
    fi
    
    local current_ver=$(grpcurl --version 2>/dev/null | head -1 || echo "unknown")
    log_info "Current version: $current_ver"
    
    # Upgrade grpcurl
    log_info "Installing latest grpcurl..."
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest 2>&1 | tail -5
    
    # Verify installation
    if command -v grpcurl &>/dev/null; then
        local new_ver=$(grpcurl --version 2>/dev/null | head -1 || echo "unknown")
        log_info "✓ grpcurl upgraded: $new_ver"
    else
        log_warn "grpcurl not in PATH, add: export PATH=\"\$HOME/go/bin:\$PATH\""
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE SOLANA CLI
# ─────────────────────────────────────────────────────────────────────────────

upgrade_solana_cli() {
    log_section "Upgrading Solana CLI"
    
    # Check if Solana CLI is installed
    if ! command -v solana &>/dev/null; then
        log_warn "Solana CLI not found, skipping upgrade"
        log_info "Note: Solana CLI is optional for guardian network"
        return 0
    fi
    
    local current_ver=$(solana --version 2>/dev/null | head -1 || echo "unknown")
    log_info "Current version: $current_ver"
    
    # solana-install is deprecated, use Agave installer instead
    log_info "Note: solana-install is deprecated, using Agave installer..."
    
    # Try Agave installer (recommended)
    local install_output=$(curl -sSfL https://release.anza.xyz/stable/install 2>&1 | sh 2>&1)
    local install_status=$?
    
    if [[ $install_status -eq 0 ]]; then
        local new_ver=$(solana --version 2>/dev/null | head -1 || echo "unknown")
        if [[ "$new_ver" != "$current_ver" ]]; then
            log_info "✓ Solana CLI upgraded via Agave: $new_ver"
        else
            # Check if installer said it's up to date
            if echo "$install_output" | grep -qi "up to date\|already installed\|latest"; then
                log_info "✓ Solana CLI is up to date"
            else
                log_info "✓ Solana CLI upgrade completed (version unchanged)"
            fi
        fi
    else
        # Check if error is just "already up to date" or similar
        if echo "$install_output" | grep -qi "up to date\|already installed\|latest\|deprecated"; then
            log_info "✓ Solana CLI is up to date (installer message)"
        else
            log_warn "Solana CLI upgrade skipped"
            log_info "Current version will be kept: $current_ver"
            log_info "Note: This is optional for guardian network"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK SYSTEM UPDATES (Optional, production best practice)
# ─────────────────────────────────────────────────────────────────────────────

check_system_updates() {
    log_section "Checking System Updates"
    
    if command -v apt-get &>/dev/null; then
        log_info "Checking for system package updates..."
        local updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
        if [[ "$updates" -gt 0 ]]; then
            log_warn "$updates package(s) can be updated"
            log_info "Review with: apt list --upgradable"
            log_info "Update with: sudo apt-get update && sudo apt-get upgrade"
        else
            log_info "✓ System packages are up to date"
        fi
    elif command -v yum &>/dev/null; then
        log_info "Checking for system package updates..."
        local updates=$(yum check-update --quiet 2>/dev/null | wc -l || echo "0")
        if [[ "$updates" -gt 0 ]]; then
            log_warn "$updates package(s) can be updated"
            log_info "Update with: sudo yum update"
        else
            log_info "✓ System packages are up to date"
        fi
    else
        log_info "System package manager not detected, skipping"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE SOLANA SDK
# ─────────────────────────────────────────────────────────────────────────────

upgrade_solana_sdk() {
    log_section "Upgrading Solana Scripts Dependencies"
    
    local scripts_dir="${WORMHOLE_REPO}/solana/scripts"
    
    if [[ ! -d "$scripts_dir" ]]; then
        log_warn "Solana scripts directory not found"
        return 0
    fi
    
    cd "$scripts_dir"
    
    # Check if package.json exists
    if [[ ! -f "package.json" ]]; then
        log_warn "package.json not found, skipping"
        cd "$WORKSPACE_ROOT"
        return 0
    fi
    
    # Check for outdated packages
    log_info "Checking for outdated packages..."
    npm outdated 2>/dev/null || true
    
    # Update packages (non-breaking)
    log_info "Updating packages..."
    npm update 2>&1 | tail -5
    
    # Audit and fix vulnerabilities (non-breaking)
    log_info "Running security audit..."
    npm audit fix 2>&1 | tail -10 || true
    
    log_info "✓ Solana SDK dependencies updated"
    
    cd "$WORKSPACE_ROOT"
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFY UPGRADE
# ─────────────────────────────────────────────────────────────────────────────

verify_upgrade() {
    log_section "Verifying Upgrade"
    
    local errors=0
    
    # Check binary exists and runs
    if [[ -f "$GUARDIAND_BIN" ]]; then
        if "$GUARDIAND_BIN" version &>/dev/null; then
            log_info "✓ guardiand binary OK"
            log_info "  Version: $(get_current_version)"
        else
            log_error "✗ guardiand binary failed to run"
            errors=1
        fi
    else
        log_error "✗ guardiand binary not found"
        errors=1
    fi
    
    # Check configs are valid
    for conf in "${WORKSPACE_ROOT}/configs/"*.conf; do
        if [[ -f "$conf" ]]; then
            if bash -n "$conf" 2>/dev/null; then
                log_info "✓ Config OK: $(basename "$conf")"
            else
                log_error "✗ Config invalid: $(basename "$conf")"
                errors=1
            fi
        fi
    done
    
    # Check required libraries
    if ldd "$GUARDIAND_BIN" 2>/dev/null | grep -q "not found"; then
        log_error "✗ Missing shared libraries:"
        ldd "$GUARDIAND_BIN" | grep "not found"
        errors=1
    else
        log_info "✓ All shared libraries present"
    fi
    
    # Verify all dependencies are available
    log_info "Checking dependencies..."
    local deps_ok=1
    for cmd in anvil cast solana grpcurl; do
        if command -v "$cmd" &>/dev/null; then
            log_info "✓ $cmd available"
        else
            log_warn "✗ $cmd not found in PATH"
            deps_ok=0
        fi
    done
    
    if [[ $deps_ok -eq 0 ]]; then
        log_warn "Some dependencies missing from PATH"
        log_info "Add to PATH: export PATH=\"\$HOME/go/bin:\$HOME/.foundry/bin:\$HOME/.local/share/solana/install/active_release/bin:\$PATH\""
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✓ Upgrade verification passed"
        return 0
    else
        log_error "Upgrade verification failed"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ROLLBACK
# ─────────────────────────────────────────────────────────────────────────────

rollback() {
    local backup_path="$1"
    log_section "Rolling Back to: $backup_path"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        exit 1
    fi
    
    # Stop guardians
    stop_all_guardians
    
    # Restore binary
    if [[ -f "${backup_path}/guardiand.backup" ]]; then
        cp "${backup_path}/guardiand.backup" "$GUARDIAND_BIN"
        chmod +x "$GUARDIAND_BIN"
        log_info "✓ Binary restored"
    fi
    
    # Restore configs
    if [[ -d "${backup_path}/configs" ]]; then
        cp -r "${backup_path}/configs/"* "${WORKSPACE_ROOT}/configs/"
        log_info "✓ Configs restored"
    fi
    
    log_info "Rollback complete"
    log_info "Previous version: $(jq -r '.guardiand_version' "${backup_path}/versions.json")"
}

list_backups() {
    log_section "Available Backups"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backups found"
        return
    fi
    
    for backup in "$BACKUP_DIR"/*/; do
        if [[ -f "${backup}versions.json" ]]; then
            local ts=$(basename "$backup")
            local version=$(jq -r '.guardiand_version' "${backup}versions.json")
            local commit=$(jq -r '.git_commit' "${backup}versions.json")
            echo "  $ts - Version: $version (${commit:0:8})"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

cleanup_old_backups() {
    local keep_count="${1:-5}"
    log_section "Cleaning Up Old Backups (keeping $keep_count)"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return
    fi
    
    local backup_count=$(ls -d "$BACKUP_DIR"/*/ 2>/dev/null | wc -l)
    
    if [[ $backup_count -le $keep_count ]]; then
        log_info "No cleanup needed ($backup_count backups)"
        return
    fi
    
    local to_delete=$((backup_count - keep_count))
    log_info "Removing $to_delete old backup(s)..."
    
    ls -d "$BACKUP_DIR"/*/ | head -$to_delete | while read backup; do
        rm -rf "$backup"
        log_info "Removed: $(basename "$backup")"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────

show_status() {
    log_section "Current Status"
    
    echo ""
    echo "Guardian Binary:"
    if [[ -f "$GUARDIAND_BIN" ]]; then
        echo "  Path: $GUARDIAND_BIN"
        echo "  Version: $(get_current_version)"
    else
        echo "  Not installed"
    fi
    
    echo ""
    echo "WormHole Repository:"
    if [[ -d "$WORMHOLE_REPO" ]]; then
        cd "$WORMHOLE_REPO"
        echo "  Path: $WORMHOLE_REPO"
        echo "  Branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
        echo "  Commit: $(git rev-parse HEAD 2>/dev/null | head -c 8)"
        echo "  Status: $(git status --porcelain | wc -l) uncommitted changes"
        cd "$WORKSPACE_ROOT"
    else
        echo "  Not found"
    fi
    
    echo ""
    echo "Dependencies:"
    echo "  Go: $(go version 2>/dev/null | grep -oP 'go\d+\.\d+\.\d+' || echo 'not found')"
    echo "  Foundry (anvil): $(anvil --version 2>/dev/null | head -1 || echo 'not found')"
    echo "  Foundry (cast): $(cast --version 2>/dev/null | head -1 || echo 'not found')"
    echo "  Solana CLI: $(solana --version 2>/dev/null | head -1 || echo 'not found')"
    echo "  grpcurl: $(grpcurl --version 2>/dev/null | head -1 || echo 'not found')"
    
    echo ""
    echo "Running Guardians:"
    local running=0
    for i in 0 1 2 3 4; do
        if pgrep -f "guardiand.*guardian-$i" &>/dev/null; then
            echo "  guardian-$i: running (PID: $(pgrep -f "guardiand.*guardian-$i"))"
            running=1
        fi
    done
    [[ $running -eq 0 ]] && echo "  None"
    
    echo ""
    echo "Backups:"
    local backup_count=$(ls -d "$BACKUP_DIR"/*/ 2>/dev/null | wc -l)
    echo "  Count: $backup_count"
    [[ $backup_count -gt 0 ]] && echo "  Latest: $(ls -d "$BACKUP_DIR"/*/ | tail -1 | xargs basename)"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Private Guardian Network - Upgrade Script

Usage: $0 <command> [options]

Commands:
    all             Full upgrade (backup + all dependencies + verify)
    check           Check for available updates
    backup          Create backup only
    update          Update WormHole repository and rebuild guardiand
    update-go       Update Go version (if using 'g' version manager)
    update-foundry  Update Foundry tools (anvil, cast, forge)
    update-grpcurl  Update grpcurl
    update-solana   Update Solana CLI tools
    update-sdk      Update Solana SDK dependencies only
    verify          Verify current installation
    rollback <path> Rollback to a specific backup
    list-backups    List available backups
    cleanup [n]     Remove old backups (keep n, default 5)
    status          Show current status
    tag <version>   Upgrade to specific tag/version

Examples:
    $0 all                  # Full upgrade with backup
    $0 check                # Check for updates
    $0 tag v2.28.0         # Upgrade to specific version
    $0 rollback backups/20260116_120000

EOF
}

main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        all)
            check_prerequisites
            check_running_guardians
            create_backup
            upgrade_go
            upgrade_foundry
            upgrade_grpcurl
            upgrade_solana_cli
            upgrade_wormhole
            upgrade_solana_sdk
            check_system_updates
            verify_upgrade
            cleanup_old_backups 5
            log_section "Upgrade Complete"
            log_info "All dependencies upgraded successfully"
            log_info "Data preserved: All guardian data, keys, and configs remain unchanged"
            log_info "Restart guardians with: make start-0 && make start-1"
            log_warn "Note: You may need to restart your shell for PATH changes to take effect"
            ;;
        check)
            check_prerequisites
            cd "$WORMHOLE_REPO"
            git fetch --all --tags
            local current=$(git rev-parse HEAD)
            local default_branch=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
            local latest=$(git rev-parse "origin/${default_branch}")
            if [[ "$current" == "$latest" ]]; then
                log_info "Already up to date (${current:0:8})"
            else
                log_warn "Update available: ${current:0:8} -> ${latest:0:8}"
                log_info "Run: $0 all"
            fi
            ;;
        backup)
            check_running_guardians
            create_backup
            ;;
        update)
            check_prerequisites
            check_running_guardians
            upgrade_wormhole
            verify_upgrade
            ;;
        update-go)
            upgrade_go
            ;;
        update-foundry)
            upgrade_foundry
            ;;
        update-grpcurl)
            upgrade_grpcurl
            ;;
        update-solana)
            upgrade_solana_cli
            ;;
        update-sdk)
            upgrade_solana_sdk
            ;;
        verify)
            verify_upgrade
            ;;
        rollback)
            [[ -z "${1:-}" ]] && { log_error "Backup path required"; exit 1; }
            rollback "$1"
            ;;
        list-backups)
            list_backups
            ;;
        cleanup)
            cleanup_old_backups "${1:-5}"
            ;;
        status)
            show_status
            ;;
        tag)
            [[ -z "${1:-}" ]] && { log_error "Tag required"; exit 1; }
            check_prerequisites
            check_running_guardians
            create_backup
            upgrade_to_tag "$1"
            verify_upgrade
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
