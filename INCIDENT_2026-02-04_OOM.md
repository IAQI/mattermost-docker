# Incident Report: OOM Kill of Mattermost (2026-02-04)

## Summary
On 2026-02-04 at 07:40:11, the Linux OOM killer terminated the `mattermost` process due to memory pressure. The kernel reported the Mattermost process with ~1.56 GB RSS at the time of termination. Mattermost was restarted by restarting the server.

## Evidence (Kernel Logs)
- OOM killer invoked and killed process `mattermost` (UID 2000).
- Reported RSS at time of kill: ~1.56 GB.

Relevant journal excerpt (from `journalctl`):
- `kernel: oom-kill: ... task=mattermost, pid=2826671, uid=2000`
- `kernel: Out of memory: Killed process 2826671 (mattermost) total-vm:25136328kB, anon-rss:1561372kB ...`

## Application Logs
Mattermost logs around the incident time show normal request activity (no explicit application crash stack trace or fatal error recorded).

## Impact
- Mattermost process terminated by OOM killer.
- Service restored after server restart.

## Mitigations Applied
- **Swap increased from 2 GB to 4 GB** on 2026-02-05.

## Follow-Up
- Monitor for recurrence.
- If OOM happens again, add proactive memory snapshot logging (e.g., periodic `ps`/`docker stats` snapshots and threshold triggers).
