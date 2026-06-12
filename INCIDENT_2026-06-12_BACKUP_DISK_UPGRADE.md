# Incident Report: Backup failure due to root disk pressure (2026-06-12)

## Summary
In the week leading to 2026-06-12, Mattermost backups began failing again because the root filesystem `/` had insufficient free space for the backup script's safety check.

The disk was upgraded from 20GB to 40GB and the backup process was rerun successfully.

## Impact
- Automatic daily/weekly backup jobs were failing at startup with:
  - `Insufficient disk space. Required: 2GB, Available: 1GB`
- No new backup could complete after `2026-05-30` until the storage upgrade.

## Detection
- Recent backup log entries in `/home/ubuntu/logs/cron-backup.log` showed repeated failures from `20260601_020001` through `20260609_020001`.
- The failure was confirmed in the backup script output as a preflight disk space check.

## Root Cause
- The server's root disk was too small for the Mattermost/Docker workload and backup retention pattern.
- The backup script requires at least 2GB free, and the previous 20GB root volume was at ~93% usage.

## Action Taken
1. Upgraded the root disk to 40GB.
2. Verified the upgrade with:
   - `df -h /` showing `/dev/sda1 39G` and ~20G available.
   - `lsblk` showing `sda` resized to `40G`.
3. Reran the backup script successfully:
   - `./scripts/backup-mattermost.sh --verbose`
   - Completed with `SUCCESS: Daily backup process completed successfully`
4. Confirmed new backup created at `/home/ubuntu/backups/daily/20260612_075852`.

## Verification
- Disk size verified: `/dev/sda1` now `39G`
- Available free space after upgrade: ~20G
- Backup run completed without error and uploaded successfully to cloud storage

## Follow-Up
- Continue monitoring root disk usage and Docker storage growth.
- Consider moving large, long-term backup data off the root filesystem if growth continues.
- Keep the disk upgrade as the main fix rather than relying on repeated cleanup.
