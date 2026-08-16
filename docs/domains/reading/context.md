---
description: "Books, Audiobooks, Comics & Manga — LLM context: apps, routes, storage, flows"
tags: ["Reading", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# Books, Audiobooks, Comics & Manga — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [audiobookshelf](../../../kubernetes/apps/entertainment/audiobookshelf) | entertainment | app-template / ghcr.io/advplyr/audiobookshelf | books.${SECRET_DOMAIN} · external | ceph-block 20Gi | VolSync | none | storage/volsync |
| [bindery](../../../kubernetes/apps/downloads/bindery) | downloads | app-template / ghcr.io/vavallee/bindery | bindery.${SECRET_DOMAIN} · internal | ceph-block 5Gi | none | none | none |
| [bookorbit](../../../kubernetes/apps/entertainment/bookorbit) | entertainment | app-template / ghcr.io/bookorbit/bookorbit | read.${SECRET_DOMAIN} · external | ceph-block 10Gi | none | onepassword-connect | database/cloudnative-pg-postgres18-bookorbit, external-secrets/external-secrets-stores |
| [calibre-web-automated](../../../kubernetes/apps/home/calibre-web-automated) | home | app-template / ghcr.io/crocodilestick/calibre-web-automated | calibre.${SECRET_DOMAIN} · internal | ceph-block 5Gi | none | onepassword-connect | none |
| [ebook-reconcile](../../../kubernetes/apps/home/ebook-reconcile) | home | app-template / ghcr.io/crocodilestick/calibre-web-automated | none | ceph-block 128Mi | none | none | home/calibre-web-automated |
| [kapowarr](../../../kubernetes/apps/downloads/kapowarr) | downloads | app-template / mrcas/kapowarr | kapowarr.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | none | storage/volsync |
| [kavita](../../../kubernetes/apps/entertainment/kavita) | entertainment | app-template / ghcr.io/kareadita/kavita | manga.${SECRET_DOMAIN} · external | ceph-block 4Gi | VolSync | none | storage/volsync |
| [komf](../../../kubernetes/apps/entertainment/komf) | entertainment | app-template / docker.io/sndxr/komf | komf.${SECRET_DOMAIN} · internal | ceph-block 1Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [lncrawl](../../../kubernetes/apps/downloads/lncrawl) | downloads | app-template / ghcr.io/lncrawl/lightnovel-crawler | lncrawl.${SECRET_DOMAIN} · internal | ceph-block 5Gi | VolSync | none | storage/volsync |
| [mangarr](../../../kubernetes/apps/entertainment/mangarr) | entertainment | app-template / ghcr.io/gavinmcfall/mangarr | mangarr.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | none | storage/volsync |
| [shelfmark](../../../kubernetes/apps/downloads/shelfmark) | downloads | app-template / ghcr.io/calibrain/shelfmark | shelfmark.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | external-secrets/external-secrets-stores, storage/volsync |
| [suwayomi](../../../kubernetes/apps/downloads/suwayomi) | downloads | app-template / ghcr.io/suwayomi/tachidesk | tachi.${SECRET_DOMAIN} · internal | ceph-block 2Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
| [tranga](../../../kubernetes/apps/downloads/tranga) | downloads | app-template / docker.io/glax/tranga-api | tranga.${SECRET_DOMAIN} · internal | ceph-block 1Gi | VolSync | onepassword-connect | database/cloudnative-pg-postgres18-cluster, external-secrets/external-secrets-stores, storage/volsync |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

### Books & Audio

```mermaid
flowchart LR
    lncrawl["lncrawl"]
    shelfmark["shelfmark"]
    inbox["_inbox<br>manual queue"]
    calibre_web_automated["calibre-web-automated<br>metadata workbench"]
    ebook_reconcile["ebook-reconcile<br>bake + sync CronJobs"]
    bindery["bindery<br>acquire + track ownership"]
    genre_tree[("NFS genre tree<br>Books/{Genre}/{Author}/{Series}/{NN - Title}/")]
    audiobookshelf["audiobookshelf<br>serves audio"]
    bookorbit["bookorbit<br>ebook reading hub"]

    lncrawl --> inbox
    shelfmark --> inbox
    inbox -.->|"manual: desktop Calibre"| calibre_web_automated
    ebook_reconcile -->|"embed-nightly re-bake"| calibre_web_automated
    calibre_web_automated -.->|"bake-sync: manual today; hardlink CronJob suspended"| genre_tree
    bindery -->|"files by {Genre}"| genre_tree
    genre_tree -->|"library scan"| audiobookshelf
    genre_tree -->|"read-only mount"| bookorbit

    classDef acquisition fill:#81D4FA,stroke:#0277BD,color:#000
    classDef pipeline fill:#FFE082,stroke:#F57C00,color:#000
    classDef reader fill:#90EE90,stroke:#2E7D32,color:#000
    classDef tree fill:#E1BEE7,stroke:#7B1FA2,color:#000
    classDef queue fill:#ECEFF1,stroke:#607D8B,color:#000

    class lncrawl,shelfmark,bindery acquisition
    class calibre_web_automated,ebook_reconcile pipeline
    class audiobookshelf,bookorbit reader
    class genre_tree tree
    class inbox queue

    %% MEANING: The NFS genre tree, not any app database, is the integration contract for books/audio (per the nerdz-reading repo's docs/README.md orientation): bindery acquires and files by {Genre}; calibre-web-automated is the metadata source of truth (a workbench scoped to .calibre/ingest + .calibre/library -- it cannot see the genre tree at all); audiobookshelf serves audio by scanning the tree; bookorbit is the ebook reading hub on a read-only mount
    %% COLOR: Blue = acquisition, Orange = Calibre metadata pipeline, Green = readers, Purple cylinder = the genre tree (shared NFS export, not an app), Gray = manual inbox
    %% GOTCHA: dashed edges are real-but-not-manifest-declared steps -- _inbox -> CWA is Gavin's desktop-Calibre workflow, and CWA -> tree is the manual bake-sync copy that the ebook-reconcile hardlink CronJob (ships suspend: true, */15 schedule once enabled) will replace after a controlled first run. Library placement must hardlink or copy, never move: qBittorrent (downloads domain) holds seeding copies open (see the Seed-Safety capsule below).
    %% NAVIGATION: Left-to-right -- acquisition feeds the manual inbox, the Calibre workbench bakes metadata, everything converges on the genre tree, and the two readers consume it. No subgraph boxes, so no edge can cross a group title.
```

### Comics & Manga

```mermaid
flowchart LR
    subgraph Acquisition2["Acquisition"]
        kapowarr["kapowarr"]
        suwayomi["suwayomi"]
        tranga["tranga"]
    end

    subgraph Organize["Organize & Metadata"]
        komf["komf"]
        mangarr["mangarr"]
    end

    subgraph Reader["Reader"]
        kavita["kavita"]
    end

    mangarr --> suwayomi
    mangarr --> tranga
    komf --> kavita

    classDef acquisition fill:#81D4FA,stroke:#0277BD,color:#000
    classDef organize fill:#FFE082,stroke:#F57C00,color:#000
    classDef reader fill:#90EE90,stroke:#2E7D32,color:#000

    class kapowarr,suwayomi,tranga acquisition
    class komf,mangarr organize
    class kavita reader

    %% MEANING: Reading domain comics/manga flow -- mangarr organizes completed downloads from both manga acquisition apps (suwayomi, tranga); komf fetches metadata into kavita, the shared reader
    %% COLOR: Blue = acquisition, Orange = organize/metadata, Green = reader
    %% GOTCHA: kapowarr has no manifest-declared edge to any other in-domain app -- its comic downloads land on the shared media NFS mount with no other app referencing that specific path
    %% NAVIGATION: Left-to-right -- mangarr pulls from both manga acquisition apps; komf feeds metadata into kavita independently
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- auth (outbound): [bookorbit](../../../kubernetes/apps/entertainment/bookorbit) enables OIDC login against pocket-id (`OIDC_ALLOW_LOCAL_ISSUERS` lets pocket-id's internal-gateway issuer through the SSRF guard) per its HelmRelease env.
- auth (outbound): [shelfmark](../../../kubernetes/apps/downloads/shelfmark) authenticates via pocket-id OIDC (`OIDC_DISCOVERY_URL` points at `id.${SECRET_DOMAIN}`) per its HelmRelease env.
- downloads (outbound): [suwayomi](../../../kubernetes/apps/downloads/suwayomi) and [tranga](../../../kubernetes/apps/downloads/tranga) use [flaresolverr](../../../kubernetes/apps/downloads/flaresolverr) to solve Cloudflare/DDoS-Guard challenges (`server.flareSolverrUrl`/`FLARESOLVERR_URL` pointing at `flaresolverr.downloads.svc.cluster.local:8191`), per their HelmRelease.
<!-- generated:end -->

<!-- curated -->
## Capsules

### Genre-Tree Contract

The disk tree, not any app database, is the integration contract for the books/audio side of this domain: every service reads or writes `Books/{Genre}/{Author}/{Series}/{NN - Title}/` on the shared NFS export (`citadel.internal:/mnt/storage0/media`), and they compose only because they all respect that shape. Folders encode only single-valued facts; anything multi-valued (extra genres, multi-series, tags) lives in metadata, never in the path. AudiobookShelf runs one library per top-level genre folder, which is also how kids' restricted accounts are age-gated (a genre folder is invisible to a kid account unless explicitly granted). calibre-web-automated cannot see the genre tree at all — it's scoped to `.calibre/ingest` + `.calibre/library` only — so the manual bake-sync copy step is the current bridge from Calibre-fixed files back into the tree; the `ebook-reconcile` hardlink CronJob (every 15 min) will take over that bridge once enabled — it ships suspended pending a controlled first run.

Audiobook layout is state-dependent: dual-format books put the ebook at the title-folder root with the audio nested in an `Audiobook/` subfolder (one AudiobookShelf item, Read+Listen); audio-only books put the audio at the title root instead (a sidecar alone does not anchor an AudiobookShelf item); dramatized adaptations get their own sibling folder, `NN - Title (Dramatized Adaptation)/`. When the ebook later arrives for a previously audio-only book, the audio gets nested into `Audiobook/` at that point. Bindery's naming templates are cached at pod boot, so a template change needs a Bindery pod restart before it takes effect.
<!-- seeded: review -->

### Two-Layer Metadata

A book's metadata lives in two independent layers: the catalog sidecar (`metadata.json` + `cover.jpg`, read by AudiobookShelf) and the file-embedded layer (OPF inside the epub, tags inside the m4b, rendered by the actual reader/player). Fixing a cover in AudiobookShelf edits only the sidecar — the epub itself still shows the old cover, because AudiobookShelf cannot write inside book files. Only Calibre (`ebook-meta`, or the UI which bakes on edit) can fix the file layer, and `calibredb set_metadata` bulk sessions bypass CWA's UI-triggered baking — which is exactly the gap ebook-reconcile's `embed-nightly` CronJob closes by re-baking every DB edit into the file within a day. BookOrbit reads the embedded (file) layer only, so its view of an un-baked book is stale by design. Fix-first workflow: correct the metadata in calibre-web, bake-sync the corrected epub over the genre-tree copy, regenerate the sidecar, then rescan in AudiobookShelf.
<!-- seeded: review -->

### Seed-Safety Rules

Library placement must hardlink or copy, never move: any tool that rewrites a file mints a new inode and silently divorces the library copy from the seeding copy held open by qBittorrent in the downloads domain (a moved or deleted `/complete` file kills the seed on the private tracker). ebook-reconcile's `embed-nightly` CronJob is scoped with `advancedMounts` to touch ONLY the Calibre library subpath — it structurally cannot reach the genre tree, so a bug there cannot corrupt AudiobookShelf's library. The `ebook-reconcile` (hardlink) CronJob itself ships **suspended** (`suspend: true`) pending a controlled first run before it's allowed to touch the shared tree.

A book therefore exists as 2-3 copies at once (the qBittorrent seed, the Calibre-baked copy, the genre-tree copy) for ebooks, or as a single hardlinked file for audiobooks. [tqm](../../../kubernetes/apps/downloads/tqm) enforces a flat 30-day-minimum seed rule across all trackers before anything is automatically removed. MAM 429 cooldowns compound: retrying a disabled indexer extends the ban roughly 24h per attempt, so wait out the stated expiry and then probe with exactly one search.
<!-- seeded: review -->

### M4b Conversion Workflow

Converting mp3 audiobooks to m4b runs through AudiobookShelf's built-in encoder (`POST /api/tools/item/{id}/encode-m4b`), driven by a sequential, resumable script that submits one encode at a time and polls the task queue rather than firing all books at once. Success must be verified on disk, never from the API — the item record lags right after an encode completes, so the real check is exactly 1 `.m4b` and 0 `.mp3`/`.m4a` files left in the folder. AudiobookShelf stashes the pre-encode originals under `/config/metadata/cache/items/{id}` as a safety net; that cache has to be purged per book once the encode is verified, or a batch run fills the config PVC. Encodes and library scans must stay sequential — running them in parallel OOMKills the AudiobookShelf container. The encoder's output lands at the title-folder root regardless of layout, so dual-format books need the resulting m4b manually filed into `Audiobook/` afterward, followed by a rescan.
<!-- seeded: review -->

### Grab Safety Gates

Grabbing is manual and user-triggered; every piece of automation that can fetch or delete is fenced off by an explicit gate. Bindery's `autoGrab.enabled=false` setting keeps roughly 2,000 monitored+wanted books from mass-grabbing the instant a download client is enabled — but the kill-switch is read only once, when Bindery's 12-hour wanted-sweep starts, so after changing it the Bindery pod needs a restart before enabling any client, or an in-flight sweep will still grab. Authors and series are added unmonitored by default; grabs go through the Wanted page in the UI or `POST /api/v1/wanted/bulk {ids,action:'search'}` (paced and bounded). The English-only filter lives on the Prowlarr MAM indexers (`searchLanguages=[1]`) — without it, loose title matches grab foreign editions. Dual-format grabs carry two known upstream Bindery gotchas: an audiobook import landing on an existing ebook folder collides into `Title (2)/` and needs manual consolidation, and the last import wins on `mediaType`, which is restored with `PUT /api/v1/book/{id} {"mediaType":"both"}`.
<!-- seeded: review -->

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
