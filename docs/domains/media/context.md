---
description: "Movies & TV — LLM context: apps, routes, storage, flows"
tags: ["Media", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# Movies & TV — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [arr-codec-tagger](../../../kubernetes/apps/downloads/arr-codec-tagger) | downloads | app-template / ghcr.io/gavinmcfall/kait | none | none | none | onepassword-connect | external-secrets/external-secrets-stores |
| [bazarr](../../../kubernetes/apps/downloads/bazarr) | downloads | app-template / ghcr.io/gavinmcfall/bazarr | bazarr.${SECRET_DOMAIN} · internal | ceph-block 5Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [bazarr-foreign](../../../kubernetes/apps/downloads/bazarr-foreign) | downloads | app-template / ghcr.io/gavinmcfall/bazarr | bazarr-foreign.${SECRET_DOMAIN} · internal | ceph-block 5Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [bazarr-uhd](../../../kubernetes/apps/downloads/bazarr-uhd) | downloads | app-template / ghcr.io/gavinmcfall/bazarr | bazarr-uhd.${SECRET_DOMAIN} · internal | ceph-block 5Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [plex](../../../kubernetes/apps/entertainment/plex) | entertainment | app-template / ghcr.io/home-operations/plex | plex.${SECRET_DOMAIN} · external | ceph-block 60Gi + ceph-block 75Gi (cache) | VolSync (config only) | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [radarr](../../../kubernetes/apps/downloads/radarr) | downloads | app-template / ghcr.io/home-operations/radarr | radarr.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) | downloads | app-template / ghcr.io/home-operations/radarr | radarr-uhd.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [recyclarr](../../../kubernetes/apps/downloads/recyclarr) | downloads | app-template / ghcr.io/recyclarr/recyclarr | none | ceph-block 1Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [seerr](../../../kubernetes/apps/entertainment/seerr) | entertainment | app-template / ghcr.io/seerr-team/seerr | requests.${SECRET_DOMAIN} · external | ceph-block 2Gi | VolSync | none | storage/volsync |
| [sonarr](../../../kubernetes/apps/downloads/sonarr) | downloads | app-template / ghcr.io/home-operations/sonarr | sonarr.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign) | downloads | app-template / ghcr.io/home-operations/sonarr | sonarr-foreign.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd) | downloads | app-template / ghcr.io/home-operations/sonarr | sonarr-uhd.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [tautulli](../../../kubernetes/apps/entertainment/tautulli) | entertainment | app-template / ghcr.io/tautulli/tautulli | tautulli.${SECRET_DOMAIN} · external | ceph-block 2Gi + ceph-block 15Gi (cache) | VolSync (config only) | none | storage/volsync |
| [wizarr](../../../kubernetes/apps/entertainment/wizarr) | entertainment | app-template / ghcr.io/wizarrrr/wizarr | join.${SECRET_DOMAIN} · external | ceph-block 2Gi | VolSync | none | entertainment/plex, entertainment/seerr, storage/volsync |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

```mermaid
flowchart TB
    arr_codec_tagger["arr-codec-tagger"]
    recyclarr["recyclarr"]
    downloads_boundary["Downloads Domain"]

    fanout(("all 5"))

    radarr["radarr"]
    radarr_uhd["radarr-uhd"]
    sonarr["sonarr"]
    sonarr_foreign["sonarr-foreign"]
    sonarr_uhd["sonarr-uhd"]

    subgraph FrontEnd["Front End"]
        plex["plex"]
        seerr["seerr"]
        tautulli["tautulli"]
        wizarr["wizarr"]
    end

    arr_codec_tagger --> fanout
    recyclarr --> fanout
    downloads_boundary --> fanout
    fanout --> radarr & radarr_uhd & sonarr & sonarr_foreign & sonarr_uhd

    click downloads_boundary href "../downloads/context.md" "Downloads domain"

    classDef automation fill:#81D4FA,stroke:#0277BD,color:#000
    classDef arr fill:#90EE90,stroke:#2E7D32,color:#000
    classDef boundary fill:#FFE082,stroke:#F57C00,color:#000
    classDef frontend fill:#E0E0E0,stroke:#616161,color:#000
    classDef junction fill:#ECEFF1,stroke:#607D8B,color:#000

    class arr_codec_tagger,recyclarr automation
    class radarr,radarr_uhd,sonarr,sonarr_foreign,sonarr_uhd arr
    class downloads_boundary boundary
    class plex,seerr,tautulli,wizarr frontend
    class fanout junction

    %% MEANING: Media domain request/automation flow -- arr-codec-tagger and recyclarr push per-instance updates into the 5 arr instances; the downloads domain (cross-seed injection, unpackerr extraction notify -- see downloads/context.md) also feeds the same 5 arr instances
    %% COLOR: Blue = automation, Green = arr instances, Orange = downloads-domain boundary (external link), Gray = front-end apps, small gray circle = fan-out junction (not an app)
    %% GOTCHA: the "all 5" circle is a fan-out junction, not an app -- each of the three sources above it feeds ALL five arr instances, so the 15 pairwise edges are collapsed through it for readability. plex, seerr, tautulli, and wizarr have no manifest-declared edge to any other in-domain app -- arr/Plex integration for these four is configured via each app's runtime UI (Seerr's Radarr/Sonarr server settings, Tautulli's Plex server, Wizarr's Plex/Seerr integration), not exposed in any manifest, so no edge is drawn. bazarr, bazarr-foreign, and bazarr-uhd are omitted from this diagram (see the Subtitle Instances diagram below) to stay under the 12-app-node limit with 14 apps in the domain.
    %% NAVIGATION: Top-to-bottom -- three sources converge on the fan-out junction, which feeds the arr row (unboxed so no edge can cross a group title); front-end apps sit apart with no manifest-modeled edges into the arr layer
```

### Subtitle Instances

```mermaid
flowchart LR
    bazarr["bazarr"]
    bazarr_foreign["bazarr-foreign"]
    bazarr_uhd["bazarr-uhd"]

    note["No manifest-declared arr integration -- configured via runtime UI"]:::note

    note -.- bazarr
    note -.- bazarr_foreign
    note -.- bazarr_uhd

    classDef subtitle fill:#81D4FA,stroke:#0277BD,color:#000
    classDef note fill:#F5F5F5,stroke:#9E9E9E,color:#616161,stroke-dasharray:3

    class bazarr,bazarr_foreign,bazarr_uhd subtitle

    %% MEANING: Media domain subtitle instances -- three independent Bazarr instances (standard/foreign/UHD library scopes), split from the main request-flow diagram to stay under the 12-node limit
    %% COLOR: Blue = subtitle instances, Gray dashed = note
    %% GOTCHA: bazarr, bazarr-foreign, and bazarr-uhd carry no manifest-declared edge to sonarr/radarr or to each other -- each connects to its paired arr instance via runtime UI configuration (API key entered in Bazarr's Settings > Sonarr/Radarr), not a manifest reference, so no edge is drawn
    %% NAVIGATION: Three parallel, unconnected nodes -- the note explains why no edges are drawn
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- downloads (inbound): [cross-seed](../../../kubernetes/apps/downloads/cross-seed) injects cross-seed matches into [radarr](../../../kubernetes/apps/downloads/radarr)/[radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd)/[sonarr](../../../kubernetes/apps/downloads/sonarr)/[sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd)/[sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign) via its ExternalSecret-templated `config.js` (see [downloads domain](../downloads/context.md)).
- downloads (inbound): [dashbrr](../../../kubernetes/apps/downloads/dashbrr) dashboards [radarr](../../../kubernetes/apps/downloads/radarr), [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd), [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [seerr](../../../kubernetes/apps/entertainment/seerr), and [plex](../../../kubernetes/apps/entertainment/plex) via API keys pulled into its ExternalSecret (see [downloads domain](../downloads/context.md)).
- downloads (inbound): [unpackerr](../../../kubernetes/apps/downloads/unpackerr) notifies [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [radarr](../../../kubernetes/apps/downloads/radarr), and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) after extracting completed archives, per its HelmRelease env (see [downloads domain](../downloads/context.md)).
- observability (inbound): [exportarr-radarr](../../../kubernetes/apps/observability/exporters/exportarr-radarr) polls [radarr](../../../kubernetes/apps/downloads/radarr) and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) via their `URL`/`APIKEY` env (see [observability domain](../observability/context.md)).
- observability (inbound): [exportarr-sonarr](../../../kubernetes/apps/observability/exporters/exportarr-sonarr) polls [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), and [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign) via their `URL`/`APIKEY` env (see [observability domain](../observability/context.md)).
- observability (inbound): [notifiarr](../../../kubernetes/apps/observability/notifiarr) monitors [plex](../../../kubernetes/apps/entertainment/plex), [tautulli](../../../kubernetes/apps/entertainment/tautulli), [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [radarr](../../../kubernetes/apps/downloads/radarr), and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) via API keys pulled into its ExternalSecret (see [observability domain](../observability/context.md)).
- observability (inbound): [plex-exporter](../../../kubernetes/apps/observability/exporters/plex-exporter) polls [plex](../../../kubernetes/apps/entertainment/plex) via `PLEX_SERVER` env (see [observability domain](../observability/context.md)).
- observability (inbound): [tautulli-exporter](../../../kubernetes/apps/observability/exporters/tautulli-exporter) polls [tautulli](../../../kubernetes/apps/entertainment/tautulli) via `TAUTULLI_URI` env (see [observability domain](../observability/context.md)).
- observability (outbound): [plex](../../../kubernetes/apps/entertainment/plex) ships a `plex-loki-rules` ConfigMap labeled `loki_rule: "true"` containing LogQL alerting rules, per its Kustomization `configMapGenerator`.
<!-- generated:end -->

<!-- curated -->
## Capsules

### Plex/Arr Metrics Pipeline

Prometheus scrapes plex, tautulli, sonarr (3 instances), and radarr (2 instances) via dedicated exporters that live in the observability domain (`plex-exporter`, `tautulli-exporter`, `exportarr-sonarr`, `exportarr-radarr`), not built into these apps' own images. See the [observability domain](../observability/context.md) for exporter details. TechnoTim's `prometheus-plex-exporter` fork was chosen over the generic Grafana registry Plex dashboard because the generic dashboard's metrics didn't reliably match.
<!-- seeded: review -->

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
