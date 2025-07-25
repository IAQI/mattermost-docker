# Mattermost Docker
[![ShellCheck](https://github.com/mattermost/docker/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/mattermost/docker/actions/workflows/shellcheck.yml)

The official Docker deployment solution for Mattermost.

## Install & Usage

Refer to the [Mattermost Docker deployment guide](https://docs.mattermost.com/install/install-docker.html) for instructions on how to install and use this Docker image.

## Documentation

- **[Setup Guide](SETUP_GUIDE.md)** - Complete installation and configuration guide
- **[Backup Guide](BACKUP_GUIDE.md)** - Automated backup and cloud sync setup  
- **[Restore Guide](RESTORE_GUIDE.md)** - Data restoration procedures
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions

## Utility Scripts

The `scripts/` directory contains helpful utilities for managing your Mattermost installation:

- **[backup-mattermost.sh](scripts/backup-mattermost.sh)** - Automated backup with cloud sync
- **[cloud-backup.sh](scripts/cloud-backup.sh)** - Standalone cloud backup sync
- **[config-manager.sh](scripts/config-manager.sh)** - Safe config file editing helper
- **[vscode-manager.sh](scripts/vscode-manager.sh)** - VS Code memory management tool

Run any script with `--help` for usage information.

## Contribute
PRs are welcome, refer to our [contributing guide](https://developers.mattermost.com/contribute/getting-started/) for an overview of the Mattermost contribution process.

## Upgrading from `mattermost-docker`

This repository replaces the [deprecated mattermost-docker repository](https://github.com/mattermost/mattermost-docker). For an in-depth guide to upgrading, please refer to [this document](https://github.com/mattermost/docker/blob/main/scripts/UPGRADE.md).
