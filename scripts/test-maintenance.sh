#!/bin/bash

#
# Maintenance Mode Test Script
# 
# This script allows manual testing of the maintenance mode functionality
#
# Usage: 
#   ./test-maintenance.sh enable   # Enable maintenance mode
#   ./test-maintenance.sh disable  # Disable maintenance mode
#   ./test-maintenance.sh status   # Check maintenance mode status
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
MAINTENANCE_FLAG="$DOCKER_DIR/nginx/conf.d/.maintenance"

case "${1:-status}" in
    enable)
        echo "Enabling maintenance mode..."
        touch "$MAINTENANCE_FLAG"
        echo "✅ Maintenance mode enabled"
        echo "💡 Visit your Mattermost URL to see the maintenance page"
        ;;
    disable)
        echo "Disabling maintenance mode..."
        rm -f "$MAINTENANCE_FLAG"
        echo "✅ Maintenance mode disabled"
        echo "💡 Mattermost should now be accessible normally"
        ;;
    status)
        if [[ -f "$MAINTENANCE_FLAG" ]]; then
            echo "🔧 Maintenance mode is ENABLED"
            echo "   Flag file: $MAINTENANCE_FLAG"
            echo "   Created: $(stat -c %y "$MAINTENANCE_FLAG" 2>/dev/null || echo "unknown")"
        else
            echo "✅ Maintenance mode is DISABLED"
            echo "   Mattermost should be accessible normally"
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        echo ""
        echo "Commands:"
        echo "  enable   - Enable maintenance mode (show maintenance page)"
        echo "  disable  - Disable maintenance mode (restore normal access)"
        echo "  status   - Check current maintenance mode status"
        exit 1
        ;;
esac
