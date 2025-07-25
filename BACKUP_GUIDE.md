# Mattermost Backup Guide

This guide provides comprehensive instructions for backing up your Mattermost Docker installation, including automated backup scripts and scheduling.

## Backup Components

A complete Mattermost backup includes:

1. **PostgreSQL Database** - All user data, messages, channels, teams
2. **Mattermost Data Files** - File uploads, attachments, profile pictures
3. **Configuration Files** - Mattermost configuration and SSL certificates
4. **Docker Environment** - Environment variables and compose files

## Manual Backup Process

### Prerequisites

- Administrative access to the server
- Sufficient disk space for backups (recommend 2x current data size)
- Docker and Docker Compose installed

### Step 1: Prepare Backup Directory

```bash
# Create backup directory structure
sudo mkdir -p /home/ubuntu/backups/{database,data,config}

# Set proper permissions
sudo chown -R ubuntu:ubuntu /home/ubuntu/backups/
```

### Step 2: Stop Mattermost Application

```bash
cd /home/ubuntu/docker

# Stop Mattermost and nginx (keep database running)
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml stop mattermost nginx

# Verify only postgres is running
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps
```

### Step 3: Backup Database

```bash
# Create database backup with timestamp
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
sudo docker exec docker-postgres-1 pg_dumpall -U mmuser > \
  /home/ubuntu/backups/database/mattermost_db_backup_${BACKUP_DATE}.sql

# Verify backup was created
ls -lh /home/ubuntu/backups/database/
```

### Step 4: Backup Mattermost Data

```bash
# Backup Mattermost data directory
sudo tar -czf /home/ubuntu/backups/data/mattermost_data_backup_${BACKUP_DATE}.tar.gz \
  -C /home/ubuntu/docker ./volumes/app/mattermost/

# Verify backup was created
ls -lh /home/ubuntu/backups/data/
```

### Step 5: Backup Configuration

```bash
# Backup Docker configuration and certificates
sudo tar -czf /home/ubuntu/backups/config/mattermost_config_backup_${BACKUP_DATE}.tar.gz \
  -C /home/ubuntu/docker \
  .env \
  docker-compose.yml \
  docker-compose.nginx.yml \
  nginx/ \
  certs/ \
  --exclude=certs/etc/letsencrypt/archive \
  --exclude=certs/lib/letsencrypt

# Verify backup was created
ls -lh /home/ubuntu/backups/config/
```

### Step 6: Restart Services

```bash
# Start all services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Verify all containers are healthy
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps
```

### Step 7: Verify Backup Integrity

```bash
# Check database backup can be read
head -20 /home/ubuntu/backups/database/mattermost_db_backup_${BACKUP_DATE}.sql

# Check data backup contents
sudo tar -tzf /home/ubuntu/backups/data/mattermost_data_backup_${BACKUP_DATE}.tar.gz | head -10

# Check config backup contents
sudo tar -tzf /home/ubuntu/backups/config/mattermost_config_backup_${BACKUP_DATE}.tar.gz
```

## Automated Backup Script

Use the automated script located at `/home/ubuntu/docker/scripts/backup-mattermost.sh` for regular backups.

### Script Features

- ✅ **Automatic timestamping** - Each backup gets a unique timestamp
- ✅ **Service management** - Safely stops/starts services
- ✅ **Retention policy** - Automatically removes old backups
- ✅ **Compression** - Reduces backup file sizes
- ✅ **Verification** - Checks backup integrity
- ✅ **Logging** - Records backup operations
- ✅ **Error handling** - Graceful failure management

### Running the Backup Script

```bash
cd /home/ubuntu/docker

# Make script executable
chmod +x scripts/backup-mattermost.sh

# Run manual backup
./scripts/backup-mattermost.sh

# Run with custom retention (days)
./scripts/backup-mattermost.sh 14

# Run with verbose output
./scripts/backup-mattermost.sh --verbose
```

### Complete Backup + Cloud Sync Workflow

The backup script **automatically includes cloud sync** when properly configured:

```bash
cd /home/ubuntu/docker

# Single command performs BOTH local backup AND cloud sync
./scripts/backup-mattermost.sh 7

# Verify both local and cloud backups were created
ls -la /home/ubuntu/backups/$(date +%Y%m%d)*/
rclone lsd swissbackup:mattermost-backups/$(date +%Y%m%d)*
```

**Cloud Backup Integration:**
- ✅ **Automatic cloud sync** - Runs after local backup completes
- ✅ **Graceful fallback** - Continues if cloud backup fails
- ✅ **Configuration checks** - Verifies rclone and SwissBackup setup
- ✅ **Consolidated logging** - All operations logged to same file

**Manual Cloud-Only Sync:**
```bash
# If you only want to sync existing backups to cloud (without creating new backup)
./scripts/cloud-backup.sh --verbose
```

**Automated Complete Workflow:**
```bash
# Edit crontab for complete backup solution
crontab -e

# Single cron job performs both local backup AND cloud sync
0 2 * * * /home/ubuntu/docker/scripts/backup-mattermost.sh 7 >> /var/log/mattermost-backup.log 2>&1
```

## Scheduled Backups with Cron

### Daily Backup Setup

```bash
# Edit crontab
crontab -e

# Add daily backup at 2:00 AM (keeps 7 days of backups)
0 2 * * * /home/ubuntu/docker/scripts/backup-mattermost.sh 7 >> /var/log/mattermost-backup.log 2>&1

# Add weekly full backup on Sundays at 1:00 AM (keeps 4 weeks)
0 1 * * 0 /home/ubuntu/docker/scripts/backup-mattermost.sh 28 >> /var/log/mattermost-backup-weekly.log 2>&1
```

### Multiple Backup Frequencies

```bash
# Daily incremental backups (7 days retention)
0 2 * * * /home/ubuntu/docker/scripts/backup-mattermost.sh 7

# Weekly full backups (4 weeks retention)  
0 1 * * 0 /home/ubuntu/docker/scripts/backup-mattermost.sh 28

# Monthly archive backups (12 months retention)
0 0 1 * * /home/ubuntu/docker/scripts/backup-mattermost.sh 365
```

### View Cron Logs

```bash
# View backup logs
tail -f /var/log/mattermost-backup.log

# Check cron is running backups
grep mattermost /var/log/syslog

# List current cron jobs
crontab -l
```

**Note:** Prior to July 25, 2025, log entries were duplicated due to the script using `tee` to write to both stdout and log file, while cron redirected stdout to the same log file. This has been fixed by writing directly to the log file only.

## Backup Storage Options

### Local Storage

```bash
# Current setup - local storage
BACKUP_DIR="/home/ubuntu/backups"

# Pros: Fast, simple, no external dependencies
# Cons: Single point of failure, limited by disk space
```

### Cloud Storage (SwissBackup) - Automated

The included `cloud-backup.sh` script provides automated sync to SwissBackup cloud storage using rclone.

**Prerequisites:**
- rclone installed and configured for SwissBackup
- SwissBackup account and credentials

**Setup rclone for SwissBackup:**
```bash
# Configure rclone for SwissBackup (one-time setup)
rclone config

# Test connection
rclone lsd swissbackup:
```

**When to Use Standalone Cloud Backup Script:**

The `cloud-backup.sh` script is useful for:
- **Testing cloud connectivity** before setting up automated backups
- **Manual re-sync** of existing backups without creating new ones
- **Dry-run testing** to see what would be uploaded
- **Troubleshooting** cloud sync issues independently

```bash
cd /home/ubuntu/docker

# Test cloud connectivity (dry-run)
./scripts/cloud-backup.sh --dry-run --verbose

# Manual sync of existing backups only (no new backup created)
./scripts/cloud-backup.sh

# Verbose sync with detailed progress
./scripts/cloud-backup.sh --verbose
```

**Normal Usage - Integrated Backup:**
```bash
# Recommended: Single command does both local backup AND cloud sync
./scripts/backup-mattermost.sh 7
```

**Script Features:**
- ✅ **Automated sync** - Syncs entire `/home/ubuntu/backups/` directory
- ✅ **Progress reporting** - Real-time transfer progress
- ✅ **Logging** - Detailed logs in `/home/ubuntu/logs/rclone-backup.log`
- ✅ **Verification** - Checks sync results after completion
- ✅ **Report generation** - Creates sync reports in `/home/ubuntu/logs/`
- ✅ **Dry-run mode** - Test transfers without actually uploading
- ✅ **Error handling** - Graceful failure management

**Cloud Storage Target:**
- **Remote:** `swissbackup:mattermost-backups`
- **Provider:** SwissBackup (OpenStack Swift)
- **Sync Method:** `rclone sync` (one-way, source to destination)

**⚠️ Note:** The main backup script (`backup-mattermost.sh`) automatically calls cloud backup, so you typically don't need separate cron jobs for cloud sync.

**Monitoring Cloud Backups:**
```bash
# View cloud backup logs (integrated with main backup logs)
tail -f /var/log/mattermost-backup.log | grep -i cloud

# Check standalone cloud backup logs
tail -f /home/ubuntu/logs/rclone-backup.log

# Check latest sync report
ls -la /home/ubuntu/logs/cloud-backup-report-*.txt | tail -1
cat /home/ubuntu/logs/cloud-backup-report-$(date +%Y%m%d)*.txt

# List remote backups
rclone lsd swissbackup:mattermost-backups

# Check remote backup sizes
rclone size swissbackup:mattermost-backups
```

### Alternative Remote Storage Options

```bash
# Sync to remote server via rsync
rsync -avz --delete /home/ubuntu/backups/ user@backup-server:/path/to/backups/

# Upload to other cloud providers with rclone
rclone sync /home/ubuntu/backups/ gdrive:mattermost-backups/    # Google Drive
rclone sync /home/ubuntu/backups/ s3:bucket/mattermost-backups/  # AWS S3
rclone sync /home/ubuntu/backups/ dropbox:mattermost-backups/   # Dropbox

# Backup to external mounted drive
cp -r /home/ubuntu/backups/* /mnt/external-drive/mattermost-backups/
```

## Backup Verification

### Database Backup Verification

```bash
# Check if backup file is valid SQL
sudo docker run --rm -i postgres:13-alpine psql --help > /dev/null < backup.sql

# Verify backup contains expected tables
grep -c "CREATE TABLE" backup.sql

# Check backup file size (should not be empty)
ls -lh backup.sql
```

### Data Backup Verification

```bash
# Test archive integrity
tar -tzf backup.tar.gz > /dev/null && echo "Archive OK" || echo "Archive corrupted"

# Check backup contains expected directories
tar -tzf backup.tar.gz | grep -E "(data|config|logs|plugins)" | head -5

# Verify file count matches
tar -tzf backup.tar.gz | wc -l
```

## Restoration Testing

### Quarterly Restoration Tests

```bash
# Test database restoration (to test database)
sudo docker exec -i docker-postgres-1 psql -U mmuser -d postgres \
  -c "CREATE DATABASE test_restore;"

sudo docker exec -i docker-postgres-1 psql -U mmuser -d test_restore < backup.sql

# Cleanup test
sudo docker exec -i docker-postgres-1 psql -U mmuser -d postgres \
  -c "DROP DATABASE test_restore;"
```

## Backup Monitoring

### Disk Space Monitoring

```bash
# Check backup directory size
du -sh /home/ubuntu/backups/

# Monitor disk usage
df -h /home/ubuntu

# Set up alerts for low disk space (add to cron)
if [ $(df /home/ubuntu | tail -1 | awk '{print $5}' | sed 's/%//') -gt 80 ]; then
  echo "WARNING: Disk usage above 80%" | mail -s "Disk Space Alert" admin@iaqi.org
fi
```

### Backup Success Monitoring

**Local Backup Monitoring:**
```bash
# Check if recent backup exists (last 24 hours)
find /home/ubuntu/backups/ -name "*.sql" -mtime -1 -ls

# Verify backup script runs successfully
tail -20 /var/log/mattermost-backup.log | grep -E "(SUCCESS|ERROR|FAILED)"

# Check backup directory structure
ls -la /home/ubuntu/backups/$(date +%Y%m%d)*/
```

**Cloud Backup Monitoring:**
```bash
# Check cloud backup logs
tail -20 /home/ubuntu/logs/rclone-backup.log | grep -E "(SUCCESS|ERROR|FAILED)"

# Verify recent cloud sync
cat /home/ubuntu/logs/cloud-backup-report-$(date +%Y%m%d)*.txt 2>/dev/null || echo "No cloud backup report for today"

# List remote backups (requires rclone)
rclone lsd swissbackup:mattermost-backups | grep $(date +%Y%m%d)

# Compare local vs remote backup counts
echo "Local backup sets: $(find /home/ubuntu/backups/ -maxdepth 1 -type d -name "20*" | wc -l)"
echo "Remote backup sets: $(rclone lsd swissbackup:mattermost-backups 2>/dev/null | wc -l)"
```

**Combined Monitoring Script:**
```bash
# Create comprehensive backup monitor
cat > /usr/local/bin/backup-monitor.sh << 'EOF'
#!/bin/bash
echo "=== Backup Status Report - $(date) ==="
echo ""

# Local backups
echo "LOCAL BACKUPS:"
echo "Backup directory size: $(du -sh /home/ubuntu/backups/ | cut -f1)"
echo "Recent backups: $(find /home/ubuntu/backups/ -name "*.sql" -mtime -1 | wc -l) in last 24h"
echo "Latest backup: $(ls -t /home/ubuntu/backups/20*/backup_summary_*.txt 2>/dev/null | head -1 | xargs -r ls -la)"
echo ""

# Cloud backups  
echo "CLOUD BACKUPS:"
if command -v rclone >/dev/null 2>&1; then
    echo "Remote backup sets: $(rclone lsd swissbackup:mattermost-backups 2>/dev/null | wc -l || echo "Connection failed")"
    echo "Latest cloud sync: $(ls -t /home/ubuntu/logs/cloud-backup-report-*.txt 2>/dev/null | head -1 | xargs -r basename)"
else
    echo "rclone not available"
fi
echo ""

# Disk usage
echo "DISK USAGE:"
df -h /home/ubuntu | grep "/home/ubuntu"
EOF

chmod +x /usr/local/bin/backup-monitor.sh

# Run manually or add to cron for daily reports
/usr/local/bin/backup-monitor.sh
```

## Security Considerations

### Backup Encryption

```bash
# Encrypt sensitive backups
gpg --cipher-algo AES256 --compress-algo 1 --s2k-cipher-algo AES256 \
    --s2k-digest-algo SHA512 --s2k-mode 3 --s2k-count 65536 \
    --symmetric backup.tar.gz

# Decrypt when needed
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

### Access Control

```bash
# Secure backup directory permissions
chmod 700 /home/ubuntu/backups/
chmod 600 /home/ubuntu/backups/*/*.sql
chmod 600 /home/ubuntu/backups/*/*.tar.gz

# Backup to restricted location
sudo mkdir -p /var/backups/mattermost/
sudo chown root:root /var/backups/mattermost/
sudo chmod 700 /var/backups/mattermost/
```

## Troubleshooting

### Common Issues

**Backup script fails with permission errors:**
```bash
# Fix ownership issues
sudo chown -R ubuntu:ubuntu /home/ubuntu/backups/
chmod +x /home/ubuntu/docker/scripts/backup-mattermost.sh
```

**Database backup is empty:**
```bash
# Check database is running
sudo docker ps | grep postgres

# Verify database connection
sudo docker exec docker-postgres-1 psql -U mmuser -l
```

**Backup takes too long:**
```bash
# Check database size
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost \
  -c "SELECT pg_size_pretty(pg_database_size('mattermost'));"

# Consider incremental backups for large databases
```

### Recovery Procedures

If automatic backup fails:
1. Check disk space: `df -h`
2. Verify services running: `sudo docker ps`
3. Check logs: `tail /var/log/mattermost-backup.log`
4. Run manual backup to diagnose: `./scripts/backup-mattermost.sh --verbose`

## Best Practices

1. **Test restores regularly** - Verify backups can actually be restored
2. **Monitor backup size trends** - Detect unusual growth patterns
3. **Keep multiple backup copies** - Local, remote, and archive copies
4. **Document backup procedures** - Ensure team members can perform backups
5. **Automate verification** - Script checks for backup completeness
6. **Secure backup storage** - Encrypt sensitive data and control access
7. **Plan for disasters** - Consider geographic distribution of backups

---

**Backup Guide Created:** July 22, 2025  
**Target Installation:** Mattermost 10.5.2 Enterprise Edition  
**Backup Script Location:** `/home/ubuntu/docker/scripts/backup-mattermost.sh`
