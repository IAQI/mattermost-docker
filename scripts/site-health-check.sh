#!/bin/bash

# Simple site availability check with email alerts on state transitions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$(eval echo ~${SUDO_USER:-${USER:-$(whoami)}})"
LOGS_DIR="${HOME_DIR}/logs"
LOG_FILE="${LOGS_DIR}/site-health.log"
STATE_FILE="${HOME_DIR}/.site-health.state"
ALERT_SCRIPT="${SCRIPT_DIR}/send-email-alert.py"

mkdir -p "$LOGS_DIR"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    local level="$1"
    local message="$2"
    echo "$(timestamp) [${level}] ${message}" >> "$LOG_FILE"
}

send_alert() {
    local subject="$1"
    local body="$2"

    if [[ -x "$ALERT_SCRIPT" ]] || command -v python3 >/dev/null 2>&1; then
        python3 "$ALERT_SCRIPT" --subject "$subject" --body "$body" >/dev/null 2>&1 || true
    fi
}

load_site_url() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return 0
    fi

    if [[ -f "${DOCKER_DIR}/.env" ]]; then
        # shellcheck disable=SC1090
        source "${DOCKER_DIR}/.env"
    fi

    if [[ -n "${SITE_HEALTH_URL:-}" ]]; then
        echo "$SITE_HEALTH_URL"
        return 0
    fi

    if [[ -n "${MM_SERVICESETTINGS_SITEURL:-}" ]]; then
        echo "$MM_SERVICESETTINGS_SITEURL"
        return 0
    fi

    if [[ -n "${DOMAIN:-}" ]]; then
        echo "https://${DOMAIN}"
        return 0
    fi

    echo ""
}

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "UNKNOWN"
    fi
}

write_state() {
    echo "$1" > "$STATE_FILE"
}

SITE_URL="$(load_site_url "${1:-}")"
if [[ -z "$SITE_URL" ]]; then
    log "ERROR" "No site URL configured. Set SITE_HEALTH_URL or MM_SERVICESETTINGS_SITEURL in .env."
    exit 1
fi

HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
PREV_STATE="$(read_state)"

if curl --silent --show-error --fail --max-time 20 "$SITE_URL" >/dev/null; then
    log "INFO" "Site reachable: ${SITE_URL}"

    if [[ "$PREV_STATE" == "DOWN" ]]; then
        send_alert \
            "Site recovered on ${HOSTNAME}" \
            "Site is reachable again.\n\nHost: ${HOSTNAME}\nURL: ${SITE_URL}\nTime: $(timestamp)\nLog: ${LOG_FILE}"
        log "INFO" "Recovery alert sent"
    fi

    write_state "UP"
    exit 0
fi

log "ERROR" "Site unreachable: ${SITE_URL}"
if [[ "$PREV_STATE" != "DOWN" ]]; then
    send_alert \
        "Site DOWN on ${HOSTNAME}" \
        "Site health check failed.\n\nHost: ${HOSTNAME}\nURL: ${SITE_URL}\nTime: $(timestamp)\nLog: ${LOG_FILE}"
    log "INFO" "Down alert sent"
fi

write_state "DOWN"
exit 1
