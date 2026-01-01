# Mattermost Upgrade Guide

This guide provides step-by-step instructions for upgrading your Mattermost Docker installation.

## Upgrade History

### January 1, 2026: 10.5.2 → 10.11.9
- **Duration:** ~3 minutes downtime
- **Issues:** None
- **Notes:** Maintenance mode enabled during upgrade. All services healthy post-upgrade.
- **Resource Usage:** Mattermost container using ~500MB RAM (25% of available)

## Pre-Upgrade Checklist

Before starting the upgrade process:

- [ ] Review [Mattermost release notes](https://docs.mattermost.com/about/release-notes.html) for breaking changes
- [ ] Check current version: `sudo docker exec docker-mattermost-1 mattermost version`
- [ ] Verify system resources are adequate (see Resource Requirements below)
- [ ] Schedule upgrade during low-traffic period
- [ ] Notify users of planned maintenance window
- [ ] Ensure recent backup exists (verify `/home/ubuntu/backups/`)

### Resource Requirements

**Minimum System State:**
- Available memory: >500MB free RAM
- Swap space: 2GB configured and active
- Disk space: >5GB free in `/home/ubuntu/docker/volumes/`
- CPU: Low load (<50% average)

**Check system status:**
```bash
# Verify memory and swap
free -h

# Check disk space
df -h /home/ubuntu

# Monitor system load
uptime
```

## System Updates

### 1. Update Ubuntu System

**Run system updates alongside Mattermost upgrades:**

```bash
# Update package lists
sudo apt update

# View what will be updated
sudo apt list --upgradable

# Apply all updates
sudo apt upgrade -y

# Check if reboot needed (defer until after Mattermost upgrade)
if [ -f /var/run/reboot-required ]; then
    echo "⚠️  Reboot will be needed after Mattermost upgrade"
    cat /var/run/reboot-required.pkgs
else
    echo "✓ No reboot required"
fi
```

**Note:** If kernel updates were installed, plan to reboot after completing the Mattermost upgrade.

## Backup Before Upgrade

### 2. Create Full Backup

**Automated backup (recommended):**
```bash
# Run the backup script (with verbose output)
cd /home/ubuntu/docker
./scripts/backup-mattermost.sh --verbose

# Verify backup completed successfully
ls -lh /home/ubuntu/backups/daily/ | tail -5
tail -20 /home/ubuntu/logs/mattermost-backup.log
```

**Manual backup (if needed):**
```bash
# Create backup directory with timestamp
BACKUP_DIR="/home/ubuntu/backups/manual-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup Mattermost data
sudo cp -a /home/ubuntu/docker/volumes/app/mattermost/ "$BACKUP_DIR/mattermost/"

# Backup database
sudo docker exec docker-postgres-1 pg_dump -U mmuser mattermost > "$BACKUP_DIR/mattermost-db.sql"

# Backup configuration
cp /home/ubuntu/docker/.env "$BACKUP_DIR/"
cp /home/ubuntu/docker/volumes/app/mattermost/config/config.json "$BACKUP_DIR/"

# Verify backup size
du -sh "$BACKUP_DIR"
```

### 3. Verify Backup Integrity

```bash
# Check database backup
head -20 "$BACKUP_DIR/mattermost-db.sql"
tail -20 "$BACKUP_DIR/mattermost-db.sql"

# Verify config files
cat "$BACKUP_DIR/.env" | grep MATTERMOST_IMAGE_TAG
cat "$BACKUP_DIR/config.json" | python3 -m json.tool > /dev/null && echo "✓ Valid JSON"
```

## Upgrade Process

### 4. Update Version in .env File

```bash
# Navigate to docker directory
cd /home/ubuntu/docker

# Check available versions at https://hub.docker.com/r/mattermost/mattermost-enterprise-edition/tags

# Edit .env file
nano .env

# Update MATTERMOST_IMAGE_TAG to desired version
# Example: MATTERMOST_IMAGE_TAG=10.6.0
```

### 5. Enable Maintenance Mode

```bash
# Enable maintenance mode to show users a maintenance page
cd /home/ubuntu/docker
touch nginx/conf.d/.maintenance

# Find the nginx container name (usually nginx_mattermost or docker-nginx-1)
sudo docker compose ps | grep nginx

# Reload nginx to apply maintenance mode (adjust container name if different)
sudo docker exec nginx_mattermost nginx -s reload
```

### 6. Enable Config Editing Mode

```bash
# Allow editing of config file
./scripts/config-manager.sh edit

# Check current configuration
./scripts/config-manager.sh status
```

### 7. Pull New Docker Image

```bash
# Pull the new Mattermost image
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml pull mattermost

# Verify new image downloaded
sudo docker images | grep mattermost
```

### 8. Stop Services Gracefully

```bash
# Stop Mattermost and nginx (keep database running)
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml stop mattermost nginx

# Verify services stopped
sudo docker compose ps
```

### 9. Restore Config Permissions

```bash
# Restore proper ownership before starting new container
./scripts/config-manager.sh restore

# Verify permissions
./scripts/config-manager.sh status
```

### 10. Start Updated Services

```bash
# Start all services with new version
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Wait for services to start (30-60 seconds)
sleep 30
```

### 11. Disable Maintenance Mode

```bash
# Remove maintenance mode file
cd /home/ubuntu/docker
rm nginx/conf.d/.maintenance

# Reload nginx to restore normal operation
sudo docker exec nginx_mattermost nginx -s reload
```

### 12. Verify Upgrade

```bash
# Check Mattermost version
sudo docker exec docker-mattermost-1 mattermost version

# Verify web access
curl -I https://mm.iaqi.org

# Check service health (all should show 'Up' or 'healthy')
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps
```

## Post-Upgrade Verification

### 13. System Health Checks

```bash
# Check all containers are running
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Expected output:
# - postgres: Up
# - mattermost: Up (healthy)
# - nginx: Up

# Monitor resource usage
sudo docker stats --no-stream

# Check logs for errors
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs --tail=50 mattermost | grep -i error
```

### 14. Functional Testing

**Admin Console:**
- [ ] Login to admin account
- [ ] Navigate to System Console
- [ ] Verify version number in About section
- [ ] Check for any configuration warnings

**User Testing:**
- [ ] Test user login
- [ ] Send test messages in channels
- [ ] Upload a file attachment
- [ ] Test @mentions and notifications
- [ ] Verify search functionality

**Integration Testing:**
- [ ] Test webhooks (if configured)
- [ ] Verify OAuth/SAML login (if configured)
- [ ] Check plugin functionality
- [ ] Test mobile app connectivity

### 15. Performance Monitoring

```bash
# Monitor system resources for 10 minutes after upgrade
watch -n 30 'date && free -h && echo "---" && sudo docker stats --no-stream'

# Check for memory leaks or unusual behavior
# Memory usage should stabilize within 5-10 minutes

# Monitor logs for repeated errors
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs -f --tail=100
```

### 16. Reboot System (If Required)

**If system updates installed kernel packages:**

```bash
# Check if reboot is required
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required - schedule during low-usage time"
    
    # When ready to reboot:
    # 1. Enable maintenance mode (optional)
    cd /home/ubuntu/docker
    touch nginx/conf.d/.maintenance
    sudo docker exec nginx_mattermost nginx -s reload
    
    # 2. Reboot
    sudo reboot
    
    # 3. After reboot, verify services auto-started:
    # docker ps
    # curl -I https://mm.iaqi.org
    
    # 4. Disable maintenance mode
    # rm nginx/conf.d/.maintenance
    # sudo docker exec nginx_mattermost nginx -s reload
fi
```

**Note:** Docker containers configured with `restart: unless-stopped` will automatically restart after system reboot.

## Post-Upgrade Cleanup (Optional)

After a successful upgrade, you can free up disk space by removing old Docker images and logs:

### Cleanup Commands

```bash
# 1. Remove old Mattermost image (saves ~1GB)
# Replace version number with the old version you just upgraded from
sudo docker image rm mattermost/mattermost-enterprise-edition:10.5.2

# 2. Clean up system logs (saves ~1.5GB, keeps last 7 days)
sudo journalctl --vacuum-time=7d

# 3. Remove old weekly backups (optional, keeps last 2)
# Only remove backups older than 1 month
ls -lt /home/ubuntu/backups/weekly/ | tail -n +3 | awk '{print $9}' | xargs -I {} rm -rf /home/ubuntu/backups/weekly/{}

# 4. Docker cleanup - remove unused data
sudo docker system prune -f

# 5. Check disk space after cleanup
df -h /
```

### Disk Usage Check

```bash
# View what's using disk space
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10

# Check Docker disk usage
sudo docker system df
```

**Expected space savings:** 2-3GB total

## Rollback Procedure

If the upgrade fails or causes issues:

### 1. Stop Current Version

```bash
cd /home/ubuntu/docker
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down
```

### 2. Restore Previous Version

```bash
# Find your backup directory
ls -lh /home/ubuntu/backups/

# Set backup directory (adjust timestamp)
BACKUP_DIR="/home/ubuntu/backups/manual-20250122-140000"

# Restore .env file (with previous version)
cp "$BACKUP_DIR/.env" /home/ubuntu/docker/.env

# Restore configuration
sudo cp -a "$BACKUP_DIR/mattermost/" /home/ubuntu/docker/volumes/app/

# Restore database (if needed)
sudo docker exec -i docker-postgres-1 psql -U mmuser mattermost < "$BACKUP_DIR/mattermost-db.sql"
```

### 3. Restart Services

```bash
# Pull the old image version
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml pull mattermost

# Start services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Verify rollback
sudo docker exec docker-mattermost-1 mattermost version
```

## Troubleshooting Common Upgrade Issues

### Issue: Container Won't Start After Upgrade

**Symptoms:**
- Mattermost container keeps restarting
- Health check failing

**Solutions:**
```bash
# Check detailed logs
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs mattermost

# Common causes:
# 1. Database migration failed - check postgres logs
sudo docker logs docker-postgres-1

# 2. Config file permissions - restore ownership
./scripts/config-manager.sh restore

# 3. Insufficient memory - check resources
free -h
```

### Issue: Database Migration Errors

**Symptoms:**
- Errors about schema version
- "Database migration failed" messages

**Solutions:**
```bash
# Check database connectivity
sudo docker exec docker-postgres-1 psql -U mmuser -l

# Review migration logs
sudo docker logs docker-mattermost-1 | grep -i migration

# If migration stuck, may need to restore from backup
# See Rollback Procedure above
```

### Issue: Configuration Lost or Reset

**Symptoms:**
- Settings reverted to defaults
- Integrations not working

**Solutions:**
```bash
# Restore config from backup
BACKUP_DIR="/home/ubuntu/backups/manual-20250122-140000"

# Enable editing
./scripts/config-manager.sh edit

# Restore previous config
sudo cp "$BACKUP_DIR/config.json" /home/ubuntu/docker/volumes/app/mattermost/config/

# Validate JSON
./scripts/config-manager.sh validate

# Restore ownership
./scripts/config-manager.sh restore

# Restart Mattermost
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart mattermost
```

### Issue: High Memory Usage After Upgrade

**Symptoms:**
- System becomes slow
- Services restarting
- High swap usage

**Solutions:**
```bash
# Check memory usage
free -h
sudo docker stats

# Reduce log verbosity if needed
./scripts/config-manager.sh edit
# Edit config.json: Set ConsoleLevel to "INFO"
./scripts/config-manager.sh restore

# Clear old Docker images
sudo docker image prune -a

# Monitor and wait for stabilization
watch -n 10 'free -h'
```

## Upgrade Schedule Recommendations

### Minor Version Updates (e.g., 10.5.x → 10.5.y)

- **Frequency:** Monthly or as security patches released
- **Risk Level:** Low
- **Testing:** Basic functional testing
- **Downtime:** 5-10 minutes

### Major Version Updates (e.g., 10.x → 11.x)

- **Frequency:** Quarterly or when needed features released
- **Risk Level:** Medium to High
- **Testing:** Full integration testing required
- **Downtime:** 15-30 minutes
- **Additional Steps:**
  - Review upgrade notes thoroughly
  - Test in staging environment if possible
  - Extended monitoring post-upgrade (24-48 hours)

## Best Practices

1. **Always backup before upgrading** - Automated backups run daily, but create manual backup before major upgrades
2. **Read release notes** - Check for breaking changes and new features
3. **Test in off-hours** - Schedule upgrades during low-traffic periods (suggested: Sunday 1-3 AM)
4. **Monitor after upgrade** - Watch system resources and logs for at least 1 hour
5. **Keep audit trail** - Document upgrade date, version, and any issues encountered
6. **Verify SSL certificates** - Ensure certificates remain valid after upgrade
7. **Update plugins** - Check plugin compatibility with new version

## Emergency Contacts

**If upgrade fails:**
- Rollback to previous version (see Rollback Procedure)
- Check Mattermost community forums
- Review `/home/ubuntu/logs/mattermost-backup.log` for backup status
- Monitor `/home/ubuntu/logs/certbot-renewal.log` for SSL issues

## Post-Upgrade Tasks

- [ ] Update SETUP_GUIDE.md with new version number
- [ ] Document any configuration changes made
- [ ] Notify users that upgrade is complete
- [ ] Monitor system for 24 hours
- [ ] Update incident log if any issues occurred
- [ ] Plan next upgrade cycle

---

**Last Updated:** January 1, 2026  
**Current Mattermost Version:** 10.11.9 Enterprise Edition  
**Last Upgrade:** January 1, 2026 (from 10.5.2 to 10.11.9)  
**Next Recommended Review:** When 10.12.x or 11.x is released
