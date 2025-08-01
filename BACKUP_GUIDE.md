# Mattermost Backup Guide

This guide provides comprehensive instructions for backing up your Mattermost Docker installation, including automated backup scripts and scheduling.

## Backup Components

A complete Mattermost backup includes:

1. **PostgreSQL Database** - All user data, messages, channels, teams
2. **Mattermost Data Files** - File uploads, attachments, profile pictures
3. **Configuration Files** - Mattermost configuration and SSL certificates
4. **Docker Environment** - Environment variables and compose files

## Automated Backup Script (Recommended)

The easiest way to create backups is using the automated backup script:

```bash
# Basic backup
cd ~/docker/scripts
./backup-mattermost.sh

# Verbose backup (shows progress)
./backup-mattermost.sh --verbose

# Allow running as root (not recommended)
./backup-mattermost.sh --allow-root

# Both verbose and allow root
./backup-mattermost.sh --verbose --allow-root
```

### Script Features

- **Smart Service Management**: Safely stops Mattermost/nginx, keeps database running
- **Comprehensive Backup**: Database, data files, and configuration
- **Integrity Verification**: Validates all backup archives
- **Cloud Integration**: Automatic upload to SwissBackup with retention policies
- **Local Cleanup**: Keeps only the 2 most recent local backups
- **Error Recovery**: Automatically restarts services on failure
- **Flexible Paths**: Works with any user, not hardcoded to ubuntu
- **Root Support**: Can run as root with --allow-root flag

### Backup Locations

**Local Backups**:
- **Daily Backups**: `~/backups/daily/YYYYMMDD_HHMMSS/`
- **Weekly Backups**: `~/backups/weekly/YYYYMMDD_HHMMSS/` (created on Sundays)

Each backup directory contains:
- `database/mattermost_db_backup_YYYYMMDD_HHMMSS.sql`
- `data/mattermost_data_backup_YYYYMMDD_HHMMSS.tar.gz`
- `config/mattermost_config_backup_YYYYMMDD_HHMMSS.tar.gz`
- `backup_summary_YYYYMMDD_HHMMSS.txt`

**Cloud Backups**: 
- `swissbackup:mattermost-backups/daily/` - Daily backups with 7-day retention
- `swissbackup:mattermost-backups/weekly/` - Weekly backups with 28-day retention

**Logs**: `~/logs/mattermost-backup.log` and `~/logs/rclone-backup.log`

### Cloud Backup Retention Policy

The backup system uses intelligent scheduling and retention:

**Backup Schedule**:
- **Monday-Saturday**: Daily backups stored in `~/backups/daily/`
- **Sunday**: Weekly backups stored in `~/backups/weekly/`

**Local Retention**:
- **Daily backups**: Keep last 2 locally
- **Weekly backups**: Keep last 2 locally

**Cloud Retention**:
- **Daily backups**: Kept for 7 days in `swissbackup:mattermost-backups/daily/`
- **Weekly backups**: Kept for 28 days in `swissbackup:mattermost-backups/weekly/`

This ensures you have:
- Recent backups locally for fast access
- 1 week of daily granularity in the cloud
- 4 weeks of weekly backups for longer-term recovery

## Manual Backup Process

### Prerequisites

- Administrative access to the server
- Sufficient disk space for backups (recommend 2x current data size)
- Docker and Docker Compose installed

### Step 1: Prepare Backup Directory

```bash
# Create backup directory structure  
mkdir -p ~/backups/{daily,weekly}
mkdir -p ~/logs
```

### Step 2: Stop Mattermost Application

```bash
cd ~/docker

# Stop Mattermost and nginx (keep database running)
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml stop mattermost nginx

# Verify only postgres is running
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps
```

### Step 3: Backup Database

```bash
# Create database backup with timestamp
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# Determine backup type and directory
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday
if [[ "$DAY_OF_WEEK" == "7" ]]; then
    BACKUP_TYPE="weekly"
else
    BACKUP_TYPE="daily"
fi

# Create backup directories
mkdir -p ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/{database,data,config}

# Create database backup
sudo docker exec docker-postgres-1 pg_dumpall -U mmuser > \
  ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/database/mattermost_db_backup_${BACKUP_DATE}.sql

# Verify backup was created
ls -lh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/database/
```

### Step 4: Backup Mattermost Data

```bash
# Backup Mattermost data directory
sudo tar -czf ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/data/mattermost_data_backup_${BACKUP_DATE}.tar.gz \
  -C ~/docker ./volumes/app/mattermost/

# Verify backup was created
ls -lh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/data/
```

### Step 5: Backup Configuration

```bash
# Backup Docker configuration and certificates
sudo tar -czf ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/config/mattermost_config_backup_${BACKUP_DATE}.tar.gz \
  -C ~/docker \
  .env \
  docker-compose.yml \
  docker-compose.nginx.yml \
  nginx/ \
  certs/ \
  scripts/ \
  --exclude=certs/etc/letsencrypt/archive \
  --exclude=certs/lib/letsencrypt

# Verify backup was created
ls -lh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/config/
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
head -20 ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/database/mattermost_db_backup_${BACKUP_DATE}.sql

# Test archive integrity
tar -tzf ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/data/mattermost_data_backup_${BACKUP_DATE}.tar.gz > /dev/null
tar -tzf ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/config/mattermost_config_backup_${BACKUP_DATE}.tar.gz > /dev/null

# Check backup sizes
du -sh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/database/mattermost_db_backup_${BACKUP_DATE}.sql
du -sh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/data/mattermost_data_backup_${BACKUP_DATE}.tar.gz
du -sh ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/config/mattermost_config_backup_${BACKUP_DATE}.tar.gz

# Show backup summary
cat ~/backups/${BACKUP_TYPE}/${BACKUP_DATE}/backup_summary_${BACKUP_DATE}.txt
```

## Automated Backup Setup

### Setting up Scheduled Backups

Use the automated cron setup script:

```bash
cd ~/docker/scripts
./setup-backup-cron.sh
```

This script will:
- Set up daily backups at 2:00 AM
- Configure proper log rotation
- Test the backup process
- Verify rclone cloud configuration

### Manual Cron Setup

If you prefer manual setup:

```bash
# Edit crontab
crontab -e

# Add this line for daily backups at 2 AM
0 2 * * * /home/$(whoami)/docker/scripts/backup-mattermost.sh >> ~/logs/cron-backup.log 2>&1
```

## Monitoring and Logs

### Viewing Logs

```bash
# View backup logs
tail -f ~/logs/mattermost-backup.log

# View cloud backup logs
tail -f ~/logs/rclone-backup.log

# View recent backup activity
grep "SUCCESS\|ERROR" ~/logs/mattermost-backup.log | tail -10
```

### Log Rotation

Create `/etc/logrotate.d/mattermost-backup`:

```
~/logs/mattermost-backup*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
```

## Cloud Backup Configuration

### SwissBackup Setup

The backup script supports automatic cloud uploads via rclone. Configure SwissBackup:

```bash
# View current cloud backups (new structure)
rclone ls swissbackup:mattermost-backups/daily
rclone ls swissbackup:mattermost-backups/weekly

# List with the backup manager script
cd ~/docker/scripts
./rclone-manager.sh list
```

### Cloud Backup Features

- **Organized structure**: Separate daily and weekly directories
- **Automatic retention**: Old backups automatically deleted by age
- **Differential sync**: Only changed files uploaded
- **Progress reporting**: Real-time upload progress
- **Error handling**: Continues backup process on cloud failure
- **Management tools**: Use `rclone-manager.sh` script for easy management

## Disaster Recovery

### Restoring from Backup

See `RESTORE_GUIDE.md` for detailed restoration procedures.

### Quick Recovery Steps

1. **Stop services**: `sudo docker compose down`
2. **Restore database**: Use `pg_restore` or `psql`
3. **Extract data**: `tar -xzf mattermost_data_backup_*.tar.gz`
4. **Extract config**: `tar -xzf mattermost_config_backup_*.tar.gz`
5. **Start services**: `sudo docker compose up -d`

## Troubleshooting

### Common Issues

**Permission Errors**:
```bash
# Fix backup directory permissions
sudo chown -R $(whoami):$(whoami) ~/backups ~/logs
```

**Service Won't Stop**:
```bash
# Force stop containers
sudo docker compose kill mattermost nginx
```

**Backup Too Large**:
```bash
# Check what's using space
du -sh ~/docker/volumes/app/mattermost/*

# Clean old files if needed
find ~/docker/volumes/app/mattermost/data -name "*.tmp" -delete
```

**Cloud Upload Fails**:
```bash
# Test rclone configuration
rclone config show swissbackup

# Manual upload test
rclone copy ~/backups/latest swissbackup:test-upload
```

### Getting Help

Check logs for detailed error messages:
```bash
# Recent errors
grep ERROR ~/logs/mattermost-backup.log | tail -5

# Full backup session
grep "$(date +%Y-%m-%d)" ~/logs/mattermost-backup.log
```

## Security Considerations

- **Encrypt backups** before storing offsite
- **Secure transfer** using rclone encryption
- **Access control** on backup directories
- **Regular testing** of restore procedures
- **Monitor logs** for unauthorized access

## Best Practices

1. **Test restores regularly** - Ensure backups are actually usable
2. **Monitor backup sizes** - Watch for unexpected growth
3. **Keep multiple copies** - Local + cloud + offsite
4. **Document procedures** - Keep restoration steps updated
5. **Automate monitoring** - Set up alerts for backup failures

For more detailed information, see:
- `RESTORE_GUIDE.md` - Restoration procedures
- `TROUBLESHOOTING.md` - Common issues and solutions
- `scripts/backup-mattermost.sh` - Source code and comments
