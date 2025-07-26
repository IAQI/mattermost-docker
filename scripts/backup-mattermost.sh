#!/bin/bash

#
# Mattermost Docker Backup Script
# 
# This script creates comprehensive backups of:
# - PostgreSQL database (full dump)
# - Mattermost data files and uploads
# - Configuration files and certificates
#
# Usage: ./backup-mattermost.sh [--verbose]
# Example: ./backup-mattermost.sh --verbose
#
# Created: July 22, 2025
# Target: Mattermost 10.5.2 Enterprise Edition
#

set -euo pipefail  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$(eval echo ~${SUDO_USER:-$USER})"  # Get actual user's home even when using sudo
BACKUP_BASE_DIR="${HOME_DIR}/backups"
LOGS_DIR="${HOME_DIR}/logs"
LOG_FILE="${LOGS_DIR}/mattermost-backup.log"
VERBOSE=""
ALLOW_ROOT=""

# Cloud backup settings
CLOUD_REMOTE="swissbackup:mattermost-backups"

# Docker compose files
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.nginx.yml"

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
    
    # Ensure logs directory exists
    mkdir -p "$LOGS_DIR"
    
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
    
    # Attempt to restart services if they were stopped
    if [[ "${SERVICES_STOPPED:-false}" == "true" ]]; then
        log "INFO" "Attempting to restart services due to error..."
        restart_services || log "ERROR" "Failed to restart services after error"
    fi
    
    exit 1
}

# Cleanup function
cleanup() {
    log "INFO" "Performing cleanup..."
    
    # Remove temporary files if any were created
    if [[ -n "${TEMP_FILES:-}" ]]; then
        rm -f $TEMP_FILES 2>/dev/null || true
    fi
    
    # Ensure services are running
    if [[ "${SERVICES_STOPPED:-false}" == "true" ]]; then
        restart_services || log "ERROR" "Failed to restart services during cleanup"
    fi
}

# Set trap for cleanup
trap cleanup EXIT
trap 'error_exit "Script interrupted"' INT TERM

# Helper function to run docker commands with or without sudo
docker_cmd() {
    if [[ $EUID -eq 0 ]]; then
        # Running as root, no need for sudo
        docker "$@"
    else
        # Running as regular user, use sudo
        sudo docker "$@"
    fi
}

# Helper function to run tar commands with or without sudo
tar_cmd() {
    if [[ $EUID -eq 0 ]]; then
        # Running as root, no need for sudo
        tar "$@"
    else
        # Running as regular user, use sudo
        sudo tar "$@"
    fi
}
check_permissions() {
    if [[ $EUID -eq 0 ]] && [[ "$ALLOW_ROOT" != "--allow-root" ]]; then
        error_exit "This script should not be run as root. Run as the ubuntu user, or use --allow-root flag to override."
    fi
    
    if [[ $EUID -eq 0 ]] && [[ "$ALLOW_ROOT" == "--allow-root" ]]; then
        log "WARN" "Running as root (explicitly allowed with --allow-root flag)"
    fi
    
    # Check if user can run docker commands
    if ! docker ps >/dev/null 2>&1 && ! sudo -n docker ps >/dev/null 2>&1; then
        # If we're root, we don't need sudo, so only check docker directly
        if [[ $EUID -eq 0 ]]; then
            if ! docker ps >/dev/null 2>&1; then
                error_exit "Cannot run docker commands as root."
            fi
        else
            error_exit "Cannot run docker commands. Please ensure user is in docker group or has sudo access."
        fi
    fi
}

# Check disk space
check_disk_space() {
    local required_space_gb=2  # Minimum 2GB free space
    local available_space=$(df "$HOME_DIR" | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_gb -lt $required_space_gb ]]; then
        error_exit "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_gb}GB"
    fi
    
    log "INFO" "Disk space check passed. Available: ${available_gb}GB"
}

# Check if services are running
check_services() {
    cd "$DOCKER_DIR"
    
    # Check if all required services are running
    local running_services=$(docker_cmd compose $COMPOSE_FILES ps --services --filter "status=running")
    
    if ! echo "$running_services" | grep -q "mattermost"; then
        error_exit "Mattermost service is not running. Start services first."
    fi
    
    if ! echo "$running_services" | grep -q "postgres"; then
        error_exit "PostgreSQL service is not running. Start services first."
    fi
    
    if ! echo "$running_services" | grep -q "nginx"; then
        error_exit "Nginx service is not running. Start services first."
    fi
    
    # Check if PostgreSQL is ready to accept connections
    if ! docker_cmd exec docker-postgres-1 pg_isready -U mmuser >/dev/null 2>&1; then
        error_exit "PostgreSQL database is not ready"
    fi
    
    log "INFO" "Service health check passed"
}

# Create backup directories
create_backup_dirs() {
    local timestamp="$1"
    
    # Create timestamped backup directory
    BACKUP_DIR="$BACKUP_BASE_DIR/$timestamp"
    
    mkdir -p "$BACKUP_DIR"/{database,data,config}
    
    # Create base backup directory if it doesn't exist
    mkdir -p "$BACKUP_BASE_DIR"
    
    log "INFO" "Created backup directories: $BACKUP_DIR"
}

# Stop Mattermost services (keep database running)
stop_services() {
    cd "$DOCKER_DIR"
    
    log "INFO" "Stopping Mattermost and nginx services..."
    
        if docker_cmd compose $COMPOSE_FILES stop mattermost nginx; then
        SERVICES_STOPPED=true
        log "SUCCESS" "Services stopped successfully"
        
        # Wait a moment for services to fully stop
        sleep 5
        
        # Verify only postgres is running
        if docker_cmd compose $COMPOSE_FILES ps | grep -E "(mattermost|nginx)" | grep -q "Up"; then
            error_exit "Failed to stop all required services"
        fi
    else
        error_exit "Failed to stop services"
    fi
}

# Restart all services
restart_services() {
    cd "$DOCKER_DIR"
    
    log "INFO" "Starting all services..."
    
    if docker_cmd compose $COMPOSE_FILES up -d; then
        SERVICES_STOPPED=false
        log "SUCCESS" "All services started successfully"
        
        # Wait for services to be ready
        sleep 10
        
        # Verify services are running
        local retries=0
        while [[ $retries -lt 30 ]]; do
            if docker_cmd compose $COMPOSE_FILES ps | grep -E "(mattermost|nginx|postgres)" | grep -c "Up" | grep -q "3"; then
                log "SUCCESS" "All services are healthy"
                return 0
            fi
            sleep 2
            ((retries++))
        done
        
        log "WARN" "Services started but health check inconclusive"
        return 0
    else
        error_exit "Failed to start services"
    fi
}

# Backup database
backup_database() {
    local backup_dir="$1"
    local timestamp="$2"
    
    log "INFO" "Starting database backup..."
    
    local db_backup_file="$backup_dir/database/mattermost_db_backup_${timestamp}.sql"
    
    # Create database backup
    if docker_cmd exec docker-postgres-1 pg_dumpall -U mmuser > "$db_backup_file"; then
        # Verify backup file is not empty and contains expected content
        if [[ -s "$db_backup_file" ]] && grep -q "CREATE ROLE mmuser" "$db_backup_file"; then
            log "SUCCESS" "Database backup completed: $(du -h "$db_backup_file" | cut -f1)"
        else
            error_exit "Database backup appears to be incomplete or corrupted"
        fi
    else
        error_exit "Database backup failed"
    fi
}

# Backup Mattermost data
backup_data() {
    local backup_dir="$1"
    local timestamp="$2"
    
    log "INFO" "Starting data backup..."
    
    local data_backup_file="$backup_dir/data/mattermost_data_backup_${timestamp}.tar.gz"
    
    # Create data backup
    if tar_cmd -czf "$data_backup_file" -C "$DOCKER_DIR" ./volumes/app/mattermost/; then
        # Verify backup file exists and is not empty
        if [[ -s "$data_backup_file" ]]; then
            log "SUCCESS" "Data backup completed: $(du -h "$data_backup_file" | cut -f1)"
            
            # Verify archive integrity
            if tar_cmd -tzf "$data_backup_file" >/dev/null 2>&1; then
                log "INFO" "Data backup archive integrity verified"
            else
                error_exit "Data backup archive is corrupted"
            fi
        else
            error_exit "Data backup file is empty"
        fi
    else
        error_exit "Data backup failed"
    fi
}

# Backup configuration
backup_config() {
    local backup_dir="$1"
    local timestamp="$2"
    
    log "INFO" "Starting configuration backup..."
    
    local config_backup_file="$backup_dir/config/mattermost_config_backup_${timestamp}.tar.gz"
    
    # Create config backup (excluding large certificate archives)
    if tar_cmd --exclude=certs/etc/letsencrypt/archive \
        --exclude=certs/lib/letsencrypt \
        -czf "$config_backup_file" \
        -C "$DOCKER_DIR" \
        .env \
        docker-compose.yml \
        docker-compose.nginx.yml \
        nginx/ \
        certs/ \
        scripts/; then
        
        # Verify backup file exists and is not empty
        if [[ -s "$config_backup_file" ]]; then
            log "SUCCESS" "Configuration backup completed: $(du -h "$config_backup_file" | cut -f1)"
            
            # Verify archive integrity
            if tar_cmd -tzf "$config_backup_file" >/dev/null 2>&1; then
                log "INFO" "Configuration backup archive integrity verified"
            else
                error_exit "Configuration backup archive is corrupted"
            fi
        else
            error_exit "Configuration backup file is empty"
        fi
    else
        error_exit "Configuration backup failed"
    fi
}

# Simple local cleanup - keep only last 2 backups locally
cleanup_old_backups() {
    log "INFO" "Cleaning up old local backups (keeping last 2 for quick access)..."
    
    # Get list of backup directories sorted by date (oldest first)
    local backup_dirs=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort))
    local total_backups=${#backup_dirs[@]}
    local keep_count=2
    
    if [[ $total_backups -le $keep_count ]]; then
        log "INFO" "Found $total_backups backups, keeping all (≤ $keep_count)"
        return 0
    fi
    
    local delete_count=$((total_backups - keep_count))
    local deleted=0
    
    # Delete oldest backups, keep only the last 2
    for ((i=0; i<delete_count; i++)); do
        local dir="${backup_dirs[$i]}"
        local dir_name=$(basename "$dir")
        
        if rm -rf "$dir"; then
            ((deleted++))
            log "INFO" "Deleted local backup: $dir_name (cloud copy preserved)"
        else
            log "WARN" "Failed to delete local backup: $dir_name"
        fi
    done
    
    log "INFO" "Local cleanup completed: deleted $deleted backups, kept $keep_count most recent"
    log "INFO" "Cloud storage handles all long-term retention via rclone"
}

# Generate backup summary
generate_summary() {
    local backup_dir="$1"
    local timestamp="$2"
    
    local summary_file="$backup_dir/backup_summary_${timestamp}.txt"
    
    cat > "$summary_file" << EOF
Mattermost Backup Summary
========================
Backup Date: $(date)
Backup Directory: $backup_dir

Database Backup:
$(ls -lh "$backup_dir"/database/*.sql 2>/dev/null || echo "No database backup found")

Data Backup:
$(ls -lh "$backup_dir"/data/*.tar.gz 2>/dev/null || echo "No data backup found")

Configuration Backup:
$(ls -lh "$backup_dir"/config/*.tar.gz 2>/dev/null || echo "No config backup found")

Total Backup Size: $(du -sh "$backup_dir" | cut -f1)

Available Disk Space: $(df -h "$HOME_DIR" | tail -1 | awk '{print $4}')

Backup Status: SUCCESS
EOF
    
    log "INFO" "Backup summary created: $summary_file"
}

# Upload to cloud storage with retention
cloud_backup() {
    local backup_dir="$1"
    local timestamp="$2"
    
    log "INFO" "Starting cloud backup upload..."
    
    # Check if rclone is available
    if ! command -v rclone >/dev/null 2>&1; then
        log "WARN" "rclone not found - skipping cloud backup"
        return 0
    fi
    
    if ! rclone config show swissbackup >/dev/null 2>&1; then
        log "WARN" "rclone SwissBackup configuration not found - skipping cloud backup"
        return 0
    fi
    
    # Determine retention policy based on day of week
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    local max_age=""
    
    # Sunday backups get longer retention (weekly backup)
    # All other days get standard retention (daily backup)
    if [[ "$day_of_week" == "7" ]]; then
        max_age="28d"
        log "INFO" "Weekly backup detected (Sunday) - using 28 day cloud retention"
    else
        max_age="7d"
        log "INFO" "Daily backup detected - using 7 day cloud retention"
    fi
    
    # Sync to cloud with appropriate retention
    if rclone sync "$BACKUP_BASE_DIR" "$CLOUD_REMOTE" \
        --max-age "$max_age" \
        --delete-during \
        --progress \
        --stats-one-line \
        --stats 30s \
        --log-file ${LOGS_DIR}/rclone-backup.log \
        --log-level INFO; then
        
        log "SUCCESS" "Cloud backup completed with $max_age retention"
        log "INFO" "Cloud storage automatically cleaned old backups beyond $max_age"
    else
        log "ERROR" "Cloud backup failed"
        return 1
    fi
}

# Main backup function
main() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    log "INFO" "Starting Mattermost backup process - Timestamp: $timestamp"
    
    # Pre-flight checks
    check_permissions
    check_disk_space
    check_services
    
    # Create backup structure
    create_backup_dirs "$timestamp"
    
    # Stop services safely
    stop_services
    
    # Perform backups
    backup_database "$BACKUP_DIR" "$timestamp"
    backup_data "$BACKUP_DIR" "$timestamp"
    backup_config "$BACKUP_DIR" "$timestamp"
    
    # Restart services
    restart_services
    
    # Generate summary
    generate_summary "$BACKUP_DIR" "$timestamp"
    
    # Upload to cloud storage (with automatic retention)
    cloud_backup "$BACKUP_DIR" "$timestamp"
    
    # Simple local cleanup (keep last 2 backups)
    cleanup_old_backups
    
    log "SUCCESS" "Backup process completed successfully"
    log "INFO" "Backup location: $BACKUP_DIR"
    log "INFO" "Total backup size: $(du -sh "$BACKUP_DIR" | cut -f1)"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [--verbose] [--allow-root]

Arguments:
  --verbose         Enable verbose output
  --allow-root      Allow running as root user (not recommended)

Examples:
  $0                    # Run backup with standard logging
  $0 --verbose          # Run backup with verbose output
  $0 --allow-root       # Run as root (use with caution)
  $0 --verbose --allow-root  # Verbose output and allow root

Description:
  Creates comprehensive backups of Mattermost installation including:
  - PostgreSQL database (complete dump)
  - Mattermost data files and uploads
  - Configuration files and SSL certificates
  
  Local storage: Keeps last 2 backups in $BACKUP_BASE_DIR
  Cloud storage: Automatic retention via rclone (7d daily, 28d on Sundays)
  Logs: Main log at $LOG_FILE, rclone log at $LOGS_DIR/rclone-backup.log
  
EOF
}

# Parse arguments
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --verbose)
            VERBOSE="--verbose"
            ;;
        --allow-root)
            ALLOW_ROOT="--allow-root"
            ;;
        *)
            echo "Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
