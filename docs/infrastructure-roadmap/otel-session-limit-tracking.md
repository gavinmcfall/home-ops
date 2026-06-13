# Session-limit & spend tracking — Claude rate-limit windows into the backbone

Capture Claude Code's authoritative rate-limit windows (the 5-hour, 7-day, and
7-day-Opus rolling limits) and land them in the OTel → InfluxDB → Grafana
backbone, so a Grafana panel can show *"how close am I to each limit right now,
and when does it reset"*.

Part of the [infrastructure roadmap](./README.md). This is an **increment on
[spec 1 — the OTel backbone](./otel-telemetry-backbone.md)**, not new
infrastructure: it adds one emitter (the status line) and a few dashboard panels
to the plane that already exists.

## Why

Gavin asked: *"track my relative session limit stuff? claudes plans are a bit
odd wit their 5h, 7d, 1m sessions. Can I get thata data in a meaningful way?"*

The OTel **metrics** stream Claude Code exports does **not** carry limit/quota
data — no `rate_limit.*`, no reset times. That data lives on a *separate* path:
the Claude Code **status line** is handed a JSON payload on stdin that, for
Pro/Max subscribers, includes the real numbers:

```json
"rate_limits": {
  "five_hour":       { "used_percentage": 23.5, "resets_at": 1738425600 },
  "seven_day":       { "used_percentage": 41.2, "resets_at": 1738857600 },
  "seven_day_opus":  { "used_percentage": 12.0, "resets_at": 1738857600 }
}
```

These are authoritative (server-provided), not reconstructed estimates. There is
**no monthly / `1m` window** in the payload — only the three above. The field
appears only for Claude.ai subscribers and only after the first API response in
a session; each window can be independently absent.

`~/.claude/statusline.sh` already extracts these and renders them, and already
fire-and-forget POSTs them to **Spyglass** (`$SPYGLASS_URL/api/account-usage`).
This spec adds a **second, parallel write** into the telemetry backbone so the
data is queryable and historical in Grafana, independent of Spyglass.

## Scope

### In scope (now — Claude-only, runs on WSL2 today)

1. **Status-line dual-write** — `~/.claude/statusline.sh` gains a backgrounded,
   throttled OTLP/HTTP metrics POST to the existing collector, alongside (not
   replacing) the existing Spyglass POST.
2. **Grafana limit panels** — 5h / 7d / 7d-Opus gauges with reset countdowns on
   the `dev-telemetry` dashboard, reading the new measurement from InfluxDB.
3. **Dashboard durability** — provision `dev-telemetry-ai` as a GitOps-managed
   ConfigMap dashboard (replacing the current fragile URL-download path) so the
   new panels land durably, not as another manual UI import.

### Out of scope (deferred — written down so it is not lost)

- **Codex + Gemini usage** via [ccusage](https://github.com/ccusage/ccusage).
  ccusage reads each CLI's local logs (`~/.codex/sessions/`,
  `~/.gemini/tmp/`) and emits tokens/cost/blocks for 14+ agents, but has **no**
  authoritative limit %. It needs the log files on disk, so it waits for the
  **dev-container-in-cluster** move, then runs as a CronJob/sidecar →
  InfluxDB. **No Codex/Gemini data until that move.**
- **Spyglass decommission** — once these panels prove out, Spyglass's
  `internal/usage` quota wheel / dollar / 5h-window becomes legacy and is
  removed (separate Spyglass-repo work). Spyglass keeps the session fleet view.

## Why this split (Spyglass vs Grafana)

Decided 2026-06-13. Two tools, two jobs:

- **Spyglass** answers *"what are my agents doing right now, and how do I resume
  one?"* — the live session fleet view. Keeps its OTLP-logs liveness ingest.
- **Grafana / InfluxDB** answers *"how much am I spending, how close to limits,
  what's the historical trend?"* — the metrics home.

The status line dual-writes during the transition; Spyglass sheds its usage
gauge over time. Grafana becomes the durable, historical home for limit + spend
metrics.

## Architecture

```
 ~/.claude/statusline.sh  (WSL2, runs every status-line tick)
   │  extract .rate_limits.{five_hour,seven_day,seven_day_opus}
   │
   ├─ existing: POST $SPYGLASS_URL/api/account-usage   (live wheel — unchanged)
   │
   └─ NEW (backgrounded, throttled ~60s, --max-time 2):
        POST http://10.99.8.217:4318/v1/metrics         ← LAN LB IP, the collector
          Authorization: Bearer $DEVTELEM_OTEL_BEARER     (already in ~/.secrets)
          OTLP/HTTP JSON, resource service.name=claude-statusline
            gauge claude_code.rate_limit.used_percentage {window, machine}
            gauge claude_code.rate_limit.resets_at       {window, machine}
                       │
                       ▼
  OTel Collector (contrib) ──influxdb exporter──▶ InfluxDB 3 (dev-telemetry)
                       │   telegraf-prometheus-v2 schema:
                       │   metric name → column in `prometheus` table,
                       │   window/machine → tags
                       ▼
  Grafana (InfluxDB SQL datasource) → dev-telemetry-ai dashboard limit panels
```

The collector is the right ingest point: it is the universal plane, it is the
only backbone component reachable from WSL2 (InfluxDB 3 is ClusterIP-only), it
already requires the bearer token, and Claude Code already emits its other
metrics there. The status line just adds one more payload to the same door.

## The status-line contract

**Trigger / gating.** On every tick, after the existing extraction, if
`.rate_limits.five_hour.used_percentage` is present (Pro/Max, post-first-response)
**and** `$DEVTELEM_OTEL_BEARER` is set, attempt the backbone write. Absent
rate-limits or token → silent no-op (matches the existing Spyglass-forwarder
gating).

**Throttle.** The status line fires many times per second during activity. Gate
the backbone write to **at most once per 60 s** using the mtime of a marker file
(e.g. `${XDG_CACHE_HOME:-$HOME/.cache}/claude/.otel-ratelimit-last`): if the
marker is younger than 60 s, skip; otherwise `touch` it and send. The marker is
local scratch, not committed.

**Non-blocking.** The write runs in a backgrounded subshell with
`curl --max-time 2 -s -o /dev/null ... &`. It must never delay status-line
render. Failures are swallowed (`2>/dev/null`), exactly like the Spyglass POST.

**Payload.** OTLP/HTTP JSON to `/v1/metrics`. One resource
(`service.name=claude-statusline`), one scope, two gauge metrics. Each window
present contributes one data point per metric, carrying `window` and `machine`
attributes:

```json
{
  "resourceMetrics": [{
    "resource": { "attributes": [
      { "key": "service.name", "value": { "stringValue": "claude-statusline" } }
    ]},
    "scopeMetrics": [{
      "metrics": [
        {
          "name": "claude_code.rate_limit.used_percentage",
          "gauge": { "dataPoints": [
            { "asDouble": 23.5, "timeUnixNano": "<now>",
              "attributes": [
                { "key": "window",  "value": { "stringValue": "five_hour" } },
                { "key": "machine", "value": { "stringValue": "<hostname>" } }
              ]},
            { "asDouble": 41.2, "timeUnixNano": "<now>",
              "attributes": [
                { "key": "window",  "value": { "stringValue": "seven_day" } },
                { "key": "machine", "value": { "stringValue": "<hostname>" } }
              ]}
          ]}
        },
        {
          "name": "claude_code.rate_limit.resets_at",
          "gauge": { "dataPoints": [
            { "asInt": "1738425600", "timeUnixNano": "<now>",
              "attributes": [
                { "key": "window",  "value": { "stringValue": "five_hour" } },
                { "key": "machine", "value": { "stringValue": "<hostname>" } }
              ]}
          ]}
        }
      ]
    }]
  }]
}
```

The payload is built with `jq` from the same `$input` the script already parses,
so window presence is handled per-window (skip a window whose `used_percentage`
is absent).

**These are gauges, not counters.** A used-percentage is an absolute level and a
reset time is an absolute instant — neither is a monotonic counter. So, unlike
the token/cost metrics, there is **no delta-temporality `sum()` to unwind** in
the Grafana queries; the latest value per `(window, machine)` is the truth.

## InfluxDB landing

The collector's `influxdb` exporter uses the `telegraf-prometheus-v2` schema,
so both metrics land in the single `prometheus` table in the `dev-telemetry`
database as columns `claude_code.rate_limit.used_percentage` and
`claude_code.rate_limit.resets_at`, tagged `window` and `machine`. Dotted column
names must be double-quoted in SQL.

Latest-value-per-window query shape (used by the gauge panels):

```sql
SELECT window, "claude_code.rate_limit.used_percentage" AS used_pct
FROM prometheus
WHERE "claude_code.rate_limit.used_percentage" IS NOT NULL
  AND time > now() - INTERVAL '15 minutes'
QUALIFY ROW_NUMBER() OVER (PARTITION BY window, machine ORDER BY time DESC) = 1
```

## Grafana panels

Added to `dashboards/grafana/dev-telemetry-ai.json`, InfluxDB-Telemetry SQL
datasource:

1. **Three gauge panels** — `5h`, `7d`, `7d-Opus` `used_percentage`, latest
   value per window. Thresholds green < 70, yellow 70–89, red ≥ 90 (mirrors the
   status-line colour bands).
2. **Reset countdown** — a stat panel per window rendering `resets_at` as a
   "resets in Xh Ym" relative time (`resets_at - now()`).
3. **5h trend** (optional, nice-to-have) — a time series of
   `used_percentage WHERE window='five_hour'` over the last 24 h, to see the
   sawtooth as windows roll over.

These render only for the machine(s) actually running Claude; multi-machine is
handled by the `machine` tag and a dashboard variable if more than one ever
reports.

## Dashboard durability (fold-in)

The `dev-telemetry-ai` dashboard currently only exists as a **manual UI import**
because Grafana's `download_dashboards.sh` truncates URL-downloaded JSON
(observed: 7815/10860 bytes; cert-manager.json 0 bytes). Rather than re-import
manually after adding panels, switch this dashboard to **ConfigMap-sidecar
provisioning**: ship the JSON as a ConfigMap labelled for the Grafana dashboard
sidecar, GitOps-managed in `kubernetes/apps/observability/grafana/`. The exact
sidecar wiring (label, folder annotation, whether the sidecar is already enabled
in the Grafana HelmRelease) is confirmed during planning; the outcome is that
`dev-telemetry-ai` — limit panels included — is reproducible from git, not a
hand-imported artifact.

## Testing

- **Payload shape** — pipe a mock status-line `$input` containing `rate_limits`
  through the new block with the curl stubbed; assert the `jq`-built JSON is
  valid OTLP and contains one data point per present window.
- **Gating** — mock `$input` *without* `rate_limits` → no POST attempted; with
  `rate_limits` but `$DEVTELEM_OTEL_BEARER` unset → no POST attempted.
- **Throttle** — two invocations <60 s apart with a fresh marker → exactly one
  POST; >60 s apart → two POSTs.
- **Non-blocking** — the status line still prints its line when the endpoint is
  unreachable (point at a dead port, confirm render is immediate and unchanged).
- **End-to-end** — after wiring, run a real Claude session, then query InfluxDB
  (`SELECT window, "claude_code.rate_limit.used_percentage", time FROM
  prometheus WHERE "claude_code.rate_limit.used_percentage" IS NOT NULL ORDER BY
  time DESC LIMIT 5`) and confirm rows for each active window. Then confirm the
  Grafana gauges read non-null.

## Risks & notes

- **Status-line latency is sacred.** Any synchronous network work would stall
  the prompt; the throttle + background + `--max-time 2` are non-negotiable
  guardrails, not polish.
- **WSL2 telemetry is throwaway.** This emitter lives on the workstation; when
  the CLIs move to the dev container, the same block moves with the status-line
  config. Nothing here needs migrating beyond a copy.
- **`seven_day_opus` naming.** The payload key is `seven_day_opus`; Spyglass
  already maps it to a field it calls `seven_day_sonnet`. We use the payload's
  own name (`seven_day_opus`) as the `window` tag to avoid the mislabel.
- **No monthly window exists.** If Anthropic later adds a `thirty_day` /
  monthly field to the payload, it is a one-line addition to the same loop.
