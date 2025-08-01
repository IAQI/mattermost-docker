# Mattermost Database and Data Restoration Guide

This guide documents the process of restoring a Mattermost instance from backups, including PostgreSQL database, Mattermost data files, and configuration.

## Backup Files Overview

Our automated backup system creates timestamped backup directories with:

- **Database Backup:** `mattermost_db_backup_YYYYMMDD_HHMMSS.sql` - PostgreSQL database dump
- **Data Backup:** `mattermost_data_backup_YYYYMMDD_HHMMSS.tar.gz` - Mattermost application data and files  
- **Config Backup:** `mattermost_config_backup_YYYYMMDD_HHMMSS.tar.gz` - Configuration files
- **Summary:** `backup_summary_YYYYMMDD_HHMMSS.txt` - Backup verification report

## Backup Locations

**Local Backups:**
- **Daily Backups:** `/home/ubuntu/backups/daily/YYYYMMDD_HHMMSS/`
- **Weekly Backups:** `/home/ubuntu/backups/weekly/YYYYMMDD_HHMMSS/`

**Cloud Backups:**
- **Daily:** `swissbackup:mattermost-backups/daily/YYYYMMDD_HHMMSS/`
- **Weekly:** `swissbackup:mattermost-backups/weekly/YYYYMMDD_HHMMSS/`

Each backup contains the same structure:
- `database/mattermost_db_backup_YYYYMMDD_HHMMSS.sql`
- `data/mattermost_data_backup_YYYYMMDD_HHMMSS.tar.gz`
- `config/mattermost_config_backup_YYYYMMDD_HHMMSS.tar.gz`
- `backup_summary_YYYYMMDD_HHMMSS.txt`

## Prerequisites

- Existing Mattermost Docker setup running
- Backup files available locally or accessible via rclone
- Administrative access to the server
- rclone configured for SwissBackup (if restoring from cloud)

## Restoration Process

### Step 0: Download Backup from SwissBackup (if needed)

If you need to restore from cloud storage instead of local backups:

```bash
# List available backup types and directories
rclone lsf swissbackup:mattermost-backups --dirs-only

# List daily backups
rclone lsf swissbackup:mattermost-backups/daily --dirs-only

# List weekly backups  
rclone lsf swissbackup:mattermost-backups/weekly --dirs-only

# Download specific backup (choose daily or weekly)
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Example: Use latest or desired backup date
rclone sync swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE /home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE --progress

# Verify download
ls -la /home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE/

# Alternative: Use the rclone manager script for easier browsing
cd ~/docker/scripts
./rclone-manager.sh list
./rclone-manager.sh details $BACKUP_DATE
```

### Step 1: Choose and Verify Backup

Select the backup you want to restore from:

```bash
# List available local backups
ls -la /home/ubuntu/backups/daily/
ls -la /home/ubuntu/backups/weekly/

# Choose backup directory and type
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Replace with your chosen backup
BACKUP_DIR="/home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE"

# Verify backup completeness
echo "Checking backup: $BACKUP_DIR"
ls -la "$BACKUP_DIR/"
ls -la "$BACKUP_DIR/database/"
ls -la "$BACKUP_DIR/data/"
ls -la "$BACKUP_DIR/config/"

# Check backup summary if available
if [ -f "$BACKUP_DIR/backup_summary_$BACKUP_DATE.txt" ]; then
    cat "$BACKUP_DIR/backup_summary_$BACKUP_DATE.txt"
fi
```

### Step 2: Stop Mattermost Services

First, stop the Mattermost application while keeping the database running for restoration:

```bash
cd /home/ubuntu/docker

# Stop only the Mattermost container
sudo docker stop docker-mattermost-1

# Verify only postgres and nginx are running
sudo docker ps
```

### Step 2: Stop Mattermost Services

First, stop the Mattermost application while keeping the database running for restoration:

```bash
cd /home/ubuntu/docker

# Stop only the Mattermost container
sudo docker stop docker-mattermost-1

# Verify only postgres and nginx are running
sudo docker ps
```

### Step 3: Backup Current Data (Safety Measure)

Before restoring, create a backup of the current installation:

```bash
# Backup current Mattermost data
sudo tar -czf /home/ubuntu/current_mattermost_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  ./volumes/app/mattermost/

# Backup current database
sudo docker exec docker-postgres-1 pg_dumpall -U mmuser > \
  /home/ubuntu/current_db_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Step 4: Restore Database from Backup

Restore the PostgreSQL database from the backup file:

```bash
# Set backup directory variable (from Step 1)
BACKUP_DIR="/home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE"

# Clear current database
sudo docker exec -it docker-postgres-1 psql -U mmuser -d postgres -c "DROP DATABASE IF EXISTS mattermost;"
sudo docker exec -it docker-postgres-1 psql -U mmuser -d postgres -c "CREATE DATABASE mattermost;"

# Copy backup file to container for easier access
sudo docker cp "$BACKUP_DIR/database/mattermost_db_backup_$BACKUP_DATE.sql" docker-postgres-1:/tmp/

# Restore the database
sudo docker exec -i docker-postgres-1 psql -U mmuser -d mattermost < "$BACKUP_DIR/database/mattermost_db_backup_$BACKUP_DATE.sql"

# Alternative method if the above doesn't work:
# sudo docker exec -i docker-postgres-1 psql -U mmuser -d mattermost -f /tmp/mattermost_db_backup_$BACKUP_DATE.sql
```

### Step 5: Restore Mattermost Data Files

Replace current Mattermost data with backup data:

```bash
# Stop nginx temporarily to avoid conflicts
sudo docker stop nginx_mattermost

# Remove current data (we have backup from Step 3)
sudo rm -rf ./volumes/app/mattermost/data/*
sudo rm -rf ./volumes/app/mattermost/logs/*
sudo rm -rf ./volumes/app/mattermost/plugins/*

# Extract backup data
sudo tar -xzf "$BACKUP_DIR/data/mattermost_data_backup_$BACKUP_DATE.tar.gz" -C ./volumes/app/mattermost/ --strip-components=1

# Fix ownership for Mattermost container (user 2000)
sudo chown -R 2000:2000 ./volumes/app/mattermost/

echo "Data restoration completed from: $BACKUP_DIR/data/"
```

### Step 6: Restore Configuration Files

Restore the Mattermost configuration:

```bash
# Backup current config as additional safety measure
sudo cp ./volumes/app/mattermost/config/config.json ./volumes/app/mattermost/config/config.json.backup

# Extract configuration backup
sudo tar -xzf "$BACKUP_DIR/config/mattermost_config_backup_$BACKUP_DATE.tar.gz" -C ./volumes/app/mattermost/ --strip-components=1

# Fix ownership
sudo chown -R 2000:2000 ./volumes/app/mattermost/config/

echo "Configuration restored from: $BACKUP_DIR/config/"
```

### Step 7: Update Configuration (if needed)

### Step 7: Update Configuration (if needed)

Verify and update the restored Mattermost configuration to match your current environment:

```bash
# Check current configuration
sudo cat ./volumes/app/mattermost/config/config.json | grep -A 5 -B 5 "DataSource\|SiteURL"

# If needed, update database connection string and site URL using the config manager
./scripts/config-manager.sh

# Or manually verify key settings:
# - SqlSettings.DataSource should be: "postgres://mmuser:mmuser_password@postgres:5432/mattermost?sslmode=disable&connect_timeout=10"
# - ServiceSettings.SiteURL should be: "https://mattermost.iaqi.org"
# - FileSettings.Directory should be: "./data/"
```

### Step 8: Restart All Services

Start all containers using Docker Compose:

```bash
# Change ownership back to Mattermost container user
sudo chown -R 2000:2000 ./volumes/app/mattermost/

# Start all services with Docker Compose
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Verify all containers are running
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Check Mattermost logs for any issues
sudo docker logs docker-mattermost-1 --tail 20
```

### Step 9: Verify Restoration

Confirm the restoration was successful:

```bash
# Check Mattermost container health
sudo docker ps | grep mattermost

# Check application logs
sudo docker logs docker-mattermost-1 --tail 50

# Test database connectivity
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "\dt" | head -10

# Verify backup restore details
echo "Restored from backup: $BACKUP_DATE"
echo "Database: $BACKUP_DIR/database/mattermost_db_backup_$BACKUP_DATE.sql"
echo "Data: $BACKUP_DIR/data/mattermost_data_backup_$BACKUP_DATE.tar.gz"
echo "Config: $BACKUP_DIR/config/mattermost_config_backup_$BACKUP_DATE.tar.gz"

# Access Mattermost web interface
echo "Visit: https://mattermost.iaqi.org"
```

## Cloud Backup Management

### Listing Available Cloud Backups

```bash
# List all backup types in SwissBackup
rclone lsf swissbackup:mattermost-backups --dirs-only

# List daily backup directories
rclone lsf swissbackup:mattermost-backups/daily --dirs-only

# List weekly backup directories  
rclone lsf swissbackup:mattermost-backups/weekly --dirs-only

# Get detailed listing with sizes and dates for daily backups
rclone ls swissbackup:mattermost-backups/daily

# Get detailed listing for weekly backups
rclone ls swissbackup:mattermost-backups/weekly

# Check specific backup contents
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Replace with desired backup
rclone ls swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE

# Use the backup manager script for easier browsing
cd ~/docker/scripts
./rclone-manager.sh list
```

### Downloading Specific Files

```bash
# Set backup type and date
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Replace with desired backup

# Download only database backup
rclone copy swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE/database/ /home/ubuntu/temp-restore/database/

# Download only data backup  
rclone copy swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE/data/ /home/ubuntu/temp-restore/data/

# Download only config backup
rclone copy swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE/config/ /home/ubuntu/temp-restore/config/
```

### Verifying Cloud Backup Integrity

```bash
# Set backup type and date
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Replace with desired backup

# Download and check backup summary
rclone copy swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE/backup_summary_$BACKUP_DATE.txt /tmp/
cat /tmp/backup_summary_$BACKUP_DATE.txt

# Compare file sizes between local and cloud
echo "Local backup size:"
du -sh /home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE/ 2>/dev/null || echo "Not available locally"

echo "Cloud backup size:"
rclone size swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE
```

## Troubleshooting

### SwissBackup Connection Issues

If you can't access SwissBackup:

```bash
# Test rclone connection
rclone config show swissbackup

# Test connectivity
rclone lsf swissbackup:mattermost-backups --dirs-only

# If connection fails, reconfigure rclone
rclone config
```

### Database Connection Issues

If Mattermost can't connect to the database:

```bash
# Check database exists and has tables
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "\l"
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "\dt"

# Verify database user permissions
sudo docker exec docker-postgres-1 psql -U mmuser -d postgres -c "\du"
```

### Configuration Issues

If configuration doesn't match:

```bash
# Use the config manager for safe editing
./scripts/config-manager.sh

# Or edit config.json manually
sudo nano ./volumes/app/mattermost/config/config.json

# Key settings to verify:
# - SqlSettings.DataSource
# - ServiceSettings.SiteURL  
# - FileSettings.Directory (should be "./data/")
```

### Backup File Issues

If backup files seem corrupted or incomplete:

```bash
# Check backup summary for verification
cat "$BACKUP_DIR/backup_summary_$BACKUP_DATE.txt"

# Verify archive integrity
tar -tzf "$BACKUP_DIR/data/mattermost_data_backup_$BACKUP_DATE.tar.gz" >/dev/null && echo "Data archive OK" || echo "Data archive corrupted"
tar -tzf "$BACKUP_DIR/config/mattermost_config_backup_$BACKUP_DATE.tar.gz" >/dev/null && echo "Config archive OK" || echo "Config archive corrupted"

# Check database backup
head -20 "$BACKUP_DIR/database/mattermost_db_backup_$BACKUP_DATE.sql"

# Try an alternative backup date if current one is problematic
ls -la /home/ubuntu/backups/
```

### Permission Issues

If Mattermost can't access files:

```bash
# Fix ownership
sudo chown -R 2000:2000 ./volumes/app/mattermost/

# Check current permissions
ls -la ./volumes/app/mattermost/
```

### Container Health Issues

If containers won't start:

```bash
# Check detailed logs
sudo docker logs docker-mattermost-1
sudo docker logs docker-postgres-1
sudo docker logs nginx_mattermost

# Restart services using Docker Compose
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Alternative: Restart in specific order if needed
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml stop mattermost nginx
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml start postgres
sleep 10
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml start mattermost
sleep 15
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml start nginx
```

## Post-Restoration Checklist

- [ ] All containers running and healthy
- [ ] Database contains expected tables and data
- [ ] Mattermost web interface accessible
- [ ] User accounts and teams restored
- [ ] File uploads and attachments working
- [ ] Channels and messages visible
- [ ] System settings preserved

## Important Notes

### Data Consistency
- Ensure the backup was taken when Mattermost was stopped to avoid data corruption
- Database and file system backups should be from the same point in time

### Version Compatibility
- Verify the backup is from a compatible Mattermost version
- Database schema should match or be automatically upgraded

### Security Considerations
- Change default passwords after restoration
- Review user permissions and access levels
- Update any hardcoded URLs or certificates

## Rollback Procedure

If restoration fails and you need to rollback:

```bash
# Stop all containers
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down

# Restore original data
sudo rm -rf ./volumes/app/mattermost/*
sudo tar -xzf /home/ubuntu/current_mattermost_backup_*.tar.gz -C ./volumes/app/

# Restore original database
sudo docker exec -i docker-postgres-1 psql -U mmuser -d postgres < /home/ubuntu/current_db_backup_*.sql

# Fix permissions and restart
sudo chown -R 2000:2000 ./volumes/app/mattermost/
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d
```

## Quick Restoration Commands

For experienced users, here's a condensed restoration sequence:

```bash
# Set variables
BACKUP_TYPE="daily"  # or "weekly"
BACKUP_DATE="20250801_020001"  # Replace with desired backup
BACKUP_DIR="/home/ubuntu/backups/$BACKUP_TYPE/$BACKUP_DATE"

# Download from cloud if needed
# rclone sync swissbackup:mattermost-backups/$BACKUP_TYPE/$BACKUP_DATE $BACKUP_DIR --progress

# Stop services and backup current state
cd /home/ubuntu/docker
sudo docker stop docker-mattermost-1
sudo tar -czf /home/ubuntu/current_mattermost_backup_$(date +%Y%m%d_%H%M%S).tar.gz ./volumes/app/mattermost/
sudo docker exec docker-postgres-1 pg_dumpall -U mmuser > /home/ubuntu/current_db_backup_$(date +%Y%m%d_%H%M%S).sql

# Restore database
sudo docker exec -it docker-postgres-1 psql -U mmuser -d postgres -c "DROP DATABASE IF EXISTS mattermost; CREATE DATABASE mattermost;"
sudo docker exec -i docker-postgres-1 psql -U mmuser -d mattermost < "$BACKUP_DIR/database/mattermost_db_backup_$BACKUP_DATE.sql"

# Restore data and config
sudo rm -rf ./volumes/app/mattermost/data/* ./volumes/app/mattermost/logs/* ./volumes/app/mattermost/plugins/*
sudo tar -xzf "$BACKUP_DIR/data/mattermost_data_backup_$BACKUP_DATE.tar.gz" -C ./volumes/app/mattermost/ --strip-components=1
sudo tar -xzf "$BACKUP_DIR/config/mattermost_config_backup_$BACKUP_DATE.tar.gz" -C ./volumes/app/mattermost/ --strip-components=1
sudo chown -R 2000:2000 ./volumes/app/mattermost/

# Restart all services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d
```

---

**Restoration Guide Updated:** August 1, 2025  
**Backup Source:** Local `/home/ubuntu/backups/{daily,weekly}/` and SwissBackup `swissbackup:mattermost-backups/{daily,weekly}/`  
**Target Installation:** Mattermost 10.5.2 Enterprise Edition
