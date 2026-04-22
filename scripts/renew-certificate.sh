#!/bin/bash

# Script to renew Let's Encrypt certificate and reload nginx if renewed
# Location: /home/ubuntu/docker/scripts/renew-certificate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/home/ubuntu/logs/certbot-renewal.log"

# Parse command line arguments
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "Running in dry-run mode"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_cert_path() {
    local env_file="$DOCKER_DIR/.env"
    local domain=""

    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        domain="$(awk -F= '/^DOMAIN=/{print $2}' "$env_file" | tail -n 1 | tr -d '[:space:]')"
    fi

    if [[ -n "$domain" && -f "$DOCKER_DIR/certs/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        echo "$DOCKER_DIR/certs/etc/letsencrypt/live/$domain/fullchain.pem"
        return 0
    fi

    # Fallback to first available certificate lineage.
    find "$DOCKER_DIR/certs/etc/letsencrypt/live" -mindepth 2 -maxdepth 2 -name fullchain.pem | sort | head -n 1
}

cert_fingerprint() {
    local cert_path="$1"
    if [[ -z "$cert_path" || ! -f "$cert_path" ]]; then
        return 0
    fi

    openssl x509 -in "$cert_path" -noout -fingerprint -sha256 | cut -d= -f2
}

cd "$DOCKER_DIR"

log "Starting certificate renewal check..."

# Build certbot command
CERTBOT_CMD="docker run --rm --name certbot \
    --network mattermost \
    -v "${DOCKER_DIR}/certs/etc/letsencrypt:/etc/letsencrypt" \
    -v "${DOCKER_DIR}/certs/lib/letsencrypt:/var/lib/letsencrypt" \
    -v shared-webroot:/usr/share/nginx/html \
    certbot/certbot renew --verbose --webroot --webroot-path=/usr/share/nginx/html"

# Add dry-run flag if specified
if [[ $DRY_RUN -eq 1 ]]; then
    CERTBOT_CMD="$CERTBOT_CMD --dry-run"
fi

CERT_PATH="$(get_cert_path || true)"
BEFORE_FP="$(cert_fingerprint "$CERT_PATH" || true)"

if [[ -n "$CERT_PATH" ]]; then
    log "Tracking certificate fingerprint at: $CERT_PATH"
fi

RUN_LOG="$(mktemp)"
trap 'rm -f "$RUN_LOG"' EXIT

# Run certbot renewal and capture only this run's output for decisions.
eval "$CERTBOT_CMD" 2>&1 | tee -a "$LOG_FILE" | tee "$RUN_LOG"

AFTER_FP="$(cert_fingerprint "$CERT_PATH" || true)"

# Check if renewal actually happened (looking for specific renewal message)
if [[ $DRY_RUN -eq 1 ]]; then
    if grep -q "Congratulations.*simulated" "$RUN_LOG"; then
        log "DRY-RUN: Would restart nginx after successful renewal"
    else
        log "DRY-RUN: No renewal would be needed"
    fi
else
    # Primary signal: certificate fingerprint changed.
    if [[ -n "$AFTER_FP" && "$BEFORE_FP" != "$AFTER_FP" ]]; then
        log "Certificate fingerprint changed. Restarting nginx to load the renewed certificate..."
        docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart nginx >> "$LOG_FILE" 2>&1
        log "Nginx restarted successfully"
    # Fallback signal: certbot reports a real renewal in this run.
    elif grep -q "Congratulations" "$RUN_LOG" && \
         ! grep -q "simulated" "$RUN_LOG" && \
         ! grep -q "no renewals were attempted" "$RUN_LOG"; then
        log "Certificate was renewed. Restarting nginx..."
        docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart nginx >> "$LOG_FILE" 2>&1
        log "Nginx restarted successfully"
    else
        log "No renewal needed at this time"
    fi
fi

log "Certificate renewal check completed"