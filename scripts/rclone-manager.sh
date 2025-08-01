#!/bin/bash

#
# Rclone Backup Manager Script
# 
# This script provides easy management of cloud backups via rclone:
# - List backups on cloud storage
# - Show backup ages and retention status
# - Manually clean up old backups
# - Check cloud storage usage
# - Test cloud connectivity
#
# Usage: ./rclone-manager.sh [command] [options]
#
# Created: July 26, 2025
# Target: SwissBackup cloud storage via rclone
#

set -euo pipefail

# But allow some commands to fail gracefully
set +e

# Configuration
CLOUD_REMOTE="swissbackup:mattermost-backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output (only if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [[ $(tput colors) -ge 8 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    # No color support
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Helper functions
print_header() {
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' {1..60})${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Check if rclone is available and configured
check_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        print_error "rclone not found. Please install rclone first."
        exit 1
    fi
    
    if ! rclone config show swissbackup >/dev/null 2>&1; then
        print_error "rclone SwissBackup configuration not found."
        echo "Run 'rclone config' to set up your SwissBackup connection first."
        exit 1
    fi
    
    print_success "rclone is available and configured"
}

# Test cloud connectivity
test_connection() {
    print_header "Testing Cloud Connection"
    
    if rclone lsd "$CLOUD_REMOTE" >/dev/null 2>&1; then
        print_success "Successfully connected to $CLOUD_REMOTE"
        return 0
    else
        print_error "Failed to connect to $CLOUD_REMOTE"
        return 1
    fi
}

# Calculate backup age in days
calculate_age_days() {
    local backup_date="$1"
    local current_date=$(date +%s)
    local backup_timestamp
    
    # Extract date from backup directory name (format: YYYYMMDD_HHMMSS)
    local date_part="${backup_date:0:8}"
    local time_part="${backup_date:9:6}"
    
    # Convert to timestamp
    backup_timestamp=$(date -d "${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}" +%s 2>/dev/null || echo "0")
    
    if [[ "$backup_timestamp" == "0" ]]; then
        echo "unknown"
    else
        local age_seconds=$((current_date - backup_timestamp))
        local age_days=$((age_seconds / 86400))
        echo "$age_days"
    fi
}

# Get backup retention status
get_retention_status() {
    local backup_path="$1"
    local backup_name="$2"
    local age_days="$3"
    
    # Determine backup type based on directory structure
    if [[ "$backup_path" == *"/daily/"* ]]; then
        # Daily backup (7 days retention)
        if [[ "$age_days" != "unknown" && "$age_days" -lt 7 ]]; then
            echo -e "${GREEN}Daily (${age_days}d/7d)${NC}"
        elif [[ "$age_days" != "unknown" && "$age_days" -ge 7 ]]; then
            echo -e "${RED}Daily (${age_days}d/7d) - EXPIRED${NC}"
        else
            echo -e "${YELLOW}Daily (?d/7d)${NC}"
        fi
    elif [[ "$backup_path" == *"/weekly/"* ]]; then
        # Weekly backup (28 days retention)
        if [[ "$age_days" != "unknown" && "$age_days" -lt 28 ]]; then
            echo -e "${GREEN}Weekly (${age_days}d/28d)${NC}"
        elif [[ "$age_days" != "unknown" && "$age_days" -ge 28 ]]; then
            echo -e "${RED}Weekly (${age_days}d/28d) - EXPIRED${NC}"
        else
            echo -e "${YELLOW}Weekly (?d/28d)${NC}"
        fi
    else
        # Unknown type - legacy backup perhaps
        echo -e "${YELLOW}Unknown${NC}"
    fi
}

# List all backups on cloud storage
list_backups() {
    print_header "Cloud Backup Listing"
    
    print_info "Fetching backup list from $CLOUD_REMOTE..."
    
    # Get list of backup directories from both daily and weekly folders
    local daily_backups weekly_backups
    daily_backups=$(rclone lsf "$CLOUD_REMOTE/daily/" --dirs-only 2>/dev/null || echo "")
    weekly_backups=$(rclone lsf "$CLOUD_REMOTE/weekly/" --dirs-only 2>/dev/null || echo "")
    
    # Check if we have any backups
    if [[ -z "$daily_backups" && -z "$weekly_backups" ]]; then
        # Try legacy format (flat structure) for backwards compatibility
        local legacy_backups
        if legacy_backups=$(rclone lsf "$CLOUD_REMOTE" --dirs-only 2>/dev/null); then
            if [[ -n "$legacy_backups" ]]; then
                print_warning "Found legacy backup structure (flat directories)"
                echo
                printf "%-25s %-12s %-8s %-25s %s\n" "Backup Name" "Age (days)" "Size" "Retention Status" "Created"
                echo "$(printf '%.0s-' {1..95})"
                
                local total_backups=0
                while IFS= read -r backup_dir; do
                    if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]]; then
                        list_single_backup "" "${backup_dir%/}"
                        ((total_backups++))
                    fi
                done <<< "$legacy_backups"
                
                echo
                print_info "Total legacy backups: $total_backups"
                return 0
            fi
        fi
        
        print_warning "No backups found on cloud storage"
        return 0
    fi
    
    echo
    printf "%-10s %-20s %-12s %-8s %-25s %s\n" "Type" "Backup Name" "Age (days)" "Size" "Retention Status" "Created"
    echo "$(printf '%.0s-' {1..100})"
    
    local total_backups=0
    local total_size=0
    
    # List daily backups
    if [[ -n "$daily_backups" ]]; then
        while IFS= read -r backup_dir; do
            if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]]; then
                list_single_backup "daily" "${backup_dir%/}"
                ((total_backups++))
            fi
        done <<< "$daily_backups"
    fi
    
    # List weekly backups
    if [[ -n "$weekly_backups" ]]; then
        while IFS= read -r backup_dir; do
            if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]]; then
                list_single_backup "weekly" "${backup_dir%/}"
                ((total_backups++))
            fi
        done <<< "$weekly_backups"
    fi
    
    echo
    print_info "Total backups: $total_backups"
}

# Helper function to list a single backup
list_single_backup() {
    local backup_type="$1"
    local backup_name="$2"
    local backup_path
    
    if [[ -n "$backup_type" ]]; then
        backup_path="$CLOUD_REMOTE/$backup_type/$backup_name"
    else
        backup_path="$CLOUD_REMOTE/$backup_name"
    fi
    
    local age_days=$(calculate_age_days "$backup_name")
    local retention_status=$(get_retention_status "$backup_path" "$backup_name" "$age_days")
    
    # Get backup size
    local size_human="..."
    if size_info=$(rclone size "$backup_path" 2>/dev/null); then
        local size_bytes=$(echo "$size_info" | grep "Total size:" | awk '{print $3}' | tr -d ',')
        if [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
            size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
        else
            size_human="unknown"
        fi
    else
        size_human="unknown"
    fi
    
    # Format creation date
    local date_part="${backup_name:0:8}"
    local time_part="${backup_name:9:6}"
    local created_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}"
    
    if [[ -n "$backup_type" ]]; then
        printf "%-10s %-20s %-12s %-8s %-35s %s\n" \
            "$backup_type" \
            "$backup_name" \
            "$age_days" \
            "$size_human" \
            "$retention_status" \
            "$created_date"
    else
        printf "%-25s %-12s %-8s %-25s %s\n" \
            "$backup_name" \
            "$age_days" \
            "$size_human" \
            "$retention_status" \
            "$created_date"
    fi
}

# Show cloud storage usage
show_usage() {
    print_header "Cloud Storage Usage"
    
    print_info "Calculating storage usage..."
    
    if ! rclone size "$CLOUD_REMOTE" 2>/dev/null; then
        print_error "Failed to get storage usage information"
        return 1
    fi
}

# Clean up expired backups manually
cleanup_expired() {
    print_header "Manual Cleanup of Expired Backups"
    
    print_warning "This will delete expired backups from cloud storage!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        return 0
    fi
    
    print_info "Scanning for expired backups..."
    
    local deleted_count=0
    
    # Check daily backups (7d retention)
    print_info "Checking daily backups for expiration (7+ days)..."
    local daily_backups
    if daily_backups=$(rclone lsf "$CLOUD_REMOTE/daily/" --dirs-only 2>/dev/null); then
        while IFS= read -r backup_dir; do
            if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]]; then
                local backup_name="${backup_dir%/}"
                local age_days=$(calculate_age_days "$backup_name")
                
                if [[ "$age_days" != "unknown" && "$age_days" -ge 7 ]]; then
                    print_warning "Daily backup $backup_name is expired (${age_days} days old)"
                    if rclone purge "$CLOUD_REMOTE/daily/$backup_dir"; then
                        print_success "Deleted expired daily backup: $backup_name"
                        ((deleted_count++))
                    else
                        print_error "Failed to delete daily backup: $backup_name"
                    fi
                fi
            fi
        done <<< "$daily_backups"
    fi
    
    # Check weekly backups (28d retention)
    print_info "Checking weekly backups for expiration (28+ days)..."
    local weekly_backups
    if weekly_backups=$(rclone lsf "$CLOUD_REMOTE/weekly/" --dirs-only 2>/dev/null); then
        while IFS= read -r backup_dir; do
            if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]]; then
                local backup_name="${backup_dir%/}"
                local age_days=$(calculate_age_days "$backup_name")
                
                if [[ "$age_days" != "unknown" && "$age_days" -ge 28 ]]; then
                    print_warning "Weekly backup $backup_name is expired (${age_days} days old)"
                    if rclone purge "$CLOUD_REMOTE/weekly/$backup_dir"; then
                        print_success "Deleted expired weekly backup: $backup_name"
                        ((deleted_count++))
                    else
                        print_error "Failed to delete weekly backup: $backup_name"
                    fi
                fi
            fi
        done <<< "$weekly_backups"
    fi
    
    # Check for legacy backups (flat structure) - clean up with old logic
    print_info "Checking for legacy backups (flat structure)..."
    local legacy_backups
    if legacy_backups=$(rclone lsf "$CLOUD_REMOTE" --dirs-only 2>/dev/null); then
        while IFS= read -r backup_dir; do
            if [[ "$backup_dir" =~ ^20[0-9]{6}_[0-9]{6}/$ ]] && [[ "$backup_dir" != "daily/" ]] && [[ "$backup_dir" != "weekly/" ]]; then
                local backup_name="${backup_dir%/}"
                local age_days=$(calculate_age_days "$backup_name")
                
                if [[ "$age_days" != "unknown" ]]; then
                    # Determine if this legacy backup is expired using old logic
                    local date_part="${backup_name:0:8}"
                    local backup_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2}"
                    local day_of_week=$(date -d "$backup_date" +%u 2>/dev/null || echo "0")
                    local is_expired=false
                    
                    if [[ "$day_of_week" == "7" && "$age_days" -ge 28 ]]; then
                        is_expired=true
                        print_warning "Legacy weekly backup $backup_name is expired (${age_days} days old)"
                    elif [[ "$day_of_week" != "7" && "$age_days" -ge 7 ]]; then
                        is_expired=true
                        print_warning "Legacy daily backup $backup_name is expired (${age_days} days old)"
                    fi
                    
                    if [[ "$is_expired" == "true" ]]; then
                        if rclone purge "$CLOUD_REMOTE/$backup_dir"; then
                            print_success "Deleted expired legacy backup: $backup_name"
                            ((deleted_count++))
                        else
                            print_error "Failed to delete legacy backup: $backup_name"
                        fi
                    fi
                fi
            fi
        done <<< "$legacy_backups"
    fi
    
    if [[ "$deleted_count" -eq 0 ]]; then
        print_success "No expired backups found"
    else
        print_success "Deleted $deleted_count expired backups"
    fi
}

# Show detailed backup information
show_details() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        print_error "Please specify a backup name"
        echo "Usage: $0 details <backup_name>"
        echo "       $0 details daily/<backup_name>"
        echo "       $0 details weekly/<backup_name>"
        return 1
    fi
    
    print_header "Backup Details: $backup_name"
    
    local backup_path backup_type
    
    # Check if backup_name includes type prefix
    if [[ "$backup_name" == daily/* ]]; then
        backup_type="daily"
        backup_name="${backup_name#daily/}"
        backup_path="$CLOUD_REMOTE/daily/$backup_name"
    elif [[ "$backup_name" == weekly/* ]]; then
        backup_type="weekly"
        backup_name="${backup_name#weekly/}"
        backup_path="$CLOUD_REMOTE/weekly/$backup_name"
    else
        # Try to find the backup in either directory
        if rclone lsf "$CLOUD_REMOTE/daily/$backup_name" >/dev/null 2>&1; then
            backup_type="daily"
            backup_path="$CLOUD_REMOTE/daily/$backup_name"
        elif rclone lsf "$CLOUD_REMOTE/weekly/$backup_name" >/dev/null 2>&1; then
            backup_type="weekly"
            backup_path="$CLOUD_REMOTE/weekly/$backup_name"
        elif rclone lsf "$CLOUD_REMOTE/$backup_name" >/dev/null 2>&1; then
            # Legacy backup (flat structure)
            backup_type="legacy"
            backup_path="$CLOUD_REMOTE/$backup_name"
        else
            print_error "Backup '$backup_name' not found in daily/, weekly/, or root directory"
            return 1
        fi
    fi
    
    print_info "Backup type: $backup_type"
    print_info "Backup location: $backup_path"
    
    local age_days=$(calculate_age_days "$backup_name")
    local retention_status=$(get_retention_status "$backup_path" "$backup_name" "$age_days")
    
    echo "Age: $age_days days"
    echo -e "Retention: $retention_status"
    echo
    
    print_info "Backup contents:"
    rclone lsf "$backup_path" --dirs-only || print_warning "Could not list backup contents"
    
    echo
    print_info "Backup size breakdown:"
    rclone size "$backup_path"
}

# Show usage information
usage() {
    cat << EOF
Rclone Backup Manager

Usage: $0 <command> [options]

Commands:
  list              List all backups on cloud storage with retention info
  usage             Show cloud storage usage statistics
  test              Test connection to cloud storage
  cleanup           Manually clean up expired backups
  details <name>    Show detailed information about a specific backup
                    Use: details <backup_name>
                         details daily/<backup_name>
                         details weekly/<backup_name>
  help              Show this help message

Examples:
  $0 list                    # List all cloud backups
  $0 usage                   # Show storage usage
  $0 test                    # Test cloud connection
  $0 cleanup                 # Clean up expired backups
  $0 details 20250726_080533     # Show details for specific backup (auto-detect type)
  $0 details daily/20250726_080533   # Show details for daily backup
  $0 details weekly/20250804_080533  # Show details for weekly backup

Backup Structure:
  - Daily backups stored in: $CLOUD_REMOTE/daily/
  - Weekly backups stored in: $CLOUD_REMOTE/weekly/
  - Legacy backups may exist in root directory (flat structure)

Retention Policy:
  - Daily backups (Mon-Sat): Kept for 7 days
  - Weekly backups (Sunday): Kept for 28 days
  - Expired backups are marked in red

Cloud Remote: $CLOUD_REMOTE

EOF
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "list"|"ls")
            check_rclone
            test_connection
            echo
            list_backups
            ;;
        "usage"|"size")
            check_rclone
            test_connection
            echo
            show_usage
            ;;
        "test"|"check")
            check_rclone
            test_connection
            ;;
        "cleanup"|"clean")
            check_rclone
            test_connection
            echo
            cleanup_expired
            ;;
        "details"|"detail"|"info")
            check_rclone
            test_connection
            echo
            show_details "${2:-}"
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
