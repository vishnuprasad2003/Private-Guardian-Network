#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Private Guardian Network — Shared Utilities
# Sourced by every other script. Never executed directly.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# ─── Foundry environment (prevent ~/.foundry growth) ────────────────────────
export FOUNDRY_CACHE_DIR="${FOUNDRY_CACHE_DIR:-/solana/wormhole/.foundry/cache}"
export FOUNDRY_DATA_DIR="${FOUNDRY_DATA_DIR:-/solana/wormhole/.foundry/data}"
export PATH="/solana/wormhole/.foundry/bin:${PATH}"

# ─── Logging ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_info()    { echo -e "${GREEN}[$(_ts)] INFO${NC}  $*" >&2; }
log_success() { echo -e "${GREEN}[$(_ts)]   OK${NC}  $*" >&2; }
log_warn()    { echo -e "${YELLOW}[$(_ts)] WARN${NC}  $*" >&2; }
log_error()   { echo -e "${RED}[$(_ts)] ERROR${NC} $*" >&2; }

# ─── Helpers ────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Load and resolve a guardian config. Sets all shell variables from the file
# and ensures relative GUARDIAND_BIN is resolved against WORKSPACE_ROOT.
load_config() {
    local config_file="${1:?config file required}"
    [[ ! -f "$config_file" ]] && { log_error "Config not found: $config_file"; return 1; }
    # shellcheck disable=SC1090
    source "$config_file"
    # Resolve GUARDIAND_BIN if relative
    [[ "${GUARDIAND_BIN:-}" && "$GUARDIAND_BIN" != /* ]] && \
        GUARDIAND_BIN="${WORKSPACE_ROOT}/${GUARDIAND_BIN}"
    return 0
}

# Create every directory referenced in the config.
ensure_dirs() {
    local base="${BASE_DIR:?BASE_DIR not set}"
    mkdir -p "${base}/data" "${base}/logs" "${base}/keys" \
             "${base}/pids" "${base}/sockets" "${base}/backups" \
             "${base}/contracts/solana" "${base}/.foundry/cache" "${base}/.foundry/data"
}

# ─── Process management ────────────────────────────────────────────────────
is_running() {
    local pid_file="${1:?pid file required}"
    [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null && return 0
    rm -f "$pid_file" 2>/dev/null
    return 1
}

graceful_stop() {
    local pid_file="${1:?pid file required}" name="${2:-process}" timeout="${3:-10}"
    is_running "$pid_file" || { log_warn "$name is not running"; return 0; }
    local pid; pid=$(cat "$pid_file")
    log_info "Stopping $name (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    local i
    for ((i=0; i<timeout; i++)); do
        kill -0 "$pid" 2>/dev/null || { rm -f "$pid_file"; log_success "$name stopped"; return 0; }
        sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    log_warn "$name killed after ${timeout}s timeout"
}

# ─── Validation ─────────────────────────────────────────────────────────────
validate_guardiand() {
    [[ ! -f "$GUARDIAND_BIN" ]] && { log_error "guardiand not found: $GUARDIAND_BIN"; return 1; }
    # Check libwasmvm in common locations + LD_LIBRARY_PATH
    local found=false paths=( /usr/lib /usr/local/lib "$HOME/.local/lib" )
    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        IFS=':' read -ra _extra <<< "$LD_LIBRARY_PATH"
        paths+=("${_extra[@]}")
    fi
    for p in "${paths[@]}"; do
        [[ -f "$p/libwasmvm.x86_64.so" ]] && { found=true; break; }
    done
    if ! $found && command_exists ldd; then
        ldd "$GUARDIAND_BIN" 2>/dev/null | grep -q "libwasmvm.*found" && found=true
    fi
    $found || { log_error "libwasmvm.x86_64.so not found — run: make install-deps"; return 1; }
    return 0
}
