#!/bin/sh
# Monthly reminder to update UniFi by hand, posted to the cluster Discord channel.
#
# Auto-update is OFF for UniFi OS, the apps and device firmware (2026-11-19):
# switch firmware auto-updates rebooted the Main and PoE switches at 3am,
# which partitioned etcd (etcdNoLeader, failed gRPC) and tripped Ceph network
# alerts. Updates are now done by hand, when someone is awake to watch.
#
# The CronJob fires every Sunday; Kubernetes cron ORs day-of-month with
# day-of-week, so "first Sunday" cannot be written as a schedule. This script
# posts only when the date is the 1st-7th. FORCE_SEND=1 skips that check.
set -eu

day=$(date +%d)
if [ "${FORCE_SEND:-0}" != "1" ] && [ "${day#0}" -gt 7 ]; then
  echo "day ${day} is not in the first week, nothing to send"
  exit 0
fi

# Devices UniFi says have firmware waiting, from unpoller via Prometheus.
# Best effort: the reminder still goes out if Prometheus cannot be reached.
# Quotes and backslashes are stripped so the names are safe inside JSON.
names=$(curl -fsS --max-time 20 -G "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=max by (name, type) (unpoller_device_upgradable) == 1' 2>/dev/null \
  | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | tr -d '\\"' | sort -u || true)
# Build a JSON-escaped list: each entry ends in a literal \n (two characters).
pending=""
while IFS= read -r name; do
  [ -n "${name}" ] && pending="${pending}- ${name}\\n"
done <<EOF
${names}
EOF
if [ -z "${pending}" ]; then
  pending='- none reported (or Prometheus was unreachable)\n'
fi

content="<@${DISCORD_USER_ID}> **Monthly UniFi update** - first Sunday of the month. Auto-update is off everywhere, so nothing updates unless you do it.\n\n**Firmware waiting:**\n${pending}\n**Order:**\n1. Network app + UniFi OS (Settings > Control Plane > Updates). A UniFi OS update reboots the UDM Pro: routing and internet drop for a few minutes.\n2. APs and the Mini switches (UniFi Devices > select > Update).\n3. Core switches LAST, one at a time: USW Aggregation, Main Switch, PoE Switch. Expect etcdNoLeader / failed gRPC / Ceph OSD timeout alerts while each reboots; wait for them to clear before the next.\n\nCheck after: etcd healthy, Ceph HEALTH_OK, no TargetDown."

printf '{"username":"UniFi reminder","allowed_mentions":{"users":["%s"]},"content":"%s"}' \
  "${DISCORD_USER_ID}" "${content}" > /tmp/payload.json

curl -fsS --max-time 30 -H 'Content-Type: application/json' \
  --data-binary @/tmp/payload.json "${DISCORD_WEBHOOK}" > /dev/null
echo "reminder posted"
