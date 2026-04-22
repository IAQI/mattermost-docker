# Thread Summary: Backup Failures, Disk Cleanup, and Alerting

Date: 2026-04-22
Scope: Mattermost backup failures, storage pressure, backup script stability fix, email alerting, and site reachability monitoring.

## 1) Findings

### Disk and backup failure findings
- Root filesystem was high usage (93%) with ~1.6G free at the start.
- Backup process required >= 2G free and was failing.
- Repeated backup failures were confirmed in `logs/mattermost-backup.log`:
  - 2026-04-13 to 2026-04-22 with `Insufficient disk space. Required: 2GB, Available: 1GB`.
  - Evidence lines: 8270, 8273, 8276, 8279, 8282, 8285, 8288, 8291, 8294, 8297.

### Root cause of post-backup non-zero exit
- Backup data and cloud upload were succeeding, but the script used post-increment arithmetic in a `set -e` shell context.
- Expressions like `((deleted_daily++))` can return non-zero (depending on previous value), causing unexpected script termination.

## 2) Applied Changes

### A) Storage cleanup to restore backup viability
- Performed safe cleanup:
  - journal vacuum (largest gain)
  - apt cache cleanup
  - temp file cleanup
  - docker builder prune (no reclaim in this case)
- Result after cleanup:
  - Root free space increased to ~3.4G
  - Root usage reduced to ~83%

### B) Backup script stability fix
File: `docker/scripts/backup-mattermost.sh`
- Changed arithmetic increments to `+=1` form:
  - `((retries+=1))`
  - `((deleted_daily+=1))`
  - `((deleted_weekly+=1))`
- Added backup failure email alert hook:
  - New `send_alert()` helper in script
  - `error_exit()` now sends an email alert when configured

### C) Email alerting implementation
- Added SMTP alert helper:
  - File: `docker/scripts/send-email-alert.py`
  - Reads settings from `docker/.env`
  - Supports `starttls`, `ssl`, or `none`

### D) Site reachability monitoring with alerts
- Added monitor script:
  - File: `docker/scripts/site-health-check.sh`
  - Checks site URL and logs to `~/logs/site-health.log`
  - Sends alert on DOWN transition
  - Sends recovery alert on UP transition
  - Maintains state in `~/.site-health.state`

### E) Configuration and docs updates
- Added alerting configuration template to:
  - `docker/env.example`
- Updated script documentation in:
  - `docker/scripts/README.md`

## 3) Validation and Evidence

### Backup success after fixes
- Full backup run completed successfully with final markers present:
  - `Daily backup process completed successfully` (line 8372)
  - `Backup location: /home/ubuntu/backups/daily/20260422_085345` (line 8373)
  - `Total backup size: 95M` (line 8374)
- Latest successful sequence around 08:53-08:54 confirmed in `logs/mattermost-backup.log` lines 8332-8375.

### Current disk status
- Current root usage: 83%, free ~3.5G.

### Site monitor check
- Manual site monitor run succeeded:
  - `logs/site-health.log` shows `Site reachable: https://mm.iaqi.org`.

## 4) Current Operational State

### Active cron entries
- Backup job:
  - `0 2 * * * /home/ubuntu/docker/scripts/backup-mattermost.sh --verbose >> /home/ubuntu/logs/cron-backup.log 2>&1`
- Site health monitor:
  - `*/30 * * * * /home/ubuntu/docker/scripts/site-health-check.sh >> /home/ubuntu/logs/site-health.log 2>&1`

## 5) Notes
- Email alerts are feature-complete but only active when SMTP settings are configured in `docker/.env` and `ALERT_EMAIL_ENABLED=true`.
- Services were confirmed healthy after backup runs.
