#!/bin/bash

#
# Mattermost Cloud Backup Script
# 
# This script uploads Mattermost backups to SwissBackup using rclone
# - Syncs entire backup directory to cloud storage
# - Includes progress reporting and logging
# - Handles permission issues properly
#
# Usage: ./cloud-backup.sh [--dry-run] [--verbose]
# Example: ./cloud-backup.sh --verbose
#
# Created: July 23, 2025
# Target: SwissBackup (OpenStack Swift)
#

set -euo pipefail  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SOURCE_DIR="/home/ubuntu/backups"
CLOUD_REMOTE="swissbackup:mattermost-backups"
LOG_DIR="/home/ubuntu/logs"
LOG_FILE="$LOG_DIR/rclone-backup.log"
DRY_RUN=""
VERBOSE=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file only
    echo -e "${timestamp} [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE" == "--verbose" ]]; then
        case $level in
            "ERROR") echo -e "${RED}ERROR: $message${NC}" >&2 ;;
            "WARN")  echo -e "${YELLOW}WARNING: $message${NC}" ;;
            "INFO")  echo -e "${BLUE}INFO: $message${NC}" ;;
            "SUCCESS") echo -e "${GREEN}SUCCESS: $message${NC}" ;;
        esac
    fi
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    # Check if rclone is installed
    if ! command -v rclone >/dev/null 2>&1; then
        error_exit "rclone is not installed. Please install rclone first."
    fi
    
    # Check if rclone is configured for SwissBackup
    if ! rclone config show swissbackup >/dev/null 2>&1; then
        error_exit "rclone SwissBackup configuration not found. Please configure rclone first."
    fi
    
    # Check if backup source directory exists
    if [[ ! -d "$BACKUP_SOURCE_DIR" ]]; then
        error_exit "Backup source directory does not exist: $BACKUP_SOURCE_DIR"
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Create log file and set permissions
    touch "$LOG_FILE"
    chmod 664 "$LOG_FILE"
    
    log "INFO" "Prerequisites check passed"
}

# Test cloud connectivity
test_connectivity() {
    log "INFO" "Testing connectivity to SwissBackup..."
    
    # First test basic connectivity to the remote
    if rclone lsd swissbackup: >/dev/null 2>&1; then
        log "SUCCESS" "Successfully connected to SwissBackup"
        
        # Check if mattermost-backups container/directory exists, create if not
        if ! rclone lsd swissbackup:mattermost-backups >/dev/null 2>&1; then
            log "INFO" "Creating mattermost-backups directory on SwissBackup..."
            if rclone mkdir swissbackup:mattermost-backups; then
                log "SUCCESS" "Created mattermost-backups directory"
            else
                log "WARN" "Could not create mattermost-backups directory (may already exist)"
            fi
        fi
    else
        error_exit "Failed to connect to SwissBackup. Check your rclone configuration."
    fi
}

# Get backup directory sizes
get_backup_info() {
    log "INFO" "Analyzing local backups..."
    
    local total_size=$(du -sh "$BACKUP_SOURCE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    local backup_count=$(find "$BACKUP_SOURCE_DIR" -maxdepth 1 -type d -name "20*" | wc -l)
    
    log "INFO" "Total backup size: $total_size"
    log "INFO" "Number of backup sets: $backup_count"
    
    if [[ $backup_count -eq 0 ]]; then
        error_exit "No backup sets found in $BACKUP_SOURCE_DIR"
    fi
}

# Perform cloud sync
sync_to_cloud() {
    log "INFO" "Starting sync to SwissBackup..."
    
    # Build rclone command
    local rclone_cmd="rclone sync"
    
    # Add options
    rclone_cmd+=" --progress"
    rclone_cmd+=" --log-file=$LOG_FILE"
    rclone_cmd+=" --stats=30s"
    rclone_cmd+=" --transfers=4"
    rclone_cmd+=" --checkers=8"
    
    # Add dry-run if specified
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        rclone_cmd+=" --dry-run"
        log "INFO" "Running in DRY-RUN mode - no files will be transferred"
    fi
    
    # Add verbose logging if specified (use either --verbose or --log-level, not both)
    if [[ "$VERBOSE" == "--verbose" ]]; then
        rclone_cmd+=" --verbose"
    else
        rclone_cmd+=" --log-level=INFO"
    fi
    
    # Add source and destination
    rclone_cmd+=" \"$BACKUP_SOURCE_DIR\" \"$CLOUD_REMOTE\""
    
    log "INFO" "Executing: $rclone_cmd"
    
    # Execute the sync
    if eval "$rclone_cmd"; then
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            log "SUCCESS" "Dry-run completed successfully"
        else
            log "SUCCESS" "Backup sync to SwissBackup completed successfully"
        fi
    else
        error_exit "Backup sync to SwissBackup failed"
    fi
}

# Verify sync results
verify_sync() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "INFO" "Skipping verification (dry-run mode)"
        return 0
    fi
    
    log "INFO" "Verifying sync results..."
    
    # Check remote directory listing
    if rclone lsd "$CLOUD_REMOTE" >/dev/null 2>&1; then
        local remote_dirs=$(rclone lsd "$CLOUD_REMOTE" | wc -l)
        local local_dirs=$(find "$BACKUP_SOURCE_DIR" -maxdepth 1 -type d -name "20*" | wc -l)
        
        log "INFO" "Local backup sets: $local_dirs"
        log "INFO" "Remote backup sets: $remote_dirs"
        
        if [[ $remote_dirs -ge $local_dirs ]]; then
            log "SUCCESS" "Sync verification passed"
        else
            log "WARN" "Remote backup count is less than local count"
        fi
    else
        log "WARN" "Could not verify remote backup sets"
    fi
}

# Generate sync report
generate_report() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="$LOG_DIR/cloud-backup-report-$timestamp.txt"
    
    cat > "$report_file" << EOF
Mattermost Cloud Backup Report
==============================
Sync Date: $(date)
Source Directory: $BACKUP_SOURCE_DIR
Cloud Remote: $CLOUD_REMOTE
Mode: $(if [[ "$DRY_RUN" == "--dry-run" ]]; then echo "DRY-RUN"; else echo "LIVE SYNC"; fi)

Local Backup Summary:
$(ls -la "$BACKUP_SOURCE_DIR" | grep "^d" | grep "20" || echo "No timestamped backups found")

Total Local Size: $(du -sh "$BACKUP_SOURCE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")

Cloud Storage Info:
$(rclone about "$CLOUD_REMOTE" 2>/dev/null || echo "Could not retrieve cloud storage info")

Sync Status: $(if [[ "$DRY_RUN" == "--dry-run" ]]; then echo "DRY-RUN COMPLETED"; else echo "SYNC COMPLETED"; fi)
EOF

    log "INFO" "Sync report generated: $report_file"
}

# Main function
main() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    log "INFO" "Starting cloud backup process - Timestamp: $timestamp"
    
    # Run checks
    check_prerequisites
    test_connectivity
    get_backup_info
    
    # Perform sync
    sync_to_cloud
    
    # Verify and report
    verify_sync
    generate_report
    
    log "SUCCESS" "Cloud backup process completed"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [--dry-run] [--verbose]

Options:
  --dry-run         Show what would be transferred without actually doing it
  --verbose         Enable verbose output and logging

Examples:
  $0                    # Normal sync to cloud
  $0 --dry-run          # Test run without transferring files
  $0 --verbose          # Sync with detailed output
  $0 --dry-run --verbose # Test run with detailed output

Description:
  Syncs Mattermost backups to SwissBackup cloud storage using rclone.
  
  Source: $BACKUP_SOURCE_DIR
  Target: $CLOUD_REMOTE
  Logs:   $LOG_FILE
  
Requirements:
  - rclone must be installed and configured for SwissBackup
  - Local backups must exist in $BACKUP_SOURCE_DIR
  
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --verbose)
            VERBOSE="--verbose"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
