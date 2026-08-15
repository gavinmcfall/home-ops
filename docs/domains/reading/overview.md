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
    subgraph Acquisition["Acquisition"]
        lncrawl["lncrawl"]
        shelfmark["shelfmark"]
    end

    subgraph Pipeline["Library Pipeline"]
        calibre_web_automated["calibre-web-automated"]
        ebook_reconcile["ebook-reconcile"]
    end

    subgraph Readers["Readers & Managers"]
        audiobookshelf["audiobookshelf"]
        bindery["bindery"]
        bookorbit["bookorbit"]
    end

    ebook_reconcile --> calibre_web_automated
    ebook_reconcile --> audiobookshelf
    ebook_reconcile --> bindery

    classDef acquisition fill:#81D4FA,stroke:#0277BD,color:#000
    classDef pipeline fill:#FFE082,stroke:#F57C00,color:#000
    classDef reader fill:#90EE90,stroke:#2E7D32,color:#000

    class lncrawl,shelfmark acquisition
    class calibre_web_automated,ebook_reconcile pipeline
    class audiobookshelf,bindery,bookorbit reader

    %% MEANING: Reading domain books/audio flow -- ebook-reconcile reads calibre-web-automated's Calibre library and writes reconciled files into the shared genre-tree path that both audiobookshelf and bindery treat as their library root
    %% COLOR: Blue = acquisition, Orange = library pipeline, Green = readers/managers
    %% GOTCHA: shelfmark and lncrawl write completed downloads to /media/Library/Books/_inbox, a manually-processed inbox with no manifest-declared consumer in this domain (Gavin processes it via a local desktop Calibre workflow), so no edge is drawn from either. bookorbit has no manifest-declared edge to any other in-domain app -- its library mount is read-only pending the CWA-vs-BookOrbit metadata decision (see decisions.md).
    %% NAVIGATION: Left-to-right -- ebook-reconcile is the hub, pulling from the library pipeline and feeding both reader apps
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
<!-- seeded: review -->

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
