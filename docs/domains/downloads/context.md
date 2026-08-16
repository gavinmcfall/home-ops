---
description: "Downloads Infrastructure — LLM context: apps, routes, storage, flows"
tags: ["Downloads", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# Downloads Infrastructure — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [autobrr](../../../kubernetes/apps/downloads/autobrr) | downloads | app-template / ghcr.io/autobrr/autobrr | autobrr.${SECRET_DOMAIN} · internal | none | none | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores |
| [cross-seed](../../../kubernetes/apps/downloads/cross-seed) | downloads | app-template / ghcr.io/cross-seed/cross-seed | none | ceph-block 5Gi | none | onepassword-connect | rook-ceph/cluster-apps-rook-ceph-cluster |
| [dashbrr](../../../kubernetes/apps/downloads/dashbrr) | downloads | app-template / ghcr.io/autobrr/dashbrr | dashbrr.${SECRET_DOMAIN} · internal | none | none | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores |
| [flaresolverr](../../../kubernetes/apps/downloads/flaresolverr) | downloads | app-template / ghcr.io/flaresolverr/flaresolverr | none | none | none | none | none |
| [metube](../../../kubernetes/apps/downloads/metube) | downloads | app-template / ghcr.io/alexta69/metube | metube.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | none | storage/volsync |
| [prowlarr](../../../kubernetes/apps/downloads/prowlarr) | downloads | app-template / ghcr.io/home-operations/prowlarr | prowlarr.${SECRET_DOMAIN} · internal | none | none | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores |
| [qbittorrent](../../../kubernetes/apps/downloads/qbittorrent) | downloads | app-template / ghcr.io/home-operations/qbittorrent | qb.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | storage/volsync |
| [qui](../../../kubernetes/apps/downloads/qui) | downloads | app-template / ghcr.io/autobrr/qui | qui.${SECRET_DOMAIN} · internal | ceph-block 5Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [sabnzbd](../../../kubernetes/apps/downloads/sabnzbd) | downloads | app-template / ghcr.io/home-operations/sabnzbd | sab.${SECRET_DOMAIN} · internal | ceph-block 1Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [slskd](../../../kubernetes/apps/downloads/slskd) | downloads | app-template / ghcr.io/slskd/slskd | slskd.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [tqm](../../../kubernetes/apps/downloads/tqm) | downloads | app-template / ghcr.io/home-operations/tqm | none | none | none | onepassword-connect | downloads/qbittorrent |
| [unpackerr](../../../kubernetes/apps/downloads/unpackerr) | downloads | app-template / ghcr.io/unpackerr/unpackerr | none | none | none | onepassword-connect | external-secrets/external-secrets-stores |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

```mermaid
flowchart LR
    subgraph Indexing["Indexing & Automation"]
        autobrr["autobrr"]
        cross_seed["cross-seed"]
        dashbrr["dashbrr"]
        prowlarr["prowlarr"]
    end

    subgraph Clients["Download Clients"]
        qbittorrent["qbittorrent"]
        sabnzbd["sabnzbd"]
        slskd["slskd"]
    end

    subgraph Operators["Post-Processing Operators"]
        tqm["tqm"]
        unpackerr["unpackerr"]
    end

    subgraph Utilities["Standalone Utilities"]
        flaresolverr["flaresolverr"]
        metube["metube"]
        qui["qui"]
    end

    cross_seed --> qbittorrent
    dashbrr --> prowlarr
    prowlarr --> cross_seed
    qbittorrent --> tqm
    qbittorrent --> unpackerr

    classDef indexing fill:#81D4FA,stroke:#0277BD,color:#000
    classDef client fill:#90EE90,stroke:#2E7D32,color:#000
    classDef operator fill:#FFE082,stroke:#F57C00,color:#000
    classDef utility fill:#E0E0E0,stroke:#616161,color:#000

    class autobrr,cross_seed,dashbrr,prowlarr indexing
    class qbittorrent,sabnzbd,slskd client
    class tqm,unpackerr operator
    class flaresolverr,metube,qui utility

    %% MEANING: Downloads domain data flow -- indexers feed release automation, which pushes releases to torrent clients, whose completed downloads are read by post-processing operators
    %% COLOR: Blue = indexing/automation, Green = download clients, Yellow = post-processing operators, Gray = standalone utilities
    %% GOTCHA: autobrr, flaresolverr, metube, qui, sabnzbd, and slskd have no manifest-declared edge to any other in-domain app -- no config file in any of their manifests references another downloads app, so no data-flow line is drawn for them here
    %% NAVIGATION: Left-to-right -- indexing/automation feeds qbittorrent, whose output is consumed by operators; sabnzbd/slskd are grouped with qbittorrent by role (download clients) but carry no drawn edges; utilities sit apart with no modeled edges
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- auth (outbound): [dashbrr](../../../kubernetes/apps/downloads/dashbrr) and [qui](../../../kubernetes/apps/downloads/qui) authenticate against pocket-id (`OIDC_ISSUER`/`QUI__OIDC_ISSUER` env pointing at `id.${SECRET_DOMAIN}`) per their ExternalSecret templates.
- media (outbound): [cross-seed](../../../kubernetes/apps/downloads/cross-seed) injects cross-seed matches into [radarr](../../../kubernetes/apps/downloads/radarr)/[radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd)/[sonarr](../../../kubernetes/apps/downloads/sonarr)/[sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd)/[sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign) via its ExternalSecret-templated `config.js`.
- media (outbound): [dashbrr](../../../kubernetes/apps/downloads/dashbrr) dashboards [radarr](../../../kubernetes/apps/downloads/radarr), [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd), [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [seerr](../../../kubernetes/apps/entertainment/seerr), and [plex](../../../kubernetes/apps/entertainment/plex) via API keys pulled into its ExternalSecret.
- media (outbound): [unpackerr](../../../kubernetes/apps/downloads/unpackerr) notifies [sonarr](../../../kubernetes/apps/downloads/sonarr), [sonarr-uhd](../../../kubernetes/apps/downloads/sonarr-uhd), [sonarr-foreign](../../../kubernetes/apps/downloads/sonarr-foreign), [radarr](../../../kubernetes/apps/downloads/radarr), and [radarr-uhd](../../../kubernetes/apps/downloads/radarr-uhd) after extracting completed archives, per its HelmRelease env.
- observability (outbound): [autobrr](../../../kubernetes/apps/downloads/autobrr) ships an `autobrr-loki-rules` ConfigMap labeled `loki_rule: "true"` containing LogQL alerting rules, per its Kustomization `configMapGenerator`.
- reading (inbound): [flaresolverr](../../../kubernetes/apps/downloads/flaresolverr) is used by [suwayomi](../../../kubernetes/apps/downloads/suwayomi) and [tranga](../../../kubernetes/apps/downloads/tranga) to solve Cloudflare/DDoS-Guard challenges (`server.flareSolverrUrl`/`FLARESOLVERR_URL` pointing at `flaresolverr.downloads.svc.cluster.local:8191`), per their HelmRelease (see [reading domain](../reading/context.md)).
<!-- generated:end -->

<!-- curated -->
## Capsules

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
