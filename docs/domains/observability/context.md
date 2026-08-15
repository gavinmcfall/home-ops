---
description: "Observability — LLM context: apps, routes, storage, flows"
tags: ["Observability", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# Observability — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [blackbox-exporter](../../../kubernetes/apps/observability/exporters/blackbox-exporter) | observability | prometheus-blackbox-exporter (community chart) | none | none | none | none | none |
| [discord-message-scheduler](../../../kubernetes/apps/observability/discord-message-scheduler) | observability | app-template / ghcr.io/gavinmcfall/discord-message-scheduler | none | ceph-block 1Gi | none | onepassword-connect | external-secrets/external-secrets-stores |
| [exportarr-radarr](../../../kubernetes/apps/observability/exporters/exportarr-radarr) | observability | app-template / ghcr.io/onedr0p/exportarr | none | none | none | onepassword-connect | downloads/radarr |
| [exportarr-sonarr](../../../kubernetes/apps/observability/exporters/exportarr-sonarr) | observability | app-template / ghcr.io/onedr0p/exportarr | none | none | none | onepassword-connect | downloads/sonarr |
| [gatus](../../../kubernetes/apps/observability/gatus) | observability | app-template / ghcr.io/twin/gatus | status.${SECRET_DOMAIN} · external | none | none | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores |
| [grafana](../../../kubernetes/apps/observability/grafana) | observability | grafana (official chart) / grafana/grafana | grafana.${SECRET_DOMAIN} · external | none | none | onepassword-connect | external-secrets/external-secrets-stores |
| [graphite-exporter](../../../kubernetes/apps/observability/exporters/graphite-exporter) | observability | app-template / prom/graphite-exporter | none | none | none | none | none |
| [intel-gpu-exporter](../../../kubernetes/apps/observability/exporters/intel-gpu-exporter) | observability | app-template / ghcr.io/onedr0p/intel-gpu-exporter | none | none | none | none | none |
| [ipmi-exporter](../../../kubernetes/apps/observability/exporters/ipmi-exporter) | observability | app-template / quay.io/prometheuscommunity/ipmi-exporter | none | none | none | onepassword-connect | none |
| [jetkvm-power](../../../kubernetes/apps/observability/exporters/jetkvm-power) | observability | raw manifests / external (JetKVM native metrics, no in-cluster pod) | none | none | none | none | none |
| [kait](../../../kubernetes/apps/observability/kait) | observability | OCIRepository / ghcr.io/gavinmcfall/kait | none | none | none | onepassword-connect | observability/kube-prometheus-stack |
| [keda](../../../kubernetes/apps/observability/keda) | observability | OCIRepository (keda chart) | none | none | none | none | none |
| [kromgo](../../../kubernetes/apps/observability/kromgo) | observability | app-template / ghcr.io/kashalls/kromgo | kromgo.${SECRET_DOMAIN} · external | none | none | none | none |
| [kube-prometheus-stack](../../../kubernetes/apps/observability/kube-prometheus-stack) | observability | kube-prometheus-stack (community chart) / prompp/prompp (Prometheus image override) | alertmanager.${SECRET_DOMAIN}, prometheus.${SECRET_DOMAIN} · internal | openebs-hostpath 75Gi (prometheus) + openebs-hostpath 1Gi (alertmanager) | none | onepassword-connect | observability/prometheus-operator-crds, openebs-system/openebs |
| [loki](../../../kubernetes/apps/observability/loki) | observability | loki (grafana chart) | none | openebs-hostpath 50Gi | none | none | openebs-system/openebs |
| [mariadb-exporter](../../../kubernetes/apps/observability/exporters/mariadb-exporter) | database | raw manifests / docker.io/bitnami/mysqld-exporter | none | none | none | none | database/mariadb |
| [network-ups-tools](../../../kubernetes/apps/observability/network-ups-tools) | observability | app-template / ghcr.io/jr0dd/network-ups-tools | none | none | none | none | none |
| [notifiarr](../../../kubernetes/apps/observability/notifiarr) | observability | app-template / ghcr.io/notifiarr/notifiarr | notifiarr.${SECRET_DOMAIN} · internal | ceph-block 1Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores |
| [ntfy](../../../kubernetes/apps/observability/ntfy) | observability | OCIRepository / binwiederhier/ntfy | ntfy.${SECRET_DOMAIN} · external | none | none | none | external-secrets/external-secrets-stores |
| [ntfy-alertmanager](../../../kubernetes/apps/observability/ntfy-alertmanager) | observability | OCIRepository / codeberg.org/xenrox/ntfy-alertmanager | none | none | none | none | observability/ntfy |
| [nut-exporter](../../../kubernetes/apps/observability/exporters/nut-exporter) | observability | app-template / ghcr.io/druggeri/nut_exporter | none | none | none | none | none |
| [otel-collector](../../../kubernetes/apps/observability/otel-collector) | observability | opentelemetry-collector (chart) / otel/opentelemetry-collector-contrib | otel.${SECRET_DOMAIN} · external + LoadBalancer IP (OTLP gRPC/HTTP, in-cluster/LAN) | none | none | onepassword-connect | database/influxdb3 |
| [plex-exporter](../../../kubernetes/apps/observability/exporters/plex-exporter) | observability | app-template / ghcr.io/timothystewart6/prometheus-plex-exporter | none | none | none | onepassword-connect | entertainment/plex |
| [prometheus-operator-crds](../../../kubernetes/apps/observability/prometheus-operator-crds) | observability | prometheus-operator-crds (community chart, CRDs only) | none | none | none | none | none |
| [promtail](../../../kubernetes/apps/observability/promtail) | observability | promtail (grafana chart) | none | none | none | none | none |
| [redisinsight](../../../kubernetes/apps/observability/redisinsight) | observability | app-template / redis/redisinsight | redisinsight.${SECRET_DOMAIN} · internal | ceph-block 1Gi | VolSync | none | database/dragonfly-operator, storage/volsync |
| [smartctl-exporter](../../../kubernetes/apps/observability/exporters/smartctl-exporter) | observability | prometheus-smartctl-exporter (community chart) | none | none | none | none | none |
| [snmp-exporter](../../../kubernetes/apps/observability/exporters/snmp-exporter) | observability | prometheus-snmp-exporter (community chart) | none | none | none | onepassword-connect | none |
| [speedtest-exporter](../../../kubernetes/apps/observability/exporters/speedtest-exporter) | observability | app-template / ghcr.io/miguelndecarvalho/speedtest-exporter | none | none | none | none | none |
| [tautulli-exporter](../../../kubernetes/apps/observability/exporters/tautulli-exporter) | observability | app-template / nwalke/tautulli_exporter | none | none | none | none | entertainment/tautulli |
| [truenas-capacity](../../../kubernetes/apps/observability/exporters/truenas-capacity) | observability | raw CronJob / alpine:3.24 (curl+jq push script) | none | none | none | sops | none |
| [unpoller](../../../kubernetes/apps/observability/unpoller) | observability | app-template / ghcr.io/unpoller/unpoller | none | none | none | onepassword-connect | observability/kube-prometheus-stack |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

32 apps in this domain exceed the 12-node diagram limit, so the data flow is split into three diagrams: Core Platform & Alerting, Hardware Exporters, and App & Service Exporters. `kube-prometheus-stack` is the shared hub and appears in all three.

### Core Platform & Alerting

```mermaid
flowchart LR
    subgraph Logs["Logs"]
        promtail["promtail"]
        loki["loki"]
    end

    subgraph Metrics["Metrics"]
        kube_prometheus_stack["kube-prometheus-stack"]
        kromgo["kromgo"]
        gatus["gatus"]
        unpoller["unpoller"]
    end

    grafana["grafana"]

    subgraph Alerting["Alerting"]
        kait["kait"]
        ntfy_alertmanager["ntfy-alertmanager"]
        ntfy["ntfy"]
    end

    promtail --> loki
    loki --> grafana
    kube_prometheus_stack --> grafana
    kube_prometheus_stack --> kromgo
    gatus --> kube_prometheus_stack
    unpoller --> kube_prometheus_stack
    kube_prometheus_stack -->|webhook| kait
    kube_prometheus_stack -->|webhook| ntfy_alertmanager
    ntfy_alertmanager -->|silence/read| kube_prometheus_stack
    ntfy_alertmanager --> ntfy

    classDef logs fill:#81D4FA,stroke:#0277BD,color:#000
    classDef metrics fill:#90EE90,stroke:#2E7D32,color:#000
    classDef dashboard fill:#FFE082,stroke:#F57C00,color:#000
    classDef alerting fill:#FFB6C1,stroke:#C62828,color:#000

    class promtail,loki logs
    class kube_prometheus_stack,kromgo,gatus,unpoller metrics
    class grafana dashboard
    class kait,ntfy_alertmanager,ntfy alerting

    %% MEANING: Core observability platform -- promtail ships logs to loki; kube-prometheus-stack (Prometheus+Alertmanager) is the metrics hub, scraping gatus/unpoller and queried by kromgo; grafana reads both loki and kube-prometheus-stack; Alertmanager fires webhooks to kait (Ceph Thunderbolt-network auto-failover) and ntfy-alertmanager (which also reads Alertmanager's API to silence, then forwards to ntfy)
    %% COLOR: Blue = logs, Green = metrics, Yellow = dashboard, Red = alerting/notification
    %% GOTCHA: discord-message-scheduler, keda, notifiarr, otel-collector, prometheus-operator-crds, and redisinsight have no manifest-declared edge to any other app in this diagram -- notifiarr and otel-collector integrate with apps in OTHER domains (see Integration Points), keda/prometheus-operator-crds are pure Flux dependencies (see the Apps table's DependsOn column), and discord-message-scheduler/redisinsight are standalone. Hardware and app-specific exporters are split into two further diagrams below to stay under the 12-node limit across 32 apps in this domain.
    %% NAVIGATION: Left-to-right -- logs and metrics pipelines feed grafana; kube-prometheus-stack's Alertmanager fans out to the alerting group on the right
```

### Hardware Exporters

```mermaid
flowchart LR
    subgraph Probes["Direct Probes"]
        blackbox_exporter["blackbox-exporter"]
        intel_gpu_exporter["intel-gpu-exporter"]
        ipmi_exporter["ipmi-exporter"]
        jetkvm_power["jetkvm-power"]
        smartctl_exporter["smartctl-exporter"]
        snmp_exporter["snmp-exporter"]
    end

    subgraph Power["Power Chain"]
        network_ups_tools["network-ups-tools"]
        nut_exporter["nut-exporter"]
    end

    subgraph Push["Push Bridge"]
        truenas_capacity["truenas-capacity"]
        graphite_exporter["graphite-exporter"]
    end

    kube_prometheus_stack["kube-prometheus-stack"]

    blackbox_exporter --> kube_prometheus_stack
    intel_gpu_exporter --> kube_prometheus_stack
    ipmi_exporter --> kube_prometheus_stack
    jetkvm_power --> kube_prometheus_stack
    smartctl_exporter --> kube_prometheus_stack
    snmp_exporter --> kube_prometheus_stack
    network_ups_tools --> nut_exporter
    nut_exporter --> kube_prometheus_stack
    truenas_capacity --> graphite_exporter
    graphite_exporter --> kube_prometheus_stack

    classDef probe fill:#81D4FA,stroke:#0277BD,color:#000
    classDef power fill:#FFE082,stroke:#F57C00,color:#000
    classDef push fill:#E1BEE7,stroke:#6A1B9A,color:#000
    classDef hub fill:#90EE90,stroke:#2E7D32,color:#000

    class blackbox_exporter,intel_gpu_exporter,ipmi_exporter,jetkvm_power,smartctl_exporter,snmp_exporter probe
    class network_ups_tools,nut_exporter power
    class truenas_capacity,graphite_exporter push
    class kube_prometheus_stack hub

    %% MEANING: Hardware/infra exporters feeding kube-prometheus-stack (repeated hub node from the Core Platform diagram) -- most probe hardware directly and get scraped; network-ups-tools' NUT protocol is polled by nut-exporter; truenas-capacity pushes gauges into graphite-exporter (a receiver, not a scraper) on a 5-minute CronJob
    %% COLOR: Blue = direct-probe exporters, Yellow = UPS power chain, Purple = push-based bridge, Green = the shared hub
    %% GOTCHA: this is 1 of 3 observability dataflow diagrams (Core Platform, Hardware Exporters, App/Service Exporters) -- split because 32 apps in this domain can't fit one 12-node diagram. kube-prometheus-stack is the same node repeated across all three; jetkvm-power runs no in-cluster pod (a headless Service points at 3 JetKVM devices' native /metrics endpoints)
    %% NAVIGATION: Left-to-right -- three source groups all ultimately feed kube-prometheus-stack, either by being scraped directly or (network-ups-tools, truenas-capacity) via an intermediate exporter
```

### App & Service Exporters

```mermaid
flowchart LR
    subgraph MediaExporters["Media-Domain Exporters"]
        exportarr_radarr["exportarr-radarr"]
        exportarr_sonarr["exportarr-sonarr"]
        plex_exporter["plex-exporter"]
        tautulli_exporter["tautulli-exporter"]
    end

    subgraph Other["Other Service Exporters"]
        mariadb_exporter["mariadb-exporter"]
        speedtest_exporter["speedtest-exporter"]
    end

    kube_prometheus_stack["kube-prometheus-stack"]

    exportarr_radarr --> kube_prometheus_stack
    exportarr_sonarr --> kube_prometheus_stack
    plex_exporter --> kube_prometheus_stack
    tautulli_exporter --> kube_prometheus_stack
    mariadb_exporter --> kube_prometheus_stack
    speedtest_exporter --> kube_prometheus_stack

    classDef media fill:#81D4FA,stroke:#0277BD,color:#000
    classDef other fill:#E1BEE7,stroke:#6A1B9A,color:#000
    classDef hub fill:#90EE90,stroke:#2E7D32,color:#000

    class exportarr_radarr,exportarr_sonarr,plex_exporter,tautulli_exporter media
    class mariadb_exporter,speedtest_exporter other
    class kube_prometheus_stack hub

    %% MEANING: App/service-specific exporters feeding kube-prometheus-stack (repeated hub node) -- exportarr-radarr, exportarr-sonarr, plex-exporter, and tautulli-exporter each poll a media-domain app's API (see Integration Points for the cross-domain targets); mariadb-exporter polls the database-domain mariadb Service; speedtest-exporter is self-contained
    %% COLOR: Blue = exporters targeting the media domain, Purple = other service exporters, Green = the shared hub
    %% GOTCHA: this is 3 of 3 observability dataflow diagrams. The edges into radarr/sonarr/plex/tautulli themselves are NOT drawn here (they're cross-domain, out of this diagram's scope) -- only the in-domain "scraped by kube-prometheus-stack" edge is shown; see Integration Points for exportarr-radarr/exportarr-sonarr/plex-exporter/tautulli-exporter's actual polling targets
    %% NAVIGATION: Left-to-right -- both exporter groups feed the same shared metrics hub
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- auth: [grafana](../../../kubernetes/apps/observability/grafana) authenticates against pocket-id via generic OAuth (`auth_url`/`token_url`/`api_url` pointing at `id.${SECRET_DOMAIN}`) per its HelmRelease.
- downloads: [notifiarr](../../../kubernetes/apps/observability/notifiarr) monitors [qbittorrent](../../../kubernetes/apps/downloads/qbittorrent), [sabnzbd](../../../kubernetes/apps/downloads/sabnzbd), and [prowlarr](../../../kubernetes/apps/downloads/prowlarr) via API keys pulled into its ExternalSecret.
- media: [exportarr-radarr](../../../kubernetes/apps/observability/exporters/exportarr-radarr) polls [radarr](../../../kubernetes/apps/downloads/radarr) and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) via their `URL`/`APIKEY` env.
- media: [exportarr-sonarr](../../../kubernetes/apps/observability/exporters/exportarr-sonarr) polls [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), and [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign) via their `URL`/`APIKEY` env.
- media: [notifiarr](../../../kubernetes/apps/observability/notifiarr) monitors [plex](../../../kubernetes/apps/entertainment/plex), [tautulli](../../../kubernetes/apps/entertainment/tautulli), [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [radarr](../../../kubernetes/apps/downloads/radarr), and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) via API keys pulled into its ExternalSecret.
- media: [plex-exporter](../../../kubernetes/apps/observability/exporters/plex-exporter) polls [plex](../../../kubernetes/apps/entertainment/plex) via `PLEX_SERVER` env.
- media: [tautulli-exporter](../../../kubernetes/apps/observability/exporters/tautulli-exporter) polls [tautulli](../../../kubernetes/apps/entertainment/tautulli) via `TAUTULLI_URI` env.
<!-- generated:end -->

<!-- curated -->
## Capsules

### KSM Collector Expansion & GPU Exporter Swap (2026-05 audit)

`docs/observability-audit-2026-05.md` expanded kube-state-metrics from 3 to 17 collector families (adding PVC/PV/StatefulSet/DaemonSet/ReplicaSet/Service/Endpoint/Namespace/Job/CronJob/Ingress/StorageClass/HPA/PDB), fixed node-exporter and promtail to tolerate the GPU node's taint so pyro-01 is covered, and fixed a kromgo staleness bug (`last_over_time(...[2h])` wrapper) caused by Prometheus's 5-minute instant-query lookback outrunning speedtest-exporter's hourly scrape. It also swapped a crash-looping `dcgm-exporter` (actually OOMKilled at a too-tight 256Mi limit, not a Pascal-incompatibility as first suspected) for `nvidia-gpu-exporter` (NVML-based, ~30MiB idle).
<!-- seeded: review -->

### Live-Repo Discrepancy: nvidia-gpu-exporter Not Present

The audit above documents deploying `kubernetes/apps/observability/exporters/nvidia-gpu-exporter/`, but no such directory exists in the current tree — only `intel-gpu-exporter` (for the stantons' Intel iGPUs) does. Treat the nvidia-gpu-exporter section of the audit as historical/reverted rather than current state; verify against the live manifest tree before assuming pyro-01 NVIDIA GPU metrics are flowing.
<!-- seeded: review -->

### OTel Telemetry Backbone (spec 1 of 3)

`otel-collector` is a separate, push-based ingestion plane from kube-prometheus-stack, not a replacement for it — Prometheus stays the Kubernetes-infra (node/cAdvisor/KSM/exporter-wall) pull-based plane; otel-collector carries application, AI-CLI, and (later) trace telemetry into InfluxDB 3 (database domain), which persists Parquet directly to an in-cluster Ceph RGW bucket rather than Backblaze B2 (B2 is deferred to cold-archive-only, to avoid egress/latency on the hot compaction/query path). InfluxDB 3 Enterprise was chosen over Core specifically because Core caps query windows at 72 hours.
<!-- seeded: review -->

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
