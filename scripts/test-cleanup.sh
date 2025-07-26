#!/bin/bash

# Test cleanup function
BACKUP_BASE_DIR="/home/ubuntu/backups"

echo "Current backups:"
ls -la "$BACKUP_BASE_DIR" | grep "^d" | grep "20"

echo ""
echo "Testing cleanup logic..."

# Get list of backup directories sorted by date (newest first)
backup_dirs=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
total_backups=${#backup_dirs[@]}
keep_count=2

echo "Found $total_backups backups total"
echo "Will keep newest $keep_count backups"
echo "Will delete oldest $((total_backups - keep_count)) backups"

echo ""
echo "Backup directories (newest first):"
for ((i=0; i<total_backups; i++)); do
    dir_name=$(basename "${backup_dirs[$i]}")
    if [[ $i -lt $keep_count ]]; then
        echo "  KEEP:   $dir_name"
    else
        echo "  DELETE: $dir_name"
    fi
done

echo ""
echo "Performing cleanup..."

deleted=0
for ((i=keep_count; i<total_backups; i++)); do
    dir="${backup_dirs[$i]}"
    dir_name=$(basename "$dir")
    
    echo "Deleting: $dir_name"
    if rm -rf "$dir"; then
        ((deleted++))
        echo "  ✓ Deleted successfully"
    else
        echo "  ✗ Failed to delete"
    fi
done

echo ""
echo "Cleanup completed: deleted $deleted backups"
echo ""
echo "Remaining backups:"
ls -la "$BACKUP_BASE_DIR" | grep "^d" | grep "20"
