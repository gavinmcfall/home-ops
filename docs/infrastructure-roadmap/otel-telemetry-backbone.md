# OpenTelemetry backbone — central ingestion plane

Stand up a single OpenTelemetry ingestion plane for the homelab: one collector
that receives OTLP from in-cluster, on-LAN, and (securely) off-LAN emitters and
routes it, with a dedicated InfluxDB 3 datastore behind it. The first load is AI-CLI telemetry (Claude Code,
Codex CLI, Gemini CLI); the same plane later carries app traces and feeds
public-facing dashboards.

Part of the [infrastructure roadmap](./README.md). This is **spec 1 of three** —
see [Build order](#build-order-three-specs).

## ⚠️ Before starting

**This does not replace kube-prometheus-stack.** Prometheus stays the
Kubernetes-infra plane (node/cAdvisor, kube-state-metrics, the exporter wall,
Alertmanager→ntfy). This backbone is the *push*-based plane for application, AI,
and trace telemetry — anything that wants long-term S3-backed retention or a
website-facing dashboard. The two coexist by design (see
[Long-term direction](#long-term-direction--intentional-hybrid)).

## Why

We want OTel metrics on the homelab — starting with the AI coding CLIs so we can
show cost/token/productivity dashboards on the website, expanding to tracing our
own apps. Today there is **no ingestion backbone at all**: zero OTel anywhere in
the cluster, no collector, no OTLP receiver, no trace store.

What exists is a single bespoke pipe: a script on the WSL2 workstation samples
Claude Code process memory (PSS) + token counts and pushes InfluxDB
line-protocol directly into the `vitals` InfluxDB (`claude-code` bucket), which
the `devpod-telemetry` Grafana dashboard reads via Flux. That works, but it is
workstation-only, narrow, and not a foundation.

Building three point-to-point integrations (one per future theme) would be a
mess. Instead we lay one **universal ingestion plane** now, and every later
theme bolts onto it as configuration rather than new infrastructure.

## Build order (three specs)

The work decomposes into three independent sub-projects on one backbone. Each
gets its own spec → plan → build cycle.

1. **Backbone + AI-tools telemetry** *(this spec)* — the collector, the
   datastore, and the first real load (Claude/Codex/Gemini CLI metrics) to prove
   the plane routes correctly.
2. **Website exposure** — decide Grafana public-embed vs a custom frontend
   pulling a thin metrics API; expose the AI dashboard plus a couple of existing
   crowd-pleasers (live homelab watts, Plex now-playing).
3. **App traces** — stand up Grafana Tempo and instrument our own apps (Cortex,
   Mangarr, scbridge, n8n) with the OTel SDK, one at a time. Highest effort,
   done once the plane is proven.

## Architecture

```
 emitters (all carry the bearer token):
   in-cluster (devpod CLIs, our apps) ──OTLP──────────────┐  via svc DNS
   on-LAN (workstation / devices) ─────OTLP──────────────┤  via Cilium LB IP
   off-LAN ──HTTPS──▶ Cloudflare (Access service token) ──┤  via cloudflared tunnel
                                                          ▼  (OTLP/HTTP only)
  OTel Collector (contrib image, Deployment)        ← observability ns
        │ influxdb exporter (line protocol)
        ▼
  InfluxDB 3 Enterprise (StatefulSet)               ← database ns
        │ WAL + Parquet cache on local PVC
        ▼  durable Parquet store
  Ceph RGW bucket (in-cluster, zero egress)         ← primary object store
        ▲
   Grafana (InfluxDB SQL datasource) → internal dashboards   (website = spec 2)

 (deferred) traces pipeline → Tempo                  (spec 3)
 (deferred) cold Parquet archive → Backblaze B2      (only if Ceph growth demands)
```

## Decisions

Every decision below is locked from the design conversation.

### Metrics sink: InfluxDB (not Prometheus)

AI telemetry is high-cardinality and event-shaped (session id, repo, model,
cost) — exactly what would blow up Prometheus's TSDB and exactly what a
columnar time-series store handles well. It also keeps continuity with the
existing dev-telemetry pattern. The collector uses the `influxdb` exporter.

### Engine: InfluxDB 3 Enterprise (free at-home)

The original "offload old data to S3" idea pushed us to v3, which is
**object-storage-native**: it persists its data *as* Apache Parquet to an S3
endpoint, not as a bolt-on export. Enterprise (free for at-home, non-commercial
use) is required over Core because Core caps queries at a 72-hour window;
Enterprise's compactor lifts that so we can query the full history.

Trade-off accepted: v3's query language is SQL/InfluxQL, not v2's Flux. Since
this is greenfield with new dashboards, that's fine — only the small existing
`claude-code` dashboard needs query rewrites, and only at cutover.

The OTel Collector's `influxdb` exporter writes line-protocol via the v2 write
API, which v3 still accepts — so the collector wiring is identical regardless of
engine version.

### Primary object store: Ceph RGW (in-cluster), **not** B2

InfluxDB 3's object store is the **primary, continuously-accessed datastore** —
compaction and any cache-miss query read Parquet straight from it. Pointing that
at an off-site bucket (B2) would mean constant egress and internet latency on the
hot path. So the primary store must be local.

Ceph RGW is already live (there is a `CephObjectStore` named `ceph-objectstore`,
and `zot` already provisions a bucket through it). InfluxDB 3 gets its bucket the
same way zot does — an `ObjectBucketClaim` with `storageClassName: ceph-bucket`
(e.g. `bucketName: influxdb-telemetry`), which yields a ConfigMap
(`BUCKET_HOST`/`BUCKET_NAME`) and a Secret (`AWS_ACCESS_KEY_ID`/`SECRET`).
Influx 3's S3 config points at the in-cluster RGW endpoint
(`rook-ceph-rgw-ceph-objectstore`). The hot path never leaves the cluster. A
local PVC holds the WAL and Parquet cache.

### Backblaze B2: deferred cold archive only

B2's role is the one originally intended — a cold archive for genuinely aged
Parquet we want *off* Ceph, queried rarely (e.g. via DuckDB on the Parquet). It
is **not** the live store. It activates only if/when Ceph growth justifies it
(see below).

### Ceph growth control

Two levers, both deferrable:

1. **Retention on the Influx database** — v3 drops Parquet older than the window
   straight out of the bucket. The simple cap on unbounded growth.
2. **Archive-before-drop** (later) — a periodic job copies aged Parquet from the
   Ceph bucket to B2 before retention deletes it, then DuckDB queries the B2
   archive when ancient data is needed.

**Approach: measure-first.** AI-CLI telemetry is low-volume (a few MB/day),
trivial against Ceph. Launch with a generous **730-day** safety cap, watch the
bucket's actual growth, and only build the B2 archive lifecycle if the numbers
ever justify it. Do not pre-build a cold tier for data that may never get big.

### Collector: deployment, exposure & auth

- Official `opentelemetry-collector` Helm chart, `mode: deployment`, single
  replica. **Image must be `-contrib`** — the `influxdb` exporter ships only in
  contrib.
- Receivers: `otlp` gRPC :4317 + HTTP :4318. Pipeline: `otlp` →
  `memory_limiter`/`resource` (stamp `source`, `host`, `service.name`)/`batch`
  processors → `influxdb` exporter.
- **Traces and logs pipelines are written into the config but stubbed** (no
  exporter). Traces wait for Tempo (spec 3); logs stay on the existing
  promtail/Loki path.

**Three access tiers** — emitters live in-cluster, on the LAN, *and* off-LAN:

1. **In-cluster** — service DNS
   `otel-collector.observability.svc.cluster.local` (gRPC or HTTP).
2. **LAN** — a **Cilium LoadBalancer IP** (L2 announcement, from the existing
   pool) exposing both OTLP ports, so workstations and devices on the network
   publish directly without leaving the LAN.
3. **Off-LAN** — a **Cloudflare Tunnel** (existing `cloudflared`) publishing
   **OTLP/HTTP :4318 only** at a hostname (e.g. `otel.<domain>`). gRPC is **not**
   exposed externally — Cloudflare gRPC proxying is fiddly and HTTP/protobuf OTLP
   is the robust path.

**Auth, layered (defense in depth):**

- `bearertokenauth` extension on the OTLP receiver — *every* emitter (all three
  tiers) carries the token; the collector rejects anonymous writes. It is never
  an open write-pipe, even in-cluster.
- The public hostname additionally sits behind **Cloudflare Access service
  tokens** (machine-to-machine: `CF-Access-Client-Id` + `CF-Access-Client-Secret`
  headers), so off-LAN requests are authenticated at Cloudflare's edge *before*
  they reach the tunnel. A public OTLP endpoint is a write-pipe to the metrics
  store — it must not be reachable unauthenticated. In-cluster and LAN tiers rely
  on the bearer token alone (no CF Access).

### Namespaces

- **Collector → `observability`** namespace (an observability concern).
- **InfluxDB 3 → `database`** namespace, with the other databases. We avoid
  co-locating datastores inside app namespaces; `vitals` is a grandfathered
  exception and stays where it is. Cross-namespace access is via service DNS.

## Long-term direction — intentional hybrid

The collector is deliberately the **single ingestion plane**, which keeps the
door open to consolidating more onto Influx later without re-architecting:

- It ingests **push** (our apps/CLIs emit OTLP) **and pull** (its `prometheus`
  receiver scrapes any existing `/metrics` endpoint, converts to OTLP, and routes
  it to Influx).
- So "move app X's metrics to Influx" is per-source routing config in the
  collector, not new infrastructure.
- InfluxDB 3 is the *right* consolidation target precisely because it handles the
  high cardinality and unbounded retention that Prometheus cannot.

The intended end-state is **not** a big-bang retirement of kube-prometheus-stack.
Prometheus keeps doing k8s infra (it is deeply k8s-shaped and mature there);
OTel→Influx owns app/AI/trace telemetry and anything website-facing or wanting
long-term S3 retention. The prometheus-receiver is the opt-in escape hatch to
pull any single exporter into Influx when there is a reason to.

When volume eventually grows from "AI CLI" to "many apps", three already-designed
knobs activate: the B2 cold-archive lifecycle stops being hypothetical, the
collector scales (single replica → HPA or agent+gateway split), and retention
tuning/downsampling matters more. None require redesign.

## Transition (nothing to migrate)

The existing WSL2 memory/token tracking is a **short-lived sizing exercise** — it
exists only to validate this week's resource usage so we can right-size the move
of the dev environment out of WSL2 and into k8s. It self-retires around the
coming weekend (Sun/Mon) and the `vitals` v2 `claude-code` bucket goes away with
it. So there is no cutover to manage: the new plane is built fresh, nothing
depends on the old pipe, and the throwaway dashboard is not migrated.

## Prerequisites

1. A free **InfluxDB 3 Enterprise at-home license key** (email signup).
2. A Ceph RGW bucket via `ObjectBucketClaim` (`ceph-bucket` storage class).
3. The OTLP bearer token, stored in 1Password → ExternalSecret, alongside any
   Influx admin token.
4. A **Cilium LoadBalancer IP** from the existing pool for the collector's LAN
   service.
5. A **Cloudflare Tunnel hostname** (e.g. `otel.<domain>`) on the existing
   `cloudflared` ingress, plus a **Cloudflare Access application + service token**
   protecting it — provisioned with the account-scoped Cloudflare token per the
   usual per-account rule.

## GitOps layout

Follows the existing app structure:

```
kubernetes/apps/observability/
  otel-collector/   ks.yaml + app/{helmrelease,externalsecret,kustomization}.yaml
                    + collector config + LB service (Cilium annotation) + httproute (cloudflared off-LAN)
kubernetes/apps/database/
  influxdb3/        ks.yaml + app/{helmrelease or statefulset, pvc, objectbucketclaim, externalsecret, kustomization}.yaml
```

Grafana gains an InfluxDB-v3 (SQL) datasource; the existing Flux datasource and
`devpod-telemetry` dashboard are left in place during transition.

## Out of scope (future specs / projects)

- **Tempo + app instrumentation** — spec 3.
- **Website exposure** — spec 2.
- **B2 cold-archive lifecycle** — only if Ceph growth demands it.
- **Migrating the WSL2 script onto OTLP** — happens at devpod cutover.
- **The devpod-in-cluster move itself** — its own project; the backbone is built
  so the devpod just sets `OTEL_EXPORTER_OTLP_ENDPOINT` to the ClusterIP.
- **Retiring kube-prometheus-stack** — explicitly not a goal.
```
