#!/bin/bash

#
# Mattermost Docker Backup Script
# 
# This script creates comprehensive backups following Mattermost official guidelines:
# - PostgreSQL database (full dump using pg_dumpall)
# - Mattermost data directory (./volumes/app/mattermost/data/)
# - Mattermost config directory (./volumes/app/mattermost/config/) 
# - Docker configuration files for complete restore capability
#
# Usage: ./backup-mattermost.sh [--verbose]
# Example: ./backup-mattermost.sh --verbose
#
# Reference: https://docs.mattermost.com/deployment-guide/backup-disaster-recovery.html
# Created: July 22, 2025
# Target: Mattermost 10.5.2 Enterprise Edition
#

set -euo pipefail  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$(eval echo ~${SUDO_USER:-$USER})"  # Get actual user's home even when using sudo
BACKUP_BASE_DIR="${HOME_DIR}/backups"
BACKUP_DAILY_DIR="${BACKUP_BASE_DIR}/daily"
BACKUP_WEEKLY_DIR="${BACKUP_BASE_DIR}/weekly"
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
    
    # Disable maintenance mode if it was enabled
    rm -f "$DOCKER_DIR/nginx/conf.d/.maintenance" 2>/dev/null || true
    
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
    
    # Disable maintenance mode
    rm -f "$DOCKER_DIR/nginx/conf.d/.maintenance" 2>/dev/null || true
    
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
    local is_weekly="$2"
    
    # Choose backup directory based on type
    if [[ "$is_weekly" == "true" ]]; then
        BACKUP_DIR="$BACKUP_WEEKLY_DIR/$timestamp"
        log "INFO" "Creating weekly backup directories: $BACKUP_DIR"
    else
        BACKUP_DIR="$BACKUP_DAILY_DIR/$timestamp"
        log "INFO" "Creating daily backup directories: $BACKUP_DIR"
    fi
    
    mkdir -p "$BACKUP_DIR"/{database,data,config}
    
    # Create base backup directories if they don't exist
    mkdir -p "$BACKUP_DAILY_DIR" "$BACKUP_WEEKLY_DIR"
}

# Stop Mattermost services (keep database running) and enable maintenance mode
stop_services() {
    cd "$DOCKER_DIR"
    
    log "INFO" "Enabling maintenance mode..."
    
    # Create maintenance flag file
    if touch "$DOCKER_DIR/nginx/conf.d/.maintenance"; then
        log "SUCCESS" "Maintenance mode enabled"
        
        # Wait a moment for nginx to pick up the change
        sleep 2
    else
        log "WARN" "Failed to enable maintenance mode, continuing with backup anyway"
    fi
    
    log "INFO" "Stopping Mattermost service..."
    
    if docker_cmd compose $COMPOSE_FILES stop mattermost; then
        SERVICES_STOPPED=true
        log "SUCCESS" "Mattermost service stopped successfully"
        
        # Wait a moment for service to fully stop
        sleep 5
        
        # Verify mattermost is stopped (should NOT appear in running services)
        if docker_cmd compose $COMPOSE_FILES ps --services --filter "status=running" | grep -q "mattermost"; then
            error_exit "Failed to stop Mattermost service - still showing as running"
        else
            log "SUCCESS" "Mattermost service is confirmed stopped"
        fi
    else
        error_exit "Failed to stop Mattermost service"
    fi
}

# Restart all services and disable maintenance mode
restart_services() {
    cd "$DOCKER_DIR"
    
    log "INFO" "Starting Mattermost service..."
    
    if docker_cmd compose $COMPOSE_FILES up -d mattermost; then
        SERVICES_STOPPED=false
        log "SUCCESS" "Mattermost service started successfully"
        
        # Wait for Mattermost to be ready
        sleep 10
        
        # Verify Mattermost is running
        local retries=0
        while [[ $retries -lt 30 ]]; do
            if docker_cmd compose $COMPOSE_FILES ps | grep "mattermost" | grep -q "Up"; then
                log "SUCCESS" "Mattermost service is healthy"
                break
            fi
            sleep 2
            ((retries++))
        done
        
        # Disable maintenance mode
        log "INFO" "Disabling maintenance mode..."
        if rm -f "$DOCKER_DIR/nginx/conf.d/.maintenance"; then
            log "SUCCESS" "Maintenance mode disabled"
        else
            log "WARN" "Failed to disable maintenance mode flag"
        fi
        
        return 0
    else
        error_exit "Failed to start Mattermost service"
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
    
    # Create data backup - only backup the data directory as per Mattermost docs
    if tar_cmd -czf "$data_backup_file" -C "$DOCKER_DIR/volumes/app/mattermost" ./data/; then
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
    
    # Create config backup using Docker directory as base - preserves natural directory structure
    # Note: excludes must come before the files they apply to
    if tar_cmd -czf "$config_backup_file" \
        -C "$DOCKER_DIR" \
        ./volumes/app/mattermost/config/ \
        ./.env \
        ./docker-compose.yml \
        ./docker-compose.nginx.yml \
        --exclude='nginx/conf.d/.maintenance' \
        ./nginx/ \
        --exclude='certs/etc/letsencrypt/archive' \
        --exclude='certs/lib/letsencrypt' \
        ./certs/ \
        2>/dev/null; then
        
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
        log "WARN" "Some files may not be accessible, trying minimal approach..."
        # Fallback: create archive with only essential files
        if tar_cmd -czf "$config_backup_file" \
            -C "$DOCKER_DIR" \
            ./volumes/app/mattermost/config/ \
            ./.env \
            ./docker-compose.yml \
            ./docker-compose.nginx.yml \
            --exclude='nginx/conf.d/.maintenance' \
            ./nginx/ \
            2>/dev/null; then
            
            log "SUCCESS" "Configuration backup completed (without certificates): $(du -h "$config_backup_file" | cut -f1)"
        else
            error_exit "Configuration backup failed"
        fi
    fi
}

# Simple local cleanup - keep only last 2 daily and 2 weekly backups locally
cleanup_old_backups() {
    log "INFO" "Cleaning up old local backups..."
    
    # Clean up daily backups (keep last 2)
    log "INFO" "Cleaning up daily backups (keeping last 2)..."
    local daily_dirs=($(find "$BACKUP_DAILY_DIR" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r))
    local total_daily=${#daily_dirs[@]}
    local keep_daily=2
    
    if [[ $total_daily -le $keep_daily ]]; then
        log "INFO" "Found $total_daily daily backups, keeping all (≤ $keep_daily)"
    else
        log "INFO" "Found $total_daily daily backups, will delete $((total_daily - keep_daily)) oldest ones"
        local deleted_daily=0
        
        for ((i=keep_daily; i<total_daily; i++)); do
            local dir="${daily_dirs[$i]}"
            local dir_name=$(basename "$dir")
            
            if rm -rf "$dir"; then
                ((deleted_daily++))
                log "INFO" "Deleted old daily backup: $dir_name"
            else
                log "WARN" "Failed to delete daily backup: $dir_name"
            fi
        done
        
        log "INFO" "Daily cleanup: deleted $deleted_daily backups, kept $keep_daily most recent"
    fi
    
    # Clean up weekly backups (keep last 2)
    log "INFO" "Cleaning up weekly backups (keeping last 2)..."
    local weekly_dirs=($(find "$BACKUP_WEEKLY_DIR" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r))
    local total_weekly=${#weekly_dirs[@]}
    local keep_weekly=2
    
    if [[ $total_weekly -le $keep_weekly ]]; then
        log "INFO" "Found $total_weekly weekly backups, keeping all (≤ $keep_weekly)"
    else
        log "INFO" "Found $total_weekly weekly backups, will delete $((total_weekly - keep_weekly)) oldest ones"
        local deleted_weekly=0
        
        for ((i=keep_weekly; i<total_weekly; i++)); do
            local dir="${weekly_dirs[$i]}"
            local dir_name=$(basename "$dir")
            
            if rm -rf "$dir"; then
                ((deleted_weekly++))
                log "INFO" "Deleted old weekly backup: $dir_name"
            else
                log "WARN" "Failed to delete weekly backup: $dir_name"
            fi
        done
        
        log "INFO" "Weekly cleanup: deleted $deleted_weekly backups, kept $keep_weekly most recent"
    fi
    
    log "INFO" "Local cleanup completed - daily: last $keep_daily, weekly: last $keep_weekly"
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
    local is_weekly="$3"
    
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
    
    # Upload new backups to cloud
    if rclone copy "$BACKUP_BASE_DIR" "$CLOUD_REMOTE" \
        --progress \
        --stats-one-line \
        --stats 30s \
        --log-file ${LOGS_DIR}/rclone-backup.log \
        --log-level INFO; then
        
        # Clean up old backups by folder - much simpler now!
        log "INFO" "Cleaning up old cloud backups..."
        
        # Clean daily backups older than 7 days
        log "INFO" "Cleaning daily backups older than 7 days..."
        rclone delete "$CLOUD_REMOTE/daily" \
            --min-age 7d \
            --log-file ${LOGS_DIR}/rclone-backup.log \
            --log-level INFO || true
        
        # Clean weekly backups older than 28 days
        log "INFO" "Cleaning weekly backups older than 28 days..."
        rclone delete "$CLOUD_REMOTE/weekly" \
            --min-age 28d \
            --log-file ${LOGS_DIR}/rclone-backup.log \
            --log-level INFO || true
        
        if [[ "$is_weekly" == "true" ]]; then
            log "SUCCESS" "Weekly cloud backup completed (28d retention)"
        else
            log "SUCCESS" "Daily cloud backup completed (7d retention)"
        fi
        log "INFO" "Cloud cleanup completed - daily: 7d, weekly: 28d retention"
    else
        log "ERROR" "Cloud backup failed"
        return 1
    fi
}

# Main backup function
main() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    local is_weekly="false"
    
    # Determine if this is a weekly backup (Sunday)
    if [[ "$day_of_week" == "7" ]]; then
        is_weekly="true"
        log "INFO" "Starting Mattermost WEEKLY backup process - Timestamp: $timestamp"
    else
        log "INFO" "Starting Mattermost DAILY backup process - Timestamp: $timestamp"
    fi
    
    # Pre-flight checks
    check_permissions
    check_disk_space
    check_services
    
    # Create backup structure
    create_backup_dirs "$timestamp" "$is_weekly"
    
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
    cloud_backup "$BACKUP_DIR" "$timestamp" "$is_weekly"
    
    # Local cleanup (keep last 2 daily, 2 weekly)
    cleanup_old_backups
    
    if [[ "$is_weekly" == "true" ]]; then
        log "SUCCESS" "Weekly backup process completed successfully"
    else
        log "SUCCESS" "Daily backup process completed successfully"
    fi
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
  Creates comprehensive backups of Mattermost installation following official guidelines:
  - PostgreSQL database (complete dump)
  - Mattermost data directory (user files, uploads, etc.)
  - Mattermost config directory (config.json and SAML certificates)
  - Docker configuration files for complete restoration capability
  
  Reference: https://docs.mattermost.com/deployment-guide/backup-disaster-recovery.html
  
  Backup Structure:
  - Daily backups: Stored in $BACKUP_DAILY_DIR (local: keep 2, cloud: 7d retention)
  - Weekly backups: Stored in $BACKUP_WEEKLY_DIR (local: keep 2, cloud: 28d retention)
  - Weekly backups automatically created on Sundays
  
  Cloud storage: Automatic age-based retention (daily: 7d, weekly: 28d)
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
