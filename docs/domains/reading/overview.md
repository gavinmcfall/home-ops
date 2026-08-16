---
description: "Books, Audiobooks, Comics & Manga — human overview: what it is, how it fits together, how to operate it"
tags: ["Reading", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# Books, Audiobooks, Comics & Manga

<!-- generated:start section=summary -->
The Books, Audiobooks, Comics & Manga domain runs 13 apps across the downloads, entertainment, and home namespaces.

## Components

| App | What it does | UI |
|---|---|---|
| audiobookshelf | Audiobook Library | https://books.${SECRET_DOMAIN} |
| bindery | Readarr replacement — book/audiobook manager backed by SQLite, imports metadata-first without moving files | https://bindery.${SECRET_DOMAIN} |
| bookorbit | Family reading hub — library + web readers, OPDS server, KOSync/Kobo sync, Hardcover/StoryGraph sync (trial) | https://read.${SECRET_DOMAIN} |
| calibre-web-automated | Web-based Calibre library manager with automated metadata/format conversion; also runs a headless Calibre Content Server | https://calibre.${SECRET_DOMAIN} |
| ebook-reconcile | Nightly CronJobs that embed Calibre metadata into library files and reconcile hardlinks into the AudiobookShelf tree | internal (CronJob, no UI) |
| kapowarr | Comic Downloads | https://kapowarr.${SECRET_DOMAIN} |
| kavita | Comic/Ebook Web Reader | https://manga.${SECRET_DOMAIN} |
| komf | Kavita metadata fetcher | https://komf.${SECRET_DOMAIN} |
| lncrawl | Fan-translated web novels -> EPUB | https://lncrawl.${SECRET_DOMAIN} |
| mangarr | Manga organiser (the missing *arr tier) | https://mangarr.${SECRET_DOMAIN} |
| shelfmark | Anna's Archive / IRC book downloader | https://shelfmark.${SECRET_DOMAIN} |
| suwayomi | Mihon/Tachiyomi self-hosted server | https://tachi.${SECRET_DOMAIN} |
| tranga | Manga monitor + downloader | https://tranga.${SECRET_DOMAIN} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

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

<!-- curated -->
## Operating Notes

The books/audio side of this domain is one NFS folder tree (`Books/{Genre}/{Author}/{Series}/{NN - Title}/`), not app databases — every service composes because it respects that shape. AudiobookShelf's kids' accounts are age-gated by which genre folders/libraries they're granted, not a separate permission system. See the Genre-Tree Contract and Two-Layer Metadata capsules in [context.md](context.md) before changing any book-pipeline manifest.

Deep design/runbook material (`metadata-bake-process.md`, `download-workflow-design.md`, `abs-bindery-room-migration.md`, incident history) lives in the external repo `G:\code\Projects\nerdz-reading`.
<!-- seeded: review -->

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
