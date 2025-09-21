# Scripts Overview

This directory contains various utility scripts for managing the Mattermost Docker deployment. Below is a comprehensive overview of each script's purpose and functionality.

## Certificate Management

### `issue-certificate.sh`
Initial SSL certificate acquisition script using Let's Encrypt certbot in standalone mode.
- Issues new SSL certificates for the Mattermost domain
- Requires Docker services to be stopped (needs port 80)
- Usage: `./issue-certificate.sh -d domain.com -o /path/to/certs`

### `renew-certificate.sh`
Automated SSL certificate renewal script using webroot authentication.
- Renews Let's Encrypt certificates when needed
- Uses webroot method (no downtime required)
- Automatically configured in crontab for daily checks
- Usage: `./renew-certificate.sh [--dry-run]`

## Backup and Data Management

### `backup-mattermost.sh`
Comprehensive backup script for the Mattermost installation.
- Backs up database, configuration, and data
- Creates timestamped backup directories
- Supports both daily and weekly backups
- Handles maintenance mode during backup
- Usage: Typically run via cron using `setup-backup-cron.sh`

### `check-all-containers.py`
Python script for inspecting Swift object storage containers.
- Lists all containers in the Swift storage account
- Shows detailed storage statistics and object counts
- Provides sample listings of stored objects
- Validates total storage usage
- Usage: `python3 check-all-containers.py`

### `setup-backup-cron.sh`
Configures automated backup schedule.
- Sets up cron jobs for regular backups
- Configures backup retention periods
- Usage: `./setup-backup-cron.sh`

### `rclone-manager.sh`
Manages remote storage operations using rclone.
- Configures and manages cloud storage connections
- Handles backup synchronization to remote storage
- Usage: Various commands for rclone configuration and sync

## Configuration Management

### `config-manager.sh`
Safely manages Mattermost configuration files.
- Handles file permissions for config editing
- Ensures proper ownership after changes
- Validates JSON syntax
- Usage:
  - `./config-manager.sh status`  # Check current status
  - `./config-manager.sh edit`    # Enable editing
  - `./config-manager.sh restore` # Restore permissions

## Monitoring and Maintenance

### `test-maintenance.sh`
Tests maintenance mode functionality.
- Verifies maintenance page configuration
- Tests nginx maintenance mode switching
- Usage: `./test-maintenance.sh`

### `test-cleanup.sh`
Cleanup utility for testing environments.
- Removes test data and temporary files
- Resets test environments
- Usage: `./test-cleanup.sh`

## Storage Management

### Swift Storage Tools (related to Swiss Backup)

#### `check-all-containers.py`
Provides a high-level overview of Swift storage.
- Lists all containers and their sizes
- Shows object counts and recent modifications
- Validates total storage usage
- Usage: `python3 check-all-containers.py`

#### `deep-swift-scan.py` and `swift-inspector.py`
Detailed Swift storage analysis tools.
- Perform deep inspection of storage structure
- Monitor detailed storage metrics
- Analyze storage patterns and usage
- Usage: `python3 swift-inspector.py`

## Database Management

### `upgrade-postgres.sh`
Handles PostgreSQL database upgrades.
- Manages database version upgrades
- Performs data migration when needed
- Usage: Follow instructions in UPGRADE.md

## Development Tools

### `vscode-manager.sh`
VS Code workspace configuration utility.
- Manages VS Code workspace settings
- Configures development environment
- Usage: `./vscode-manager.sh [setup|update]`

## Best Practices

1. Always review script contents before execution
2. Test scripts with `--dry-run` or test options when available
3. Keep backup scripts and retention policies aligned with your data requirements
4. Monitor logs after running maintenance scripts
5. Use config-manager.sh when editing configuration files

## Logging

Most scripts log their operations to `/home/ubuntu/logs/` with specific log files:
- Certificate operations: `certbot-renewal.log`
- Backup operations: `mattermost-backup.log`
- Rclone operations: `rclone-backup.log`

## Script Dependencies

- bash (all shell scripts)
- Python 3.x (for Python scripts)
- Docker and Docker Compose
- rclone (for remote storage operations)
- certbot (for SSL certificate management)

## See Also

- [UPGRADE.md](./UPGRADE.md) - Detailed upgrade procedures
- [../SETUP_GUIDE.md](../SETUP_GUIDE.md) - Main setup documentation