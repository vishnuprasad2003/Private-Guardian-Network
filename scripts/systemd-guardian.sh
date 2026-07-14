#!/bin/bash
# systemd foreground launcher for one guardian (UTS hostname = guardian-N).
# See README "Systemd Services". Usage: ./scripts/systemd-guardian.sh <config-file>
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:?Usage: $0 <config-file>}"
load_config "$CONFIG"

GUARDIAN="${GUARDIAN_NAME:?GUARDIAN_NAME not set in config}"
UTS_MODE="${UTS_MODE:-cap}"
run_guardian=(env RUN_FOREGROUND=1 "${WORKSPACE_ROOT}/scripts/start-guardian.sh" "$CONFIG")

case "$UTS_MODE" in
    none)
        log_info "UTS_MODE=none — host hostname=$(hostname)"
        exec "${run_guardian[@]}"
        ;;
    userns)
        command_exists unshare || { log_error "unshare not found"; exit 1; }
        log_info "Starting ${GUARDIAN} in UTS+user namespace"
        exec unshare --uts --user --map-root-user -- \
            bash -c 'hostname "$1"; shift; exec "$@"' _ "$GUARDIAN" "${run_guardian[@]}"
        ;;
    cap|*)
        command_exists unshare || { log_error "unshare not found"; exit 1; }
        log_info "Starting ${GUARDIAN} in UTS namespace (hostname=${GUARDIAN})"
        exec unshare --uts -- \
            bash -c 'hostname "$1"; shift; exec "$@"' _ "$GUARDIAN" "${run_guardian[@]}"
        ;;
esac
