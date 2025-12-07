# Plex & Arr Monitoring Stack

Implementation guide for Prometheus-based monitoring of Plex and the arr stack, adapted from [TechnoTim's plex-monitoring-stack](https://github.com/timothystewart6/plex-monitoring-stack).

## TechnoTim's Stack Components

From his [plex-monitoring-stack repo](https://github.com/timothystewart6/plex-monitoring-stack):

| Component | Image | Port | Purpose |
|-----------|-------|------|---------|
| prometheus-plex-exporter | `ghcr.io/timothystewart6/prometheus-plex-exporter` | 9000 | Plex metrics |
| node-exporter | `quay.io/prometheus/node-exporter` | 9100 | System metrics |
| dcgm-exporter | `nvidia/dcgm-exporter` | 9400 | NVIDIA GPU metrics |
| smartctl-exporter | `quay.io/prometheuscommunity/smartctl-exporter` | 9633 | Disk health |
| cadvisor | `gcr.io/cadvisor/cadvisor` | 8080 | Container metrics |

**Custom Dashboards** (in his repo):
- `plex.json` - Plex Dashboard
- `plex-streaming.json` - Plex Streaming Dashboard
- `server.json` - Server metrics
- `gpu.json` - GPU metrics
- `storage.json` - Storage/disk health
- `container.json` - Container metrics
- `thermals.json` - Temperature monitoring

**Key insight**: Tim uses his own [prometheus-plex-exporter](https://github.com/timothystewart6/prometheus-plex-exporter) fork with custom dashboards, NOT the generic Grafana registry dashboards.

---

## Current State

| Component | Status | Location |
|-----------|--------|----------|
| Plex | Deployed | `entertainment` namespace, LB IP `10.90.3.206` |
| Tautulli | Deployed | `entertainment` namespace (v2.16.0) |
| Sonarr | 3 instances | `downloads`: sonarr, sonarr-uhd, sonarr-foreign |
| Radarr | 2 instances | `downloads`: radarr, radarr-uhd |
| Prometheus | Deployed | `observability` namespace, ServiceMonitor discovery |
| Grafana | Deployed | Dashboard auto-provisioning via ConfigMaps |

**No existing monitoring** for Plex, Tautulli, Sonarr, or Radarr metrics.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Prometheus                                │
└─────────────────────────────────────────────────────────────────┘
        ▲              ▲              ▲              ▲
        │              │              │              │
   ServiceMonitor  ServiceMonitor  ServiceMonitor  ServiceMonitor
        │              │              │              │
┌───────┴───────┐ ┌────┴────┐ ┌──────┴──────┐ ┌─────┴─────┐
│ tautulli-     │ │  plex-  │ │  exportarr  │ │ exportarr │
│ exporter      │ │exporter │ │  (sonarr)   │ │ (radarr)  │
└───────┬───────┘ └────┬────┘ └──────┬──────┘ └─────┴─────┘
        │              │              │              │
        ▼              ▼              ▼              ▼
   Tautulli         Plex          Sonarr x3      Radarr x2
```

---

## Components to Deploy

### 1. tautulli-exporter
Exports Tautulli metrics (active streams, users, watch history)

- **Image**: `ghcr.io/nwalke/tautulli-exporter`
- **Port**: 9487
- **Location**: `kubernetes/apps/observability/exporters/tautulli-exporter/`

### 2. plex-exporter (TechnoTim's fork)
Exports Plex library/server metrics directly

- **Image**: `ghcr.io/timothystewart6/prometheus-plex-exporter`
- **Port**: 9000
- **Location**: `kubernetes/apps/observability/exporters/plex-exporter/`
- **Requires**: PLEX_TOKEN from 1Password
- **Env**: `PLEX_SERVER=http://plex.entertainment.svc.cluster.local:32400`

### 3. exportarr (Sonarr instances)
[onedr0p/exportarr](https://github.com/onedr0p/exportarr) - AIO exporter for arr apps

One deployment per instance:
- **exportarr-sonarr** → sonarr.downloads.svc
- **exportarr-sonarr-uhd** → sonarr-uhd.downloads.svc
- **exportarr-sonarr-foreign** → sonarr-foreign.downloads.svc

- **Image**: `ghcr.io/onedr0p/exportarr:v2.0`
- **Port**: 9707
- **Location**: `kubernetes/apps/observability/exporters/exportarr-sonarr/`

### 4. exportarr (Radarr instances)
One deployment per instance:
- **exportarr-radarr** → radarr.downloads.svc
- **exportarr-radarr-uhd** → radarr-uhd.downloads.svc

- **Image**: `ghcr.io/onedr0p/exportarr:v2.0`
- **Port**: 9708
- **Location**: `kubernetes/apps/observability/exporters/exportarr-radarr/`

### 5. Grafana Dashboards
Add to Grafana HelmRelease dashboard providers.

---

## Files to Create

```
kubernetes/apps/observability/exporters/
├── tautulli-exporter/
│   ├── ks.yaml
│   └── app/
│       ├── helmrelease.yaml
│       ├── externalsecret.yaml      # TAUTULLI_API_KEY
│       ├── servicemonitor.yaml
│       └── kustomization.yaml
│
├── plex-exporter/
│   ├── ks.yaml
│   └── app/
│       ├── helmrelease.yaml
│       ├── externalsecret.yaml      # PLEX_TOKEN
│       ├── servicemonitor.yaml
│       └── kustomization.yaml
│
├── exportarr-sonarr/
│   ├── ks.yaml
│   └── app/
│       ├── helmrelease.yaml         # 3 controllers for 3 instances
│       ├── externalsecret.yaml      # API keys for all 3
│       ├── servicemonitor.yaml
│       └── kustomization.yaml
│
└── exportarr-radarr/
    ├── ks.yaml
    └── app/
        ├── helmrelease.yaml         # 2 controllers for 2 instances
        ├── externalsecret.yaml      # API keys for both
        ├── servicemonitor.yaml
        └── kustomization.yaml
```

---

## Files to Modify

### kubernetes/apps/observability/grafana/app/helmrelease.yaml

Add dashboard folder and dashboards:

```yaml
dashboards:
  entertainment:
    # TechnoTim's custom Plex dashboards (from his repo)
    plex-dashboard:
      url: https://raw.githubusercontent.com/timothystewart6/plex-monitoring-stack/main/grafana/provisioning/dashboards/plex.json
      datasource: Prometheus
    plex-streaming:
      url: https://raw.githubusercontent.com/timothystewart6/plex-monitoring-stack/main/grafana/provisioning/dashboards/plex-streaming.json
      datasource: Prometheus
    # Exportarr dashboards for arr apps
    sonarr-dashboard:
      gnetId: 12530
      revision: 2
      datasource: Prometheus
    radarr-dashboard:
      gnetId: 12896
      revision: 1
      datasource: Prometheus
```

**Note**: Tim's dashboards are designed to work with his `prometheus-plex-exporter` fork. The generic Grafana registry dashboards (17891) may not have matching metrics.

---

## Implementation Order

1. **plex-exporter** - Direct Plex metrics
2. **tautulli-exporter** - Stream/user metrics
3. **exportarr-sonarr** - All 3 Sonarr instances
4. **exportarr-radarr** - Both Radarr instances
5. **Grafana dashboards** - Add dashboard configs

---

## Configuration Details

### tautulli-exporter HelmRelease

```yaml
controllers:
  tautulli-exporter:
    containers:
      app:
        image:
          repository: ghcr.io/nwalke/tautulli-exporter
          tag: latest  # Find pinned version
        env:
          TAUTULLI_URI: http://tautulli.entertainment.svc.cluster.local
        envFrom:
          - secretRef:
              name: tautulli-exporter-secret  # TAUTULLI_API_KEY
service:
  metrics:
    ports:
      metrics:
        port: 9487
```

### plex-exporter HelmRelease (TechnoTim's fork)

```yaml
controllers:
  plex-exporter:
    containers:
      app:
        image:
          repository: ghcr.io/timothystewart6/prometheus-plex-exporter
          tag: latest  # Find pinned version
        env:
          TZ: ${TIMEZONE}
          PLEX_SERVER: http://plex.entertainment.svc.cluster.local:32400
        envFrom:
          - secretRef:
              name: plex-exporter-secret  # PLEX_TOKEN
service:
  metrics:
    ports:
      metrics:
        port: 9000
```

### exportarr-sonarr HelmRelease (multi-instance)

```yaml
controllers:
  sonarr:
    containers:
      app:
        image:
          repository: ghcr.io/onedr0p/exportarr
          tag: v2.0.1
        args: ["sonarr"]
        env:
          PORT: "9707"
          URL: http://sonarr.downloads.svc.cluster.local
          APIKEY:
            valueFrom:
              secretKeyRef:
                name: exportarr-sonarr-secret
                key: SONARR_API_KEY
  sonarr-uhd:
    containers:
      app:
        image:
          repository: ghcr.io/onedr0p/exportarr
          tag: v2.0.1
        args: ["sonarr"]
        env:
          PORT: "9707"
          URL: http://sonarr-uhd.downloads.svc.cluster.local
          APIKEY:
            valueFrom:
              secretKeyRef:
                name: exportarr-sonarr-secret
                key: SONARR_UHD_API_KEY
  sonarr-foreign:
    # Similar pattern
```

### ServiceMonitor Pattern

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: exportarr-sonarr
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: exportarr-sonarr
  namespaceSelector:
    matchNames: [observability]
  endpoints:
    - port: metrics
      interval: 1m
      path: /metrics
```

---

## 1Password Secrets Required

| Secret Item | Keys Needed |
|------------|-------------|
| plex-exporter | `PLEX_TOKEN` |
| tautulli-exporter | `TAUTULLI_API_KEY` |
| exportarr-sonarr | `SONARR_API_KEY`, `SONARR_UHD_API_KEY`, `SONARR_FOREIGN_API_KEY` |
| exportarr-radarr | `RADARR_API_KEY`, `RADARR_UHD_API_KEY` |

---

## Sources

- [TechnoTim's plex-monitoring-stack](https://github.com/timothystewart6/plex-monitoring-stack) - Main repo with compose, dashboards, configs
- [TechnoTim's prometheus-plex-exporter](https://github.com/timothystewart6/prometheus-plex-exporter) - His custom Plex exporter
- [TechnoTim's Blog Post](https://technotim.live/posts/monitor-your-plex-server-like-a-pro/) - Original guide
- [exportarr - onedr0p](https://github.com/onedr0p/exportarr) - AIO exporter for Sonarr/Radarr/etc
- [tautulli-exporter](https://github.com/nwalke/tautulli-exporter) - Tautulli metrics exporter
- [Grafana Dashboard 12530 - Sonarr Exportarr](https://grafana.com/grafana/dashboards/12530)
- [Grafana Dashboard 12896 - Radarr Exportarr](https://grafana.com/grafana/dashboards/12896)
