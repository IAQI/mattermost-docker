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

# Run certbot renewal
eval "$CERTBOT_CMD" 2>&1 | tee -a "$LOG_FILE"

# Check if renewal actually happened (looking for specific renewal message)
if [[ $DRY_RUN -eq 1 ]]; then
    if grep -q "Congratulations.*simulated" "$LOG_FILE"; then
        log "DRY-RUN: Would restart nginx after successful renewal"
    else
        log "DRY-RUN: No renewal would be needed"
    fi
else
    # In a real renewal, we'll see "Congratulations" without "simulated" or "no renewals were attempted"
    if grep -q "Congratulations" "$LOG_FILE" && \
       ! grep -q "simulated" "$LOG_FILE" && \
       ! grep -q "no renewals were attempted" "$LOG_FILE"; then
        log "Certificate was renewed. Restarting nginx..."
        docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart nginx >> "$LOG_FILE" 2>&1
        log "Nginx restarted successfully"
    else
        log "No renewal needed at this time"
    fi
fi

log "Certificate renewal check completed"