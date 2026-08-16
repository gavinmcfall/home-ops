---
description: "Movies & TV — human overview: what it is, how it fits together, how to operate it"
tags: ["Media", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# Movies & TV

<!-- generated:start section=summary -->
The Movies & TV domain runs 14 apps across the downloads and entertainment namespaces.

## Components

| App | What it does | UI |
|---|---|---|
| arr-codec-tagger | Weekly CronJob that tags Sonarr/Radarr libraries with codec metadata via the kait image | internal (CronJob, no UI) |
| bazarr | Subtitle Downloads | https://bazarr.${SECRET_DOMAIN} |
| bazarr-foreign | Subtitle Downloads (Foreign) | https://bazarr-foreign.${SECRET_DOMAIN} |
| bazarr-uhd | Subtitle Downloads (UHD) | https://bazarr-uhd.${SECRET_DOMAIN} |
| plex | Media Player | https://plex.${SECRET_DOMAIN} |
| radarr | Movie Downloads | https://radarr.${SECRET_DOMAIN} |
| radarr-uhd | UHD Movie Downloads | https://radarr-uhd.${SECRET_DOMAIN} |
| recyclarr | Daily CronJob that syncs TRaSH Guides quality profiles and custom formats into Sonarr/Radarr | internal (CronJob, no UI) |
| seerr | Media Request Management | https://requests.${SECRET_DOMAIN} |
| sonarr | TV Downloads | https://sonarr.${SECRET_DOMAIN} |
| sonarr-foreign | Foreign TV Downloads | https://sonarr-foreign.${SECRET_DOMAIN} |
| sonarr-uhd | UHD TV Downloads | https://sonarr-uhd.${SECRET_DOMAIN} |
| tautulli | Plex Stream Monitoring | https://tautulli.${SECRET_DOMAIN} |
| wizarr | Plex Invite Management | https://join.${SECRET_DOMAIN} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

```mermaid
flowchart TB
    subgraph Sources["Automation & Downloads Handoff"]
        arr_codec_tagger["arr-codec-tagger"]
        recyclarr["recyclarr"]
        downloads_boundary["Downloads Domain"]
    end

    subgraph Arrs["Arr Instances"]
        radarr["radarr"]
        radarr_uhd["radarr-uhd"]
        sonarr["sonarr"]
        sonarr_foreign["sonarr-foreign"]
        sonarr_uhd["sonarr-uhd"]
    end

    subgraph FrontEnd["Front End"]
        plex["plex"]
        seerr["seerr"]
        tautulli["tautulli"]
        wizarr["wizarr"]
    end

    arr_codec_tagger --> radarr & radarr_uhd & sonarr & sonarr_foreign & sonarr_uhd
    recyclarr --> radarr & radarr_uhd & sonarr & sonarr_foreign & sonarr_uhd
    downloads_boundary --> radarr & radarr_uhd & sonarr & sonarr_foreign & sonarr_uhd

    click downloads_boundary href "../downloads/context.md" "Downloads domain"

    classDef automation fill:#81D4FA,stroke:#0277BD,color:#000
    classDef arr fill:#90EE90,stroke:#2E7D32,color:#000
    classDef boundary fill:#FFE082,stroke:#F57C00,color:#000
    classDef frontend fill:#E0E0E0,stroke:#616161,color:#000

    class arr_codec_tagger,recyclarr automation
    class radarr,radarr_uhd,sonarr,sonarr_foreign,sonarr_uhd arr
    class downloads_boundary boundary
    class plex,seerr,tautulli,wizarr frontend

    %% MEANING: Media domain request/automation flow -- arr-codec-tagger and recyclarr push per-instance updates into the 5 arr instances; the downloads domain (cross-seed injection, unpackerr extraction notify -- see downloads/context.md) also feeds the same 5 arr instances
    %% COLOR: Blue = automation, Green = arr instances, Orange = downloads-domain boundary (external link), Gray = front-end apps
    %% GOTCHA: plex, seerr, tautulli, and wizarr have no manifest-declared edge to any other in-domain app -- arr/Plex integration for these four is configured via each app's runtime UI (Seerr's Radarr/Sonarr server settings, Tautulli's Plex server, Wizarr's Plex/Seerr integration), not exposed in any manifest, so no edge is drawn. bazarr, bazarr-foreign, and bazarr-uhd are omitted from this diagram (see the Subtitle Instances diagram below) to stay under the 12-node limit with 14 apps in the domain.
    %% NAVIGATION: Top-to-bottom -- automation and the downloads-domain boundary both feed the arr instances; front-end apps sit apart with no manifest-modeled edges into the arr layer
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

<!-- curated -->
## Operating Notes

Plex, Tautulli, and the arr instances are scraped for metrics by dedicated exporters in the observability domain (`plex-exporter`, `tautulli-exporter`, `exportarr-sonarr`, `exportarr-radarr`) — not built into these apps. See the [observability domain](../observability/overview.md) for the monitoring stack.
<!-- seeded: review -->

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
