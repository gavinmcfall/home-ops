---
description: Architecture and operational reference for the vitals namespace — self-hosted health data platform ingesting from 5+ device sources into InfluxDB v2
tags: [vitals, health, influxdb, telegraf, sleep, nutrition, fitness, ble, api-reverse-engineering]
audience: { human: 30, agent: 70 }
purpose: { gestalt: 40, reference: 50, design: 10 }
---

# Vitals Namespace

Self-hosted health data platform. Ingests biometric data from multiple devices into a single InfluxDB v2 time-series store for cross-correlation analysis.

## Why It Exists

Commercial health platforms silo data. Sleep quality affects training recovery. Nutrition affects sleep. CPAP compliance affects HRV. No single vendor connects these — so we built the connective tissue ourselves. Every scraper reverse-engineers an unofficial API because none of these vendors offer public data access.

## Architecture

```
┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  ┌─────────────┐
│ Apple Watch  │  │ ResMed CPAP │  │ Tempur Bed   │  │ Speediance    │  │ MyFitnessPal│
│ (via iPhone) │  │ (myAir)     │  │ (Sleeptracker│  │ GM2           │  │             │
└──────┬───────┘  └──────┬──────┘  │  AI portal)  │  └──────┬────────┘  └──────┬──────┘
       │                 │         └──────┬────────┘         │                 │
       ▼                 ▼                ▼                   ▼                 ▼
┌──────────────┐  ┌────────────┐  ┌───────────────┐  ┌───────────────┐  ┌────────────┐
│apple-health- │  │resmed-     │  │sleeptracker-  │  │speediance-    │  │mfp-influx  │
│ingester      │  │influx      │  │influx         │  │influx         │  │            │
│(HTTP webhook)│  │(poll/scrape│  │(poll/ZIP      │  │(poll/REST API)│  │(binary sync│
│              │  │ myAir API) │  │ download)     │  │              │  │ protocol)  │
└──────┬───────┘  └──────┬──────┘  └──────┬────────┘  └──────┬────────┘  └──────┬──────┘
       │                 │                │                   │                 │
       ▼                 ▼                ▼                   ▼                 ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              InfluxDB v2 — bucket: health                            │
│                              org: vitals, infinite retention                          │
└──────────────────────────────────────────────────────────────────────────────────────┘
       ▲
       │
┌──────┴───────┐
│  Telegraf    │
│  (MQTT fan-in│
│   + HTTP)    │
└──────────────┘
```

## Deployments

| App | Image | Auth Method | Data Flow | Measurements |
|-----|-------|-------------|-----------|-------------|
| **influxdb** | `influxdb:2.8.0` | N/A | Store | All |
| **telegraf** | `telegraf:1.38.1` | N/A | MQTT consumer + HTTP listener | Smartbed env sensors |
| **apple-health-ingester** | `irvinlim/apple-health-ingester:v0.5.0` | Bearer token (webhook) | iPhone → HTTP POST → InfluxDB | 69M+ points: HR, HRV, steps, sleep, respiratory, workouts |
| **resmed-influx** | `vdbg/resmed-influx:1.3` | Email/password (myAir cloud) | Poll every 60min | `cpap` |
| **sleeptracker-influx** | `ghcr.io/gavinmcfall/sleeptracker-influx:1.0.0` | Basic auth + CSRF (portal) | Bulk ZIP download every 60min | `sleep`, `sleep_cardio`, `sleep_stages`, `sleep_events` |
| **speediance-influx** | `ghcr.io/gavinmcfall/speediance-influx:1.0.2` | Email/password (REST API) | Poll every 60min | `workout`, `workout_sets`, `workout_muscles`, `strength_1rm` |
| **mfp-influx** | `ghcr.io/gavinmcfall/mfp-influx:1.0.0` | OAuth2 + binary sync protocol | Poll every 60min | `nutrition` |

## 1Password Items (vault: cluster)

| Item | Fields | Used By |
|------|--------|---------|
| `influxdb` | `INFLUXDB_ADMIN_USERNAME`, `INFLUXDB_ADMIN_PASSWORD`, `INFLUXDB_ADMIN_TOKEN` | All scrapers via `dataFrom: extract` |
| `apple-health-ingester` | `APPLE_INGESTOR_AUTH_TOKEN` | apple-health-ingester |
| `resmed-influx` | `RESMED_LOGIN`, `RESMED_PASSWORD` | resmed-influx |
| `sleeptracker-influx` | `SLEEPTRACKER_EMAIL`, `SLEEPTRACKER_PASSWORD` | sleeptracker-influx |
| `speediance-influx` | `SPEEDIANCE_EMAIL`, `SPEEDIANCE_PASSWORD` | speediance-influx |
| `mfp-influx` | `MFP_EMAIL`, `MFP_PASSWORD` | mfp-influx |
| `mosquitto` | `MOSQUITTO_USERNAME`, `MOSQUITTO_PASSWORD` | telegraf |

## Custom Container Pattern

All custom scrapers (`sleeptracker-influx`, `speediance-influx`, `mfp-influx`) follow an identical pattern:

- **Language:** Python 3.12 on Alpine
- **Config:** TOML file mounted from ExternalSecret at `/app/config.toml`, with env var overrides
- **Loop:** Configurable poll interval (default 60min), signal handling (SIGTERM/SIGINT)
- **Idempotent:** InfluxDB overwrites same timestamp+tags, safe to re-fetch
- **Resume:** Queries InfluxDB for last recorded timestamp, fetches only new data
- **Dockerfile:** `USER nobody:nogroup`, non-root, read-only root FS
- **CI:** GitHub Actions, multi-arch (amd64+arm64), semver tags, SHA digest pinning, build provenance attestation
- **k8s:** bjw-s app-template v4.4.0, `runAsUser: 568`, Recreate strategy, reloader annotation

## API Reverse Engineering Notes

### Sleeptracker AI (Tempur bed)
- Portal at `portal.tsi.sleeptracker.com` uses Basic auth + `X-CSRFToken` header
- `GET /api/downloadAccountData` returns ZIP of per-day JSON files matching the official schema
- Mobile API (`app.tsi.sleeptracker.com`) is Jetty-based device control only — no sleep data

### Speediance (Gym Monster 2)
- App decompiled via jadx from `com.speediance.speediance_mobile` APK (Flutter + native Kotlin)
- 456 API endpoints extracted from `libapp.so` strings
- Auth: `POST /api/app/v2/login/byPass` with `{userIdentity, password, type: 2}`
- **Critical:** API requires IANA timezone name (`Pacific/Auckland`), not abbreviation (`NZST`)
- **Critical:** `userTrainingDataRecord` only returns latest workout without `startDate`/`endDate` params
- Server selection: URL type 4 = `api2.speediance.com/api` (EN Formal, for NZ accounts)

### MyFitnessPal
- APK decompiled via jadx from `com.myfitnesspal.android` (native Android + Kotlin)
- OAuth2 at `api.myfitnesspal.com/v2/oauth2/token` with `client_id=mfp-mobile-android-google`
- Diary data locked behind v1 binary sync protocol at `sync.myfitnesspal.com/iphone_api/synchronize`
- Binary protocol: custom XOR-encrypted format, 10-byte packet headers, magic `0x04D3`
- **Critical:** All master IDs are 8 bytes on the wire despite Java code using `decode4ByteInt()`
- Two-step sync: initial (empty pointers) → food DB + cursors; second (with cursors) → food entries
- Identity API credentials captured via mitmproxy: `client_id=28887945-...`, `client_secret=cwia5on...`
- GraphQL at `myfitnesspal.com/v2/query-envoy/graphql` — requires `client-metadata` header (base64 JSON)

## Operational Notes

- **InfluxDB init env vars** (`DOCKER_INFLUXDB_INIT_*`) only run on first setup. Use `influx` CLI for runtime changes.
- **Telegraf** connects to Mosquitto at `mosquitto-app.database.svc.cluster.local:1883`
- **Apple Health Export** uses Health Auto Export iOS app ($49.99 NZD lifetime), v2 export format, 5-min sync cadence
- **SparkFitness** was deployed then removed — replaced by MFP for nutrition tracking (SparkFitness food search was unusable)
