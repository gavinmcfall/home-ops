#!/bin/sh
# Monthly reminder to update UniFi by hand.
#
# Auto-update is OFF for UniFi OS, the apps and device firmware (2026-11-19):
# switch firmware auto-updates rebooted the Main and PoE switches at 3am,
# which partitioned etcd (etcdNoLeader, failed gRPC) and tripped Ceph network
# alerts. Updates are now done by hand, when someone is awake to watch.
#
# The CronJob fires every Sunday; Kubernetes cron ORs day-of-month with
# day-of-week, so "first Sunday" cannot be written as a schedule. This script
# sends only when the date is the 1st-7th. FORCE_SEND=1 skips that check.
set -eu

day=$(date +%d)
if [ "${FORCE_SEND:-0}" != "1" ] && [ "${day#0}" -gt 7 ]; then
  echo "day ${day} is not in the first week, nothing to send"
  exit 0
fi

# Devices UniFi says have firmware waiting, from unpoller via Prometheus.
# Best effort: the reminder still goes out if Prometheus cannot be reached.
pending=$(curl -fsS --max-time 20 -G "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=max by (name, type) (unpoller_device_upgradable) == 1' 2>/dev/null \
  | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sort -u | sed 's/^/  - /' || true)
if [ -z "${pending}" ]; then
  pending="  (none reported by unpoller, or Prometheus was unreachable)"
fi

msg=/tmp/message.eml
cat > "${msg}" <<EOF
From: UniFi update reminder <${MAIL_FROM}>
To: ${MAIL_TO}
Subject: Monthly UniFi update - $(date +'%B %Y')
Date: $(date -R)
Message-ID: <unifi-update-$(date +%Y%m%d%H%M%S)@${MAIL_FROM#*@}>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

It's the first Sunday of the month. Time to update UniFi by hand.
Auto-update is off everywhere, so nothing updates unless you do it.

Devices with firmware waiting:
${pending}

Order:
  1. Network app and UniFi OS (Settings > Control Plane > Updates).
     A UniFi OS update reboots the UDM Pro: routing and internet drop
     for a few minutes.
  2. APs and the Mini switches (UniFi Devices > select > Update).
  3. Core switches LAST, one at a time: USW Aggregation, Main Switch,
     PoE Switch. They carry the control-plane and Ceph links. Expect
     etcdNoLeader / failed gRPC / Ceph OSD timeout alerts while each
     reboots; wait for them to clear before the next switch.

Check after: etcd healthy, Ceph HEALTH_OK, no TargetDown.
EOF

curl -fsS --max-time 60 "smtp://${SMTP_HOST}:${SMTP_PORT}" \
  --mail-from "${MAIL_FROM}" \
  --mail-rcpt "${MAIL_TO}" \
  --upload-file "${msg}"
echo "reminder sent"
