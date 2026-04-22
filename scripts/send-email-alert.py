#!/usr/bin/env python3
"""
SMTP email alert helper for operational scripts.

Configuration is read from /home/ubuntu/docker/.env (and process env):
- ALERT_EMAIL_ENABLED=true|false
- ALERT_SMTP_HOST=smtp.example.com
- ALERT_SMTP_PORT=587
- ALERT_SMTP_USER=alerts@example.com
- ALERT_SMTP_PASS=app-password
- ALERT_SMTP_FROM=alerts@example.com
- ALERT_SMTP_TO=ops@example.com[,admin@example.com]
- ALERT_SMTP_TLS=starttls|ssl|none
- ALERT_SUBJECT_PREFIX=[Mattermost]
"""

import argparse
import os
import smtplib
import ssl
from email.message import EmailMessage
from pathlib import Path


ENV_PATH = Path("/home/ubuntu/docker/.env")


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        # Preserve explicit process env if already set.
        os.environ.setdefault(key, value)


def _is_enabled() -> bool:
    return os.getenv("ALERT_EMAIL_ENABLED", "false").strip().lower() in {"1", "true", "yes", "on"}


def _required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required setting: {name}")
    return value


def send_email(subject: str, body: str) -> None:
    host = _required("ALERT_SMTP_HOST")
    port = int(os.getenv("ALERT_SMTP_PORT", "587"))
    user = _required("ALERT_SMTP_USER")
    password = _required("ALERT_SMTP_PASS")
    sender = _required("ALERT_SMTP_FROM")
    recipients_raw = _required("ALERT_SMTP_TO")
    tls_mode = os.getenv("ALERT_SMTP_TLS", "starttls").strip().lower()
    subject_prefix = os.getenv("ALERT_SUBJECT_PREFIX", "[Mattermost]").strip()

    recipients = [item.strip() for item in recipients_raw.split(",") if item.strip()]
    if not recipients:
        raise ValueError("ALERT_SMTP_TO has no valid recipients")

    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = f"{subject_prefix} {subject}".strip()
    msg.set_content(body)

    if tls_mode == "ssl":
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(host, port, context=context, timeout=30) as server:
            server.login(user, password)
            server.send_message(msg)
        return

    with smtplib.SMTP(host, port, timeout=30) as server:
        if tls_mode == "starttls":
            context = ssl.create_default_context()
            server.starttls(context=context)
        server.login(user, password)
        server.send_message(msg)


def main() -> int:
    parser = argparse.ArgumentParser(description="Send SMTP email alerts")
    parser.add_argument("--subject", required=True, help="Email subject")
    parser.add_argument("--body", required=True, help="Email body")
    args = parser.parse_args()

    _load_env_file(ENV_PATH)

    if not _is_enabled():
        print("Email alerts are disabled (ALERT_EMAIL_ENABLED != true).")
        return 0

    try:
        send_email(args.subject, args.body)
        print("Alert email sent.")
        return 0
    except Exception as exc:
        print(f"Failed to send alert email: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
