# Mattermost Database and Data Restoration Guide

This guide documents the process of restoring a Mattermost instance from backups, including PostgreSQL database and Mattermost data files.

## Backup Files Overview

- **Database Backup:** `all_databases_backup.sql` - PostgreSQL cluster dump
- **Data Backup:** `mattermost_data.tar.gz` - Mattermost application data and files

## Prerequisites

- Existing Mattermost Docker setup running
- Backup files available in `/home/ubuntu/db_backup/`
- Administrative access to the server

## Restoration Process

### Step 1: Stop Mattermost Services

First, stop the Mattermost application while keeping the database running for restoration:

```bash
cd /home/ubuntu/docker

# Stop only the Mattermost container
sudo docker stop docker-mattermost-1

# Verify only postgres and nginx are running
sudo docker ps
```

### Step 2: Backup Current Data (Safety Measure)

Before restoring, create a backup of the current installation:

```bash
# Backup current Mattermost data
sudo tar -czf /home/ubuntu/current_mattermost_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  ./volumes/app/mattermost/

# Backup current database
sudo docker exec docker-postgres-1 pg_dumpall -U mmuser > \
  /home/ubuntu/current_db_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Step 3: Clear Current Database

Remove existing database content to prepare for restoration:

```bash
# Connect to PostgreSQL and drop/recreate the database
sudo docker exec -it docker-postgres-1 psql -U mmuser -d postgres -c "DROP DATABASE IF EXISTS mattermost;"
sudo docker exec -it docker-postgres-1 psql -U mmuser -d postgres -c "CREATE DATABASE mattermost;"
```

### Step 4: Restore Database from Backup

Restore the PostgreSQL database from the backup file:

```bash
# Copy backup file to container for easier access
sudo docker cp /home/ubuntu/db_backup/all_databases_backup.sql docker-postgres-1:/tmp/

# Restore the database
sudo docker exec -i docker-postgres-1 psql -U mmuser -d postgres < /home/ubuntu/db_backup/all_databases_backup.sql

# Alternative method if the above doesn't work:
# sudo docker exec -i docker-postgres-1 psql -U mmuser -d postgres -f /tmp/all_databases_backup.sql
```

### Step 5: Restore Mattermost Data Files

Replace current Mattermost data with backup data:

```bash
# Stop nginx temporarily to avoid conflicts
sudo docker stop nginx_mattermost

# Remove current data (we have backup from Step 2)
sudo rm -rf ./volumes/app/mattermost/*

# Extract backup data
cd ./volumes/app/mattermost/
sudo tar -xzf /home/ubuntu/db_backup/mattermost_data.tar.gz --strip-components=1

# Fix ownership for Mattermost container (user 2000)
sudo chown -R 2000:2000 /home/ubuntu/docker/volumes/app/mattermost/

# Return to docker directory
cd /home/ubuntu/docker
```

### Step 6: Update Configuration

Ensure the restored Mattermost configuration matches your current environment:

```bash
# Check current configuration
sudo cat ./volumes/app/mattermost/config/config.json | grep -A 5 -B 5 "DataSource\|SiteURL"

# If needed, update database connection string and site URL
# The database connection should match your .env file settings:
# "postgres://mmuser:mmuser_password@postgres:5432/mattermost?sslmode=disable&connect_timeout=10"
# SiteURL should be: "https://mattermost.iaqi.org"
```

### Step 7: Restart All Services

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

### Step 8: Verify Restoration

Confirm the restoration was successful:

```bash
# Check Mattermost container health
sudo docker ps | grep mattermost

# Check application logs
sudo docker logs docker-mattermost-1 --tail 50

# Test database connectivity
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "\dt" | head -10

# Access Mattermost web interface
echo "Visit: https://mattermost.iaqi.org"
```

## Troubleshooting

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
# Edit config.json manually
sudo nano ./volumes/app/mattermost/config/config.json

# Key settings to verify:
# - SqlSettings.DataSource
# - ServiceSettings.SiteURL
# - FileSettings.Directory (should be "./data/")
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

---

**Restoration Guide Created:** July 22, 2025  
**Source Backup Location:** `/home/ubuntu/db_backup/`  
**Target Installation:** Mattermost 10.5.2 Enterprise Edition
