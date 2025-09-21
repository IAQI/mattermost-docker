# Mattermost Docker Troubleshooting Guide

This guide covers common issues and solutions for the Mattermost Docker deployment.

## Table of Contents

- [Memory and Performance Issues](#memory-and-performance-issues)
- [Container and Service Issues](#container-and-service-issues)
- [Database Issues](#database-issues)
- [SSL and Network Issues](#ssl-and-network-issues)
- [Backup and Restore Issues](#backup-and-restore-issues)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Memory and Performance Issues

### Server Crashes and Instability

**Problem:** Mattermost server crashes randomly, especially during backups or high usage periods.

**Investigation Date:** July 24, 2025  
**Root Cause:** Memory pressure on system with only 1.9GB RAM and no swap space.

#### Symptoms:
- Unexpected service restarts (containers show recent start times)
- Memory usage consistently above 70-80%
- PostgreSQL connection errors during operations
- Slow response times or timeouts

#### Diagnostic Commands:
```bash
# Check current memory usage
free -h

# Check swap status
swapon --show

# Check container resource usage
sudo docker stats --no-stream

# Check service uptime
cd /home/ubuntu/docker
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Check for OOM kills in system logs
sudo dmesg | grep -i "out of memory"
sudo journalctl --since="24h" | grep -i -E "(oom|kill|memory)"
```

#### Solution 1: Identify VS Code Server Memory Usage (Most Common Cause)

**Root Cause Discovered:** VS Code Remote Server is the primary memory consumer, not Mattermost itself.

**Investigation Commands:**
```bash
# Check VS Code server memory usage
ps aux --sort=-%mem | head -10

# Calculate total VS Code memory consumption
ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print "Total VS Code RSS (MB):", sum/1024}'

# Compare with Mattermost memory usage
ps aux | grep -E "mattermost|postgres" | grep -v grep
```

**Typical Memory Usage on 2GB System:**
- VS Code Server: **800-900MB (40-45%)**
- Mattermost: **120-150MB (6-8%)**
- PostgreSQL: **50-100MB (3-5%)**
- System/Other: **200-300MB (10-15%)**
- **Total: 1.2-1.5GB (60-75% of 2GB)**

**VS Code Management Solutions:**
```bash
# Option 1: Kill VS Code server when not needed
pkill -f "vscode-server"

# Option 2: Monitor VS Code processes
watch 'ps aux | grep vscode-server | grep -v grep'

# Option 3: Set up VS Code auto-shutdown (recommended)
# Edit VS Code settings to enable auto-shutdown after inactivity
```

**Connection Drop Prevention:**
- Use screen/tmux for long-running operations
- Monitor VS Code connection stability
- Close VS Code when doing memory-intensive operations

#### Solution 2: Add Swap Space (Also Recommended)
```bash
# Create 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify swap is active
sudo swapon --show
free -h
```

#### Solution 2: Optimize Mattermost Configuration
Edit `/home/ubuntu/docker/volumes/app/mattermost/config/config.json`:
Chris left these as they were. I believe that's not really a problem...

```json
{
  "LogSettings": {
    "ConsoleLevel": "INFO",              // Reduced from DEBUG
    "EnableWebhookDebugging": false,     // Disabled to reduce overhead
    "FileLevel": "INFO"
  },
  "SqlSettings": {
    "MaxOpenConns": 200,                 // Reduced from 300
    "MaxIdleConns": 10                   // Reduced from 20
  }
}
```

After changes, restart Mattermost:
```bash
cd /home/ubuntu/docker
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart mattermost
```

#### Solution 3: VS Code Server Memory Management

**Root Cause Discovered:** VS Code Remote Server is often the primary memory consumer, not Mattermost itself.

**Investigation Commands:**
```bash
# Check VS Code server memory usage
./scripts/vscode-manager.sh status

# Calculate total VS Code memory consumption  
ps aux | grep -E "vscode-server" | grep -v grep | awk '{sum += $6} END {print "Total VS Code RSS (MB):", sum/1024}'

# Compare with Mattermost memory usage
ps aux | grep -E "mattermost|postgres" | grep -v grep
```

**Typical Memory Usage on 2GB System:**
- VS Code Server: **800-900MB (40-45%)**
- Mattermost: **120-150MB (6-8%)**
- PostgreSQL: **50-100MB (3-5%)**
- System/Other: **200-300MB (10-15%)**
- **Total: 1.2-1.5GB (60-75% of 2GB)**

**VS Code Management Solutions:**
```bash
# Check current status
./scripts/vscode-manager.sh status

# Kill VS Code server when not needed (frees ~800MB)
./scripts/vscode-manager.sh kill

# Monitor VS Code memory usage in real-time
./scripts/vscode-manager.sh monitor

# Clean up orphaned processes from connection drops
./scripts/vscode-manager.sh clean

# Set up automatic alerts for high memory usage
./scripts/vscode-manager.sh alert
```

**Connection Drop Prevention:**
- Use screen/tmux for long-running operations
- Monitor VS Code connection stability  
- Close VS Code when doing memory-intensive operations like backups

#### Solution 4: Monitor Resource Usage
```bash
# Real-time monitoring with VS Code detection
watch -n 5 '
echo "=== $(date) ==="
echo "Overall Memory Usage:"
free -h
echo
echo "Top Memory Consumers:"
ps aux --sort=-%mem | head -8
echo
echo "VS Code Server Memory Usage:"
ps aux | grep -E "vscode-server" | grep -v grep | awk "{sum += \$6} END {if(sum>0) print \"VS Code Total:\", sum/1024 \"MB\"; else print \"VS Code: Not running\"}"
echo
echo "Docker Container Stats:"
sudo docker stats --no-stream
'

# Quick VS Code memory check script
echo '#!/bin/bash
VSCODE_MEM=$(ps aux | grep -E "vscode-server" | grep -v grep | awk "{sum += \$6} END {print sum/1024}")
TOTAL_MEM=$(free -m | grep "^Mem:" | awk "{print \$2}")
if [ ! -z "$VSCODE_MEM" ] && (( $(echo "$VSCODE_MEM > 0" | bc -l) )); then
    VSCODE_PERCENT=$(echo "scale=1; $VSCODE_MEM * 100 / $TOTAL_MEM" | bc)
    echo "VS Code using ${VSCODE_MEM}MB (${VSCODE_PERCENT}% of total memory)"
    if (( $(echo "$VSCODE_PERCENT > 35" | bc -l) )); then
        echo "WARNING: VS Code using excessive memory!"
    fi
else
    echo "VS Code server not running"
fi' | sudo tee /usr/local/bin/vscode-memory-check.sh
sudo chmod +x /usr/local/bin/vscode-memory-check.sh

# Enhanced memory alerting that includes VS Code detection
echo '#!/bin/bash
MEMORY_USAGE=$(free | grep Mem | awk "{print (\$3/\$2) * 100.0}")
VSCODE_MEM=$(ps aux | grep -E "vscode-server" | grep -v grep | awk "{sum += \$6} END {print sum/1024}")
TOTAL_MEM=$(free -m | grep "^Mem:" | awk "{print \$2}")

LOG_MSG="Memory: ${MEMORY_USAGE}%"
if [ ! -z "$VSCODE_MEM" ] && (( $(echo "$VSCODE_MEM > 0" | bc -l) )); then
    VSCODE_PERCENT=$(echo "scale=1; $VSCODE_MEM * 100 / $TOTAL_MEM" | bc)
    LOG_MSG="${LOG_MSG}, VS Code: ${VSCODE_MEM}MB (${VSCODE_PERCENT}%)"
fi

if (( $(echo "$MEMORY_USAGE > 85" | bc -l) )); then
    echo "WARNING: High memory usage - ${LOG_MSG} on $(date)" >> /var/log/memory-alerts.log
fi' | sudo tee /usr/local/bin/memory-check.sh
sudo chmod +x /usr/local/bin/memory-check.sh

# Add to cron to run every 15 minutes
echo "*/15 * * * * /usr/local/bin/memory-check.sh" | crontab -
```

## Container and Service Issues

### Services Not Starting

**Diagnostic Steps:**
```bash
# Check container status
cd /home/ubuntu/docker
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Check logs for errors
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs mattermost
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs postgres
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs nginx

# Check disk space
df -h

# Check Docker daemon status
sudo systemctl status docker
```

### Container Health Check Failures

**Check Health Status:**
```bash
# Detailed container inspection
sudo docker inspect docker-mattermost-1 | grep -A 10 -B 5 "Health"

# Manual health check
sudo docker exec docker-mattermost-1 curl -f http://localhost:8065/api/v4/system/ping || echo "Health check failed"
```

## Database Issues

### PostgreSQL Connection Errors

**Common Error:** `FATAL: database "mmuser" does not exist`

**Investigation:**
```bash
# List all databases
sudo docker exec docker-postgres-1 psql -U mmuser -l

# Check Mattermost config database name
grep -A 3 -B 3 "DataSource" /home/ubuntu/docker/volumes/app/mattermost/config/config.json

# Test database connection
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "SELECT current_database();"
```

**Solution:** Ensure config.json DataSource points to correct database name (should be `mattermost`, not `mmuser`).

### Database Performance Issues

**Check Database Performance:**
```bash
# Check active connections
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "SELECT count(*) FROM pg_stat_activity;"

# Check database size
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "SELECT pg_size_pretty(pg_database_size('mattermost'));"

# Check slow queries (if logging enabled)
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "SELECT query, mean_time, calls FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
```

## SSL and Network Issues

### Certificate Problems

**Check Certificate Status:**
```bash
# Check certificate expiry
sudo openssl x509 -in ./certs/etc/letsencrypt/live/mm.iaqi.org-0001/fullchain.pem -noout -dates

# Test SSL connection
openssl s_client -connect mm.iaqi.org:443 -servername mm.iaqi.org < /dev/null

# Check nginx configuration
sudo docker exec nginx_mattermost nginx -t
```

### Network Connectivity Issues

**Check Network Configuration:**
```bash
# Check port bindings
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Test internal connectivity
sudo docker exec docker-mattermost-1 curl -f http://postgres:5432 || echo "Database not reachable"
sudo docker exec nginx_mattermost curl -f http://mattermost:8065/api/v4/system/ping || echo "Mattermost not reachable"

# Check external connectivity
curl -I https://mm.iaqi.org/api/v4/system/ping
```

## Backup and Restore Issues

### Backup Script Failures

**Check Backup Status:**
```bash
# Check backup logs
tail -50 /var/log/mattermost-backup.log

# Test backup script manually
cd /home/ubuntu/docker/scripts
./scripts/backup-mattermost.sh 1 --verbose

# Check backup directory permissions
ls -la /home/ubuntu/backups/
```

### Cloud Backup Issues

**Test Cloud Connectivity:**
```bash
# Test rclone configuration
rclone lsd swissbackup:

# Test cloud backup script
cd /home/ubuntu/docker/scripts
./cloud-backup.sh --dry-run --verbose

# Check cloud backup logs
tail -20 /home/ubuntu/logs/rclone-backup.log
```

## Monitoring and Maintenance

### Regular Health Checks

**Daily Monitoring Script:**
```bash
#!/bin/bash
# Save as /usr/local/bin/mattermost-health-check.sh

echo "=== Mattermost Health Check - $(date) ==="

# Memory usage
echo "Memory Usage:"
free -h | grep -E "(Mem|Swap)"

# Container status
echo -e "\nContainer Status:"
cd /home/ubuntu/docker
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Service health
echo -e "\nService Health:"
curl -s -f https://mm.iaqi.org/api/v4/system/ping && echo "✅ Mattermost API responding" || echo "❌ Mattermost API not responding"

# Database connectivity
sudo docker exec docker-postgres-1 pg_isready -U mmuser && echo "✅ Database responding" || echo "❌ Database not responding"

# Disk usage
echo -e "\nDisk Usage:"
df -h / | tail -1

# Certificate expiry
echo -e "\nSSL Certificate:"
sudo openssl x509 -in ./certs/etc/letsencrypt/live/mm.iaqi.org-0001/fullchain.pem -noout -enddate

echo "=== End Health Check ==="
```

### Performance Baseline

**After fixes applied (July 24, 2025):**
- **Memory:** 1.9GB RAM + 2GB Swap
- **Typical Usage:** 60-70% RAM, minimal swap usage
- **Container Memory:**
  - Mattermost: ~220MB (11%)
  - PostgreSQL: ~66MB (3.4%)
  - Nginx: ~9MB (0.5%)
- **Log Level:** INFO (reduced from DEBUG)

### Recommended Monitoring

**Set up automated monitoring:**
```bash
# Add to crontab for daily health checks
echo "0 8 * * * /usr/local/bin/mattermost-health-check.sh >> /var/log/mattermost-health.log 2>&1" | crontab -

# Weekly resource usage report
echo "0 9 * * 1 echo '=== Weekly Resource Report ===' >> /var/log/weekly-resources.log && free -h >> /var/log/weekly-resources.log && sudo docker stats --no-stream >> /var/log/weekly-resources.log" | crontab -
```

## Emergency Procedures

### Service Recovery

**If all services are down:**
```bash
cd /home/ubuntu/docker

# Stop all services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down

# Check for conflicts
sudo docker ps -a
sudo docker network ls

# Restart services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Monitor startup
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs -f
```

### Data Recovery

**If database corruption suspected:**
```bash
# Stop Mattermost but keep database running
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml stop mattermost nginx

# Check database integrity
sudo docker exec docker-postgres-1 psql -U mmuser -d mattermost -c "SELECT pg_database_size('mattermost');"

# Restore from backup if needed (see RESTORE_GUIDE.md)
```

---

**Document Updated:** July 24, 2025  
**Issues Resolved:** Memory pressure, service stability  
**Status:** ✅ System stable with swap space and optimized configuration
