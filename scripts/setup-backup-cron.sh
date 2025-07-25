#!/bin/bash

#
# Cron Setup Script for Mattermost Backups
#
# This script helps set up automated backups using cron
#

echo "Mattermost Backup Cron Setup"
echo "============================="
echo

# Check if script exists
SCRIPT_PATH="/home/ubuntu/docker/scripts/backup-mattermost.sh"
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: Backup script not found at $SCRIPT_PATH"
    exit 1
fi

# Make sure script is executable
chmod +x "$SCRIPT_PATH"

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/mattermost-backup.log
sudo chown ubuntu:ubuntu /var/log/mattermost-backup.log

echo "Choose backup frequency:"
echo "1) Daily backups (2:00 AM, 7 days retention)"
echo "2) Daily + Weekly backups (daily at 2:00 AM, weekly Sunday 1:00 AM)"
echo "3) Custom schedule"
echo "4) Show current cron jobs"
echo "5) Remove backup cron jobs"
echo

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo "Setting up daily backups..."
        # Remove any existing mattermost backup cron jobs
        crontab -l 2>/dev/null | grep -v "backup-mattermost.sh" | crontab -
        
        # Add daily backup
        (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_PATH 7 >> /var/log/mattermost-backup.log 2>&1") | crontab -
        
        echo "✅ Daily backup scheduled for 2:00 AM (7 days retention)"
        ;;
        
    2)
        echo "Setting up daily + weekly backups..."
        # Remove any existing mattermost backup cron jobs
        crontab -l 2>/dev/null | grep -v "backup-mattermost.sh" | crontab -
        
        # Add daily and weekly backups
        (crontab -l 2>/dev/null; echo "0 2 * * 1-6 $SCRIPT_PATH 7 >> /var/log/mattermost-backup.log 2>&1") | crontab -
        (crontab -l 2>/dev/null; echo "0 1 * * 0 $SCRIPT_PATH 28 >> /var/log/mattermost-backup-weekly.log 2>&1") | crontab -
        
        echo "✅ Daily backup scheduled for 2:00 AM Mon-Sat (7 days retention)"
        echo "✅ Weekly backup scheduled for 1:00 AM Sunday (28 days retention)"
        ;;
        
    3)
        echo "Custom schedule setup:"
        echo "Enter cron expression (e.g., '0 2 * * *' for daily at 2:00 AM):"
        read -p "Cron expression: " cron_expr
        read -p "Retention days: " retention_days
        
        if [[ -z "$cron_expr" ]] || [[ -z "$retention_days" ]]; then
            echo "ERROR: Both cron expression and retention days are required"
            exit 1
        fi
        
        # Validate retention days is a number
        if ! [[ "$retention_days" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Retention days must be a number"
            exit 1
        fi
        
        # Add custom backup
        (crontab -l 2>/dev/null; echo "$cron_expr $SCRIPT_PATH $retention_days >> /var/log/mattermost-backup.log 2>&1") | crontab -
        
        echo "✅ Custom backup scheduled: $cron_expr ($retention_days days retention)"
        ;;
        
    4)
        echo "Current cron jobs:"
        crontab -l 2>/dev/null || echo "No cron jobs found"
        ;;
        
    5)
        echo "Removing Mattermost backup cron jobs..."
        crontab -l 2>/dev/null | grep -v "backup-mattermost.sh" | crontab -
        echo "✅ Mattermost backup cron jobs removed"
        ;;
        
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo
echo "Setup complete!"
echo
echo "Useful commands:"
echo "  View logs:        tail -f /var/log/mattermost-backup.log"
echo "  Test backup:      $SCRIPT_PATH --verbose"
echo "  List cron jobs:   crontab -l"
echo "  Edit cron jobs:   crontab -e"
echo
echo "Log rotation setup (optional):"
cat << 'EOF'
  Create /etc/logrotate.d/mattermost-backup:
  
  /var/log/mattermost-backup*.log {
      daily
      missingok
      rotate 30
      compress
      delaycompress
      notifempty
      create 644 ubuntu ubuntu
  }
EOF
