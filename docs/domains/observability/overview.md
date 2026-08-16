---
description: "Observability — human overview: what it is, how it fits together, how to operate it"
tags: ["Observability", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# Observability

<!-- generated:start section=summary -->
The Observability domain runs 32 apps owned by the observability directory tree; mariadb-exporter deploys into the database namespace.

## Components

| App | What it does | UI |
|---|---|---|
| blackbox-exporter | Probes ICMP/TCP/HTTP endpoints (NAS, NFS port) for reachability | internal (no route) |
| discord-message-scheduler | Discord bot for scheduling recurring messages | internal (no route) |
| exportarr-radarr | Prometheus exporter for the radarr/radarr-uhd Radarr instances | internal (no route) |
| exportarr-sonarr | Prometheus exporter for the sonarr/sonarr-uhd/sonarr-foreign Sonarr instances | internal (no route) |
| gatus | Status Page | https://status.${SECRET_DOMAIN} |
| grafana | Monitoring Dashboards | https://grafana.${SECRET_DOMAIN} |
| graphite-exporter | Receives pushed Graphite-protocol gauges and re-exposes them as Prometheus metrics | internal (LoadBalancer IP, no route) |
| intel-gpu-exporter | Prometheus exporter for Intel iGPU metrics on the stanton nodes | internal (no route) |
| ipmi-exporter | Prometheus exporter that polls BMC/IPMI sensors over the network | internal (no route) |
| jetkvm-power | Scrapes native Prometheus metrics from 3 JetKVM DC power-monitoring devices | internal (no route, no in-cluster pod) |
| kait | Webhook receiver that auto-fails the Ceph cluster network over to LAN when Thunderbolt connectivity is lost | internal (no route) |
| keda | Kubernetes event-driven autoscaling controller | internal (no route) |
| kromgo | Public-facing metrics API that queries Prometheus and re-exposes curated values | https://kromgo.${SECRET_DOMAIN} |
| kube-prometheus-stack | Monitoring Scrape Service | https://alertmanager.${SECRET_DOMAIN}, https://prometheus.${SECRET_DOMAIN} |
| loki | Log aggregation backend for promtail-shipped cluster logs | internal (no route) |
| mariadb-exporter | Prometheus exporter for the database-domain MariaDB instance | internal (no route) |
| network-ups-tools | NUT server exposing UPS status over the network | internal (LoadBalancer IP, no route) |
| notifiarr | Notification Service | https://notifiarr.${SECRET_DOMAIN} |
| ntfy | Self-hosted push notification server | https://ntfy.${SECRET_DOMAIN} |
| ntfy-alertmanager | Bridges Alertmanager webhooks into ntfy push notifications | internal (no route) |
| nut-exporter | Prometheus exporter that polls network-ups-tools for UPS metrics | internal (no route) |
| otel-collector | OpenTelemetry Collector -- ingests OTLP telemetry and exports it to InfluxDB 3 | https://otel.${SECRET_DOMAIN} |
| plex-exporter | Prometheus exporter for Plex library/server metrics (TechnoTim's fork) | internal (no route) |
| prometheus-operator-crds | Prometheus Operator CustomResourceDefinitions (Probe, ServiceMonitor, PrometheusRule, etc.) | internal (no route, CRDs only) |
| promtail | Ships container logs to Loki | internal (no route) |
| redisinsight | Developer GUI for Redis | https://redisinsight.${SECRET_DOMAIN} |
| smartctl-exporter | Prometheus exporter for disk S.M.A.R.T. health, auto-scanning each node's drives | internal (no route) |
| snmp-exporter | Prometheus exporter that polls UniFi network gear (UDM Pro, switches) over SNMP | internal (no route) |
| speedtest-exporter | Runs periodic internet speed tests and exposes results as Prometheus metrics | internal (no route) |
| tautulli-exporter | Prometheus exporter for Tautulli (Plex stream monitoring) metrics | internal (no route) |
| truenas-capacity | CronJob that pushes TrueNAS storage capacity gauges into graphite-exporter | internal (no route, CronJob) |
| unpoller | Prometheus exporter for UniFi controller metrics | internal (no route) |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

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
    %% GOTCHA: this is 1 of 3 observability dataflow diagrams (Core Platform, Hardware Exporters, App/Service Exporters) -- split because 32 apps in this domain can't fit one 12-node diagram. discord-message-scheduler, keda, notifiarr, otel-collector, prometheus-operator-crds, and redisinsight have no manifest-declared edge to any other app in this diagram -- notifiarr and otel-collector integrate with apps in OTHER domains (see Integration Points), keda/prometheus-operator-crds are pure Flux dependencies (see the Apps table's DependsOn column), and discord-message-scheduler/redisinsight are standalone. Hardware and app-specific exporters are split into two further diagrams below to stay under the 12-node limit across 32 apps in this domain.
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
    %% GOTCHA: this is 2 of 3 observability dataflow diagrams (Core Platform, Hardware Exporters, App/Service Exporters) -- split because 32 apps in this domain can't fit one 12-node diagram. kube-prometheus-stack is the same node repeated across all three; jetkvm-power runs no in-cluster pod (a headless Service points at 3 JetKVM devices' native /metrics endpoints)
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
    %% GOTCHA: this is 3 of 3 observability dataflow diagrams. The edges into radarr/sonarr/plex/tautulli themselves are NOT drawn here (they're cross-domain, out of this diagram's scope) -- only the in-domain "scraped by kube-prometheus-stack" edge is shown; see context.md's Integration Points for exportarr-radarr/exportarr-sonarr/plex-exporter/tautulli-exporter's actual polling targets
    %% NAVIGATION: Left-to-right -- both exporter groups feed the same shared metrics hub
```
<!-- generated:end -->

<!-- curated -->
## Operating Notes

`kube-prometheus-stack` is the hub nearly everything in this domain feeds into or reads from — check it first when metrics, dashboards, or alerts look wrong. Alertmanager's `ceph-network-failover` receiver drives `kait`'s automatic Ceph-network failover to LAN on Thunderbolt isolation; it currently runs in `DRY_RUN` mode. The 2026-05 audit's `dcgm-exporter` → `nvidia-gpu-exporter` swap does not appear to be live in the current manifest tree — see the capsule flagging this in [context.md](context.md) before assuming pyro-01 GPU metrics are flowing.
<!-- seeded: review -->

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
