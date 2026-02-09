#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Upgrade the guardian binary and dependencies
# Usage: ./scripts/upgrade.sh <all|check|backup|update|verify|rollback|status>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${WORKSPACE_ROOT}/configs/guardian-0.conf"
[[ -f "$CONFIG" ]] && load_config "$CONFIG"

WORMHOLE_REPO="${WORKSPACE_ROOT}/../wormhole"
BACKUP_DIR="${BASE_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ─── Helpers ────────────────────────────────────────────────────────────────
get_version() { [[ -f "$GUARDIAND_BIN" ]] && "$GUARDIAND_BIN" version 2>/dev/null | head -1 || echo "unknown"; }

stop_all() {
    for i in 0 1 2; do
        local pf="${BASE_DIR}/pids/guardian-${i}.pid"
        is_running "$pf" && graceful_stop "$pf" "guardian-${i}" 10
    done
    local apf="${BASE_DIR}/pids/anvil.pid"
    is_running "$apf" && graceful_stop "$apf" "Anvil" 5
}

# ─── Backup ─────────────────────────────────────────────────────────────────
create_backup() {
    log_info "Creating backup..."
    local path="${BACKUP_DIR}/${TIMESTAMP}"
    mkdir -p "$path"
    [[ -f "$GUARDIAND_BIN" ]] && cp "$GUARDIAND_BIN" "${path}/guardiand.backup"
    [[ -d "${WORKSPACE_ROOT}/configs" ]] && cp -r "${WORKSPACE_ROOT}/configs" "${path}/"
    [[ -d "${BASE_DIR}/keys" ]] && cp -r "${BASE_DIR}/keys" "${path}/"
    cat > "${path}/versions.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "guardiand": "$(get_version)",
  "go":        "$(go version 2>/dev/null | grep -oP 'go\d+\.\d+\.\d+' || echo 'n/a')",
  "foundry":   "$(anvil --version 2>/dev/null | head -1 || echo 'n/a')",
  "commit":    "$(cd "$WORMHOLE_REPO" 2>/dev/null && git rev-parse --short HEAD || echo 'n/a')"
}
EOF
    log_success "Backup → ${path}"
    # Keep last 5 backups
    local count; count=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if (( count > 5 )); then
        find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort | head -$((count-5)) | xargs rm -rf
        log_info "Cleaned old backups (kept 5)"
    fi
}

# ─── Update ─────────────────────────────────────────────────────────────────
do_update() {
    [[ -d "$WORMHOLE_REPO" ]] || { log_error "Repo not found: $WORMHOLE_REPO"; exit 1; }
    cd "$WORMHOLE_REPO"
    local current; current=$(git rev-parse HEAD)
    git fetch --all --tags
    local branch; branch=$(git remote show origin | awk '/HEAD branch/{print $NF}')
    local latest; latest=$(git rev-parse "origin/${branch}")
    if [[ "$current" == "$latest" ]]; then
        log_info "Already up to date (${current:0:8})"; return 0
    fi
    log_info "Updating ${current:0:8} → ${latest:0:8}"
    git pull origin "$branch"
    mkdir -p "${WORMHOLE_REPO}/build/bin"
    (cd node && go build -o "${WORMHOLE_REPO}/build/bin/guardiand" .)
    chmod +x "${WORMHOLE_REPO}/build/bin/guardiand"
    log_success "Built: $(get_version)"
    cd "$WORKSPACE_ROOT"
}

# ─── Verify ─────────────────────────────────────────────────────────────────
do_verify() {
    local ok=0
    if [[ -f "$GUARDIAND_BIN" ]] && "$GUARDIAND_BIN" version &>/dev/null; then
        log_success "guardiand OK — $(get_version)"
    else
        log_error "guardiand binary broken"; ok=1
    fi
    for conf in "${WORKSPACE_ROOT}/configs/"*.conf; do
        bash -n "$conf" 2>/dev/null && log_success "Config OK: $(basename "$conf")" || { log_error "Invalid: $(basename "$conf")"; ok=1; }
    done
    if [[ -f "$GUARDIAND_BIN" ]] && ldd "$GUARDIAND_BIN" 2>/dev/null | grep -q "not found"; then
        log_error "Missing shared libraries"; ldd "$GUARDIAND_BIN" | grep "not found"; ok=1
    else
        log_success "Shared libraries OK"
    fi
    return $ok
}

# ─── Rollback ───────────────────────────────────────────────────────────────
do_rollback() {
    local path="${1:?backup path required}"
    [[ -d "$path" ]] || { log_error "Not found: $path"; exit 1; }
    stop_all
    [[ -f "${path}/guardiand.backup" ]] && { cp "${path}/guardiand.backup" "$GUARDIAND_BIN"; chmod +x "$GUARDIAND_BIN"; }
    [[ -d "${path}/configs" ]] && cp -r "${path}/configs/"* "${WORKSPACE_ROOT}/configs/"
    log_success "Rolled back to: $(basename "$path")"
}

# ─── Status ─────────────────────────────────────────────────────────────────
show_status() {
    echo ""
    echo "  Guardian:  $(get_version)"
    echo "  Go:        $(go version 2>/dev/null | grep -oP 'go\d+\.\d+\.\d+' || echo 'n/a')"
    echo "  Foundry:   $(anvil --version 2>/dev/null | head -1 || echo 'n/a')"
    echo "  Solana:    $(solana --version 2>/dev/null | head -1 || echo 'n/a')"
    echo "  grpcurl:   $(grpcurl --version 2>/dev/null | head -1 || echo 'n/a')"
    echo ""
    for i in 0 1 2; do
        local pf="${BASE_DIR}/pids/guardian-${i}.pid"
        is_running "$pf" && echo "  guardian-${i}: running (PID $(cat "$pf"))" || echo "  guardian-${i}: stopped"
    done
    local apf="${BASE_DIR}/pids/anvil.pid"
    is_running "$apf" && echo "  Anvil:      running (PID $(cat "$apf"))" || echo "  Anvil:      stopped"
    echo ""
    echo "  Backups: $(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    echo "  Storage: $(du -sh "$BASE_DIR" 2>/dev/null | cut -f1)"
}

# ─── Main ───────────────────────────────────────────────────────────────────
CMD="${1:-help}"; shift || true
case "$CMD" in
    all)      stop_all; create_backup; do_update; do_verify; log_success "Upgrade complete" ;;
    check)    cd "$WORMHOLE_REPO" && git fetch --all --tags && git log --oneline HEAD..origin/$(git remote show origin | awk '/HEAD branch/{print $NF}') | head -10 ;;
    backup)   create_backup ;;
    update)   stop_all; do_update ;;
    verify)   do_verify ;;
    rollback) do_rollback "${1:-}" ;;
    status)   show_status ;;
    *)
        echo "Usage: $0 <all|check|backup|update|verify|rollback <path>|status>"
        exit 1 ;;
esac
