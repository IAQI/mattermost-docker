#!/bin/bash

# VS Code Server Memory Management Script
# Helps manage VS Code server processes to prevent memory issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$(eval echo ~${SUDO_USER:-$USER})"
LOGS_DIR="${HOME_DIR}/logs"
LOG_FILE="${LOGS_DIR}/vscode-manager.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    mkdir -p "$LOGS_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

show_usage() {
    echo -e "${BLUE}VS Code Server Manager${NC}"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show VS Code server memory usage"
    echo "  kill      - Kill all VS Code server processes"
    echo "  monitor   - Monitor VS Code memory usage continuously"
    echo "  alert     - Set up memory alerting for VS Code"
    echo "  clean     - Clean up orphaned VS Code processes"
    echo ""
}

check_vscode_status() {
    echo -e "${BLUE}VS Code Server Status${NC}"
    echo "======================"
    
    # Check if VS Code processes are running
    if ! pgrep -f "vscode-server" > /dev/null; then
        echo -e "${GREEN}✓ No VS Code server processes running${NC}"
        return 0
    fi
    
    # Get process details
    local total_processes=$(pgrep -f "vscode-server" | wc -l)
    local total_memory=$(ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print sum/1024}')
    local system_memory=$(free -m | grep "^Mem:" | awk '{print $2}')
    local memory_percent=$(echo "scale=1; $total_memory * 100 / $system_memory" | bc -l)
    
    echo "Processes: $total_processes"
    echo "Memory Usage: ${total_memory}MB (${memory_percent}% of system)"
    
    if (( $(echo "$memory_percent > 35" | bc -l) )); then
        echo -e "${YELLOW}⚠ WARNING: High memory usage!${NC}"
    elif (( $(echo "$memory_percent > 50" | bc -l) )); then
        echo -e "${RED}🚨 CRITICAL: Excessive memory usage!${NC}"
    else
        echo -e "${GREEN}✓ Memory usage is acceptable${NC}"
    fi
    
    echo ""
    echo "Top VS Code processes:"
    ps aux | grep -E "vscode-server" | grep -v grep | sort -k6 -nr | head -5 | awk '{printf "  PID %-8s %6.1fMB  %s\n", $2, $6/1024, $11}'
}

kill_vscode() {
    echo -e "${YELLOW}Killing VS Code server processes...${NC}"
    
    if ! pgrep -f "vscode-server" > /dev/null; then
        echo -e "${GREEN}✓ No VS Code server processes running${NC}"
        return 0
    fi
    
    local before_count=$(pgrep -f "vscode-server" | wc -l)
    local before_memory=$(ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print sum/1024}')
    
    # Kill processes gracefully
    pkill -f "vscode-server" 2>/dev/null || true
    sleep 2
    
    # Force kill if any remain
    if pgrep -f "vscode-server" > /dev/null; then
        echo "Force killing remaining processes..."
        pkill -9 -f "vscode-server" 2>/dev/null || true
        sleep 1
    fi
    
    if pgrep -f "vscode-server" > /dev/null; then
        echo -e "${RED}✗ Some processes could not be killed${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Successfully killed $before_count processes (freed ${before_memory}MB)${NC}"
        log "Killed $before_count VS Code processes, freed ${before_memory}MB memory"
    fi
}

monitor_vscode() {
    echo -e "${BLUE}Monitoring VS Code memory usage (Ctrl+C to stop)${NC}"
    echo "=================================================="
    
    while true; do
        clear
        echo "$(date)"
        echo "===================="
        
        if pgrep -f "vscode-server" > /dev/null; then
            local total_memory=$(ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print sum/1024}')
            local system_memory=$(free -m | grep "^Mem:" | awk '{print $2}')
            local memory_percent=$(echo "scale=1; $total_memory * 100 / $system_memory" | bc -l)
            
            echo "VS Code Memory: ${total_memory}MB (${memory_percent}%)"
            
            # Show overall system memory
            free -h
            echo ""
            
            # Show top processes
            echo "Top processes:"
            ps aux --sort=-%mem | head -6
        else
            echo -e "${GREEN}VS Code server not running${NC}"
        fi
        
        sleep 5
    done
}

clean_orphaned() {
    echo -e "${YELLOW}Cleaning orphaned VS Code processes...${NC}"
    
    # Look for processes that might be orphaned (running longer than 24 hours without recent activity)
    local old_processes=$(ps -eo pid,etime,cmd | grep "vscode-server" | grep -v grep | awk '$2 ~ /[0-9]+-/ {print $1}')
    
    if [ -z "$old_processes" ]; then
        echo -e "${GREEN}✓ No orphaned processes found${NC}"
        return 0
    fi
    
    echo "Found potentially orphaned processes:"
    ps -eo pid,etime,cmd | grep "vscode-server" | grep -v grep | awk '$2 ~ /[0-9]+-/ {print $1, $2, $3}'
    
    read -p "Kill these processes? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "$old_processes" | xargs kill 2>/dev/null || true
        echo -e "${GREEN}✓ Orphaned processes cleaned${NC}"
        log "Cleaned orphaned VS Code processes: $old_processes"
    else
        echo "Cancelled"
    fi
}

setup_alerts() {
    echo -e "${BLUE}Setting up VS Code memory alerts...${NC}"
    
    # Create alert script
    cat > /tmp/vscode-alert.sh << 'EOF'
#!/bin/bash
VSCODE_MEM=$(ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print sum/1024}')
TOTAL_MEM=$(free -m | grep "^Mem:" | awk '{print $2}')

if [ ! -z "$VSCODE_MEM" ] && (( $(echo "$VSCODE_MEM > 0" | bc -l) )); then
    VSCODE_PERCENT=$(echo "scale=1; $VSCODE_MEM * 100 / $TOTAL_MEM" | bc)
    if (( $(echo "$VSCODE_PERCENT > 40" | bc -l) )); then
        echo "$(date): WARNING - VS Code using ${VSCODE_MEM}MB (${VSCODE_PERCENT}% of system memory)" >> /var/log/vscode-alerts.log
        # Optionally: send notification, email, etc.
    fi
fi
EOF

    sudo mv /tmp/vscode-alert.sh /usr/local/bin/vscode-alert.sh
    sudo chmod +x /usr/local/bin/vscode-alert.sh
    
    # Add to cron if not already present
    if ! crontab -l 2>/dev/null | grep -q "vscode-alert"; then
        (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/vscode-alert.sh") | crontab -
        echo -e "${GREEN}✓ VS Code memory alerting enabled (every 10 minutes)${NC}"
        echo "Alerts will be logged to /var/log/vscode-alerts.log"
    else
        echo -e "${YELLOW}VS Code alerting already configured${NC}"
    fi
}

# Main execution
case "${1:-status}" in
    "status")
        check_vscode_status
        ;;
    "kill")
        kill_vscode
        ;;
    "monitor")
        monitor_vscode
        ;;
    "clean")
        clean_orphaned
        ;;
    "alert")
        setup_alerts
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
