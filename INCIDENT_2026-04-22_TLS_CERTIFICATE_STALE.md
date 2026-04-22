# Incident Report: Stale TLS Certificate Served After Renewal (2026-04-22)

## Summary
On 2026-04-22, users of `https://mm.iaqi.org` received an expired TLS certificate, even though a newer, valid Let's Encrypt certificate already existed on disk.

Immediate remediation was to restart the `nginx` container so it reloaded the mounted certificate file.

## Impact
- HTTPS clients saw certificate expiration errors for `mm.iaqi.org`.
- API traffic over HTTPS was affected until nginx was restarted.

## Detection
### Public endpoint (expired certificate)
`openssl s_client -connect mm.iaqi.org:443 -servername mm.iaqi.org | openssl x509 -noout -dates`

Observed before fix:
- `notAfter=Apr 19 23:37:09 2026 GMT` (expired)

### Local certificate on disk (valid certificate)
`openssl x509 -in ./certs/etc/letsencrypt/live/mm.iaqi.org/fullchain.pem -noout -dates`

Observed on disk:
- `notAfter=Jun 19 23:38:12 2026 GMT` (valid)

## Root Cause
- Certificate renewal succeeded previously and wrote a newer certificate lineage.
- Nginx continued serving an older loaded certificate and had not reloaded/restarted after the renewal event.
- Existing renewal logic relied on broad log-message matching and did not robustly tie action to this run's actual certificate change.

## Immediate Fix Applied
1. Restarted nginx container:
```bash
cd /home/ubuntu/docker
sudo -n docker compose -f docker-compose.yml -f docker-compose.nginx.yml restart nginx
```
2. Re-verified live certificate:
```bash
echo | openssl s_client -connect mm.iaqi.org:443 -servername mm.iaqi.org 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Observed after fix:
- Subject: `CN = mm.iaqi.org`
- Issuer: `Let's Encrypt, CN = E8`
- `notAfter=Jun 19 23:38:12 2026 GMT`

## Permanent Prevention Changes
Updated `scripts/renew-certificate.sh` to ensure renewed certificates are served:
- Captures only the current renewal run output in a temporary run log.
- Computes certificate SHA-256 fingerprint before and after renewal.
- Restarts nginx automatically when fingerprint changes.
- Keeps a fallback restart trigger for explicit certbot success output in current run.

This makes nginx reload behavior deterministic and tied to actual certificate file changes.

## Verification Procedure (Post-Renewal)
Run after every renewal window:
```bash
# 1) Check live cert presented to clients
echo | openssl s_client -connect mm.iaqi.org:443 -servername mm.iaqi.org 2>/dev/null | openssl x509 -noout -subject -issuer -dates

# 2) Confirm endpoint health
curl -sSf https://mm.iaqi.org/api/v4/system/ping >/dev/null && echo "API check: OK"
```

## Follow-Up
- Keep root cron job for renewal (`/home/ubuntu/docker/scripts/renew-certificate.sh`) active.
- Review `/home/ubuntu/logs/certbot-renewal.log` periodically for restart entries.
- Add external certificate-expiry monitoring (>=14 days before expiry) for early alerting.
