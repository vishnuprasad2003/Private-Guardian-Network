#!/bin/bash
# Common utilities for Private Guardian Network

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

load_config() {
    local config_file="${1:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
    [[ ! -f "$config_file" ]] && { log_error "Config not found: $config_file"; return 1; }
    source "$config_file"
    
    # Resolve paths
    KEY_FILE="${WORKSPACE_ROOT}/${KEY_FILE}"
    NODE_KEY_FILE="${WORKSPACE_ROOT}/${NODE_KEY_FILE}"
    DATA_DIR="${WORKSPACE_ROOT}/${DATA_DIR}"
    LOG_FILE="${WORKSPACE_ROOT}/${LOG_FILE}"
    ADMIN_SOCKET="${WORKSPACE_ROOT}/${ADMIN_SOCKET}"
    GRPC_SOCKET="${WORKSPACE_ROOT}/${GRPC_SOCKET}"
    PID_FILE="${WORKSPACE_ROOT}/${PID_FILE}"
    [[ "$GUARDIAND_BIN" != /* ]] && GUARDIAND_BIN="${WORKSPACE_ROOT}/${GUARDIAND_BIN}"
}

is_running() {
    local pid_file="${1:-$PID_FILE}"
    [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null && return 0
    rm -f "$pid_file" 2>/dev/null; return 1
}

validate_guardiand() {
    [[ ! -f "$GUARDIAND_BIN" ]] && { log_error "guardiand not found: $GUARDIAND_BIN"; return 1; }
    return 0
}

check_hostname() {
    [[ "${UNSAFE_DEV_MODE:-false}" != "true" ]] && return 0
    local expected="guardian-${GUARDIAN_INDEX}"
    [[ "$(hostname)" != "$expected" ]] && { log_error "Hostname must be $expected"; return 1; }
    return 0
}

create_directories() {
    mkdir -p "$(dirname "$KEY_FILE")" "$(dirname "$NODE_KEY_FILE")" "$DATA_DIR" \
             "$(dirname "$LOG_FILE")" "$(dirname "$ADMIN_SOCKET")" "$(dirname "$GRPC_SOCKET")"
}

handle_unsafe_dev_keys() {
    if [[ "${UNSAFE_DEV_MODE:-false}" == "true" ]]; then
        [[ -f "$KEY_FILE" ]] && rm -f "$KEY_FILE"
    else
        [[ ! -f "$KEY_FILE" ]] && { log_error "Key file not found: $KEY_FILE"; return 1; }
    fi
    return 0
}
