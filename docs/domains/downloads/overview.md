---
description: "Downloads Infrastructure — human overview: what it is, how it fits together, how to operate it"
tags: ["Downloads", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# Downloads Infrastructure

<!-- generated:start section=summary -->
The Downloads Infrastructure domain runs 12 apps across the downloads namespace.

## Components

| App | What it does | UI |
|---|---|---|
| autobrr | IRC/RSS release automation — filters torrent/usenet announces and pushes matching releases to download clients | https://autobrr.${SECRET_DOMAIN} |
| cross-seed | Cross-seeds releases across trackers by matching new torrents against the existing library | internal (no route) |
| dashbrr | Unified dashboard aggregating status from Prowlarr, Radarr, Sonarr, Seerr, and Plex | https://dashbrr.${SECRET_DOMAIN} |
| flaresolverr | Proxy that solves Cloudflare/DDoS-Guard challenges on behalf of indexers | internal (LoadBalancer IP, no route) |
| metube | Web UI front-end for yt-dlp video downloads | https://metube.${SECRET_DOMAIN} |
| prowlarr | Torrent/NZB Indexer Management | https://prowlarr.${SECRET_DOMAIN} |
| qbittorrent | Torrent Client, routed through gluetun/ProtonVPN | https://qb.${SECRET_DOMAIN} |
| qui | Web UI for managing multiple qBittorrent instances | https://qui.${SECRET_DOMAIN} |
| sabnzbd | NZB Download Client | https://sab.${SECRET_DOMAIN} |
| slskd | Soulseek Client, routed through gluetun/ProtonVPN | https://slskd.${SECRET_DOMAIN} |
| tqm | Scheduled qBittorrent queue manager — retags and removes torrents per tracker rules | internal (CronJob, no UI) |
| unpackerr | Extracts completed archive downloads and notifies Sonarr/Radarr | internal (headless, metrics only) |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

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

<!-- curated -->
## Operating Notes

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
