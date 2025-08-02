# Mattermost Docker Setup Guide

This document summarizes the steps taken to set up a Mattermost server using Docker with nginx reverse proxy and Let's Encrypt SSL certificates.

## Prerequisites

- Ubuntu server with Docker and Docker Compose installed, following https://docs.docker.com/engine/install/ubuntu/ 
- Domain name pointing to your server (mattermost.iaqi.org)
- Port 80 and 443 accessible from the internet (open these two ports up on the infomaniak management portal)

## Initial Setup

### 1. Clone and Configure
Following the official instructions on https://docs.mattermost.com/deployment-guide/server/containers/install-docker.html, tweaked for the IAQI mattermost server.

```bash
# Clone 
git clone https://github.com/IAQI/mattermost-docker.git docker

# Navigate to the docker directory containing the mattermost-docker setup
cd /home/ubuntu/docker

# Create .env configuation file from IAQI template
cp env.IAQI .env

# Review the .env configuration file
# Key settings configured:
# - DOMAIN=mattermost.iaqi.org
# - POSTGRES credentials
# - SSL certificate paths
# - Mattermost image and settings
```

### 2. Environment Configuration

The `.env` file was configured with:

```bash
# Domain configuration
DOMAIN=mattermost.iaqi.org

# Database settings
POSTGRES_USER=mmuser
POSTGRES_PASSWORD=mmuser_password
POSTGRES_DB=mattermost

# SSL Certificate paths
CERT_PATH=./certs/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
KEY_PATH=./certs/etc/letsencrypt/live/${DOMAIN}/privkey.pem

# Mattermost configuration
MATTERMOST_IMAGE=mattermost-enterprise-edition
MATTERMOST_IMAGE_TAG=10.5.2
MM_SERVICESETTINGS_SITEURL=https://${DOMAIN}
```

## SSL Certificate Setup

### 3. Issue Initial Let's Encrypt Certificate

```bash
# Stop any running containers to free port 80
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down

# Issue certificate using the provided script
./scripts/issue-certificate.sh -d mattermost.iaqi.org -o /home/ubuntu/docker/certs
```

### 4. Fix Certificate Permissions

The nginx container runs as user ubuntu, so certificate files needed proper ownership:

```bash
# Change ownership of certificate files to nginx user
sudo chown -R ubuntu:ubuntu ./certs/
```


## Service Deployment

### 5. Deploy Mattermost Stack

```bash
# Start all services (postgres, mattermost, nginx)
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Verify all containers are running
sudo docker ps

# Check container logs if needed
sudo docker logs nginx_mattermost
sudo docker logs docker-mattermost-1
sudo docker logs docker-postgres-1
```

## Troubleshooting Issues Encountered

### SSL Certificate Loading Issues

**Problem:** nginx container kept restarting with SSL certificate errors:
```
nginx: [emerg] cannot load certificate key "/key.pem": PEM_read_bio_PrivateKey() failed
```

**Solution:** Fixed file ownership permissions:
```bash
sudo chown -R 101:101 ./certs/
```

### Docker Permission Issues

**Problem:** Permission denied accessing Docker daemon socket.

**Solutions:**
1. Add user to docker group: `sudo usermod -aG docker $USER`
2. Use sudo for docker commands: `sudo docker compose ...`

### Certificate Renewal Issues

**Problem:** CAA records preventing Let's Encrypt renewal:
```
Error finalizing order :: rechecking caa: During secondary validation: Secondary validation RPC failed
```

**Current Status:** 
- Certificate valid until October 19, 2025
- Need to fix CAA DNS records for future renewals (see CAA Records section below)
- Clean up broken renewal config: `sudo rm /home/ubuntu/docker/certs/etc/letsencrypt/renewal/mattermost.iaqi.org.conf`

## Understanding CAA Records

**CAA (Certificate Authority Authorization)** records are DNS security records that specify which Certificate Authorities can issue certificates for your domain.

### Current CAA Status
Your domain uses Infomaniak DNS but has no CAA records currently set. The renewal failure was likely due to temporary validation issues.

### Recommended CAA Records
Add these records in your Infomaniak DNS management to explicitly allow Let's Encrypt:

```dns
iaqi.org. CAA 0 issue "letsencrypt.org"
iaqi.org. CAA 0 issuewild "letsencrypt.org"
```

### Steps to Add CAA Records in Infomaniak:
1. Log into Infomaniak control panel
2. Navigate to DNS management for `iaqi.org`
3. Add CAA record: Type=CAA, Name=@, Value=`0 issue "letsencrypt.org"`
4. Add second CAA record: Type=CAA, Name=@, Value=`0 issuewild "letsencrypt.org"`

This prevents unauthorized certificate issuance and ensures Let's Encrypt can renew your certificates.

## Final Configuration

### 6. Verify Setup

```bash
# Check all containers are healthy
sudo docker compose ps -a

# Expected output should show:
# - postgres: Up
# - mattermost: Up (healthy)
# - nginx: Up
```

### 7. Access Mattermost

- **URL:** https://mattermost.iaqi.org
- **SSL:** Let's Encrypt certificate (valid until Oct 19, 2025)
- **Reverse Proxy:** nginx handling SSL termination
- **Database:** PostgreSQL 13-alpine

## Directory Structure

```
/home/ubuntu/docker/
├── .env                           # Environment configuration
├── docker-compose.yml            # Main docker-compose file
├── docker-compose.nginx.yml      # nginx reverse proxy config
├── nginx/
│   └── conf.d/
│       └── default.conf          # nginx SSL configuration
├── scripts/
│   └── issue-certificate.sh      # Let's Encrypt certificate script
├── certs/
│   └── etc/letsencrypt/          # SSL certificates
└── volumes/
    ├── app/mattermost/           # Mattermost data
    └── db/                       # PostgreSQL data
```

## Maintenance Notes

### Certificate Renewal

Current certificate expires: **October 19, 2025**

For future renewals:
1. Fix CAA DNS records to allow letsencrypt.org
2. Use the renewal script or manual certbot commands
3. Ensure proper file permissions (101:101) after renewal

### Backup Considerations

Important directories to backup:
- `./volumes/app/mattermost/` - Mattermost data and configuration
- `./volumes/db/` - PostgreSQL database
- `./certs/` - SSL certificates

### Security Notes

- nginx container runs in read-only mode with limited privileges
- Database uses non-root user (mmuser)
- SSL configured with modern TLS protocols (1.2, 1.3)
- Containers restart automatically unless stopped

## Useful Commands

```bash
# View logs
sudo docker logs nginx_mattermost --tail 20
sudo docker logs docker-mattermost-1 --tail 20

# Restart services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart

# Stop all services
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml down

# Update Mattermost version (edit .env then):
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml pull
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d

# Check certificate expiry
sudo openssl x509 -in ./certs/etc/letsencrypt/live/mattermost.iaqi.org/fullchain.pem -noout -dates
```

## Configuration Management

### Safe Config Editing

Mattermost configuration files require special ownership to work with Docker containers. Use the config manager script for safe editing:

```bash
# Check current config file status
./scripts/config-manager.sh status

# Enable editing (changes ownership to ubuntu user)
./scripts/config-manager.sh edit

# Edit the config file in VS Code or nano
# File: /home/ubuntu/docker/volumes/app/mattermost/config/config.json

# Validate JSON syntax
./scripts/config-manager.sh validate

# Restore proper ownership (required before restart)
./scripts/config-manager.sh restore

# Apply changes by restarting Mattermost
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart mattermost
```

**Complete workflow:**
```bash
# 1. Enable editing
./scripts/config-manager.sh edit

# 2. Make changes in VS Code
# 3. Validate changes
./scripts/config-manager.sh validate

# 4. Restore ownership  
./scripts/config-manager.sh restore

# 5. Apply changes
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart mattermost
```

## Troubleshooting

### Memory-Related Issues and Crashes

**Problem:** Mattermost server crashes or becomes unresponsive, especially during backup operations or peak usage.

**Root Causes Identified:**
- Insufficient memory (1.9GB RAM without swap space)
- Verbose DEBUG logging consuming excessive resources
- Memory pressure during backup operations

**Symptoms:**
- Services restart unexpectedly
- Container health checks failing
- PostgreSQL connection errors: `FATAL: database "mmuser" does not exist`
- High memory usage without swap space

**Solutions Applied:**

#### 1. Add Swap Space (Critical)
```bash
# Create 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
sudo swapon --show
free -h
```

#### 2. Reduce Log Verbosity
Edit `/home/ubuntu/docker/volumes/app/mattermost/config/config.json`:
```json
"LogSettings": {
    "ConsoleLevel": "INFO",          // Changed from "DEBUG"
    "EnableWebhookDebugging": false, // Changed from true
    "FileLevel": "INFO"
}
```

#### 3. Monitor System Resources
```bash
# Check memory usage
free -h

# Check container resource usage
sudo docker stats --no-stream

# Check swap usage
swapon --show

# Monitor during backup operations
watch -n 5 'free -h && echo "---" && sudo docker stats --no-stream'
```

#### 4. Optimize Backup Schedule
- Scheduled backups run at 2 AM (weekdays) and 1 AM (Sunday) to avoid peak usage
- Avoid manual backups during business hours
- Monitor backup logs: `tail -f /var/log/mattermost-backup.log`

#### 5. Database Connection Verification
```bash
# Verify database exists and is accessible
sudo docker exec docker-postgres-1 psql -U mmuser -l

# Check database connection from Mattermost config
grep -A 2 -B 2 "DataSource" /home/ubuntu/docker/volumes/app/mattermost/config/config.json
```

### Performance Monitoring

**Commands for ongoing monitoring:**
```bash
# System overview
htop

# Memory usage trend
watch -n 10 'date && free -h'

# Container health
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml ps

# Service logs
sudo docker compose -f docker-compose.yml -f docker-compose.nginx.yml logs --tail=50 mattermost
```

**Key Metrics to Watch:**
- Memory usage should stay below 80% of available RAM
- Swap usage should be minimal during normal operations
- Container restart counts should remain stable

### Common Issues

#### Issue: High Memory Usage
**Solution:** Monitor memory with `free -h`. If consistently above 80%, consider upgrading server or optimizing plugins.

#### Issue: Services Not Starting
**Solution:** Check Docker logs and ensure sufficient disk space and memory.

#### Issue: Backup Failures
**Solution:** Verify backup script permissions and available disk space. Check `/var/log/mattermost-backup.log`.

#### Issue: SSL Certificate Problems
**Solution:** Verify certificate expiry and renewal process. See SSL section above.

---

**Troubleshooting Guide Updated:** July 24, 2025  
**Memory Issues Resolved:** Added 2GB swap, reduced logging verbosity  
**System Stability:** ✅ Improved with resource monitoring

---

**Setup completed successfully on:** July 22, 2025  
**Mattermost version:** 10.5.2 Enterprise Edition  
**Domain:** mattermost.iaqi.org  
**SSL Status:** ✅ Valid until October 19, 2025
