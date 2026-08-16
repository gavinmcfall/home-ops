---
description: "Books, Audiobooks, Comics & Manga — decision records: the whys behind this domain"
tags: ["Reading", "Decisions"]
audience: ["LLMs", "Humans"]
categories: ["DecisionRecord[100%]"]
---

# Books, Audiobooks, Comics & Manga — Decisions

Append-only. Never regenerated. New entries at the top. Format:

## YYYY-MM-DD — Chose X over Y
**Why**: ...
**Alternatives rejected**: Y (reason), Z (reason)
**Links**: manifests / PRs / external docs

## 2026-07-31 — Mounted BookOrbit's genre-tree library read-only, no exceptions
**Why**: BookOrbit's per-book Write & Rename feature bypasses its own library-visibility toggles by design (upstream bookorbit#852), so a read-write mount risked uncontrolled writes into the shared genre tree that Bindery, ebook-reconcile, and AudiobookShelf all depend on. The CWA-vs-BookOrbit question of which app owns file-level metadata writes is still undecided, so read-only keeps BookOrbit safe to trial without resolving that question first.
**Alternatives rejected**: Read-write mount — rejected until the metadata-ownership question is settled and bookorbit#852 is fixed upstream.
**Links**: docs/ai-context/nerdz-reading-stack.md; kubernetes/apps/entertainment/bookorbit/app/helmrelease.yaml
<!-- seeded: review -->

## 2026-07-31 — CWA sees only its own ingest/library subpaths, never the shared genre tree
**Why**: calibre-web-automated is the Calibre metadata workbench, not the serving layer — scoping its NFS mounts to `.calibre/ingest` and `.calibre/library` only means a CWA bug or bad bulk edit cannot directly corrupt the AudiobookShelf-serving genre tree. The manual bake-sync copy step is the current, narrowly-scoped bridge back into the tree; the `ebook-reconcile` hardlink CronJob (every 15 min) will take over once enabled — it ships suspended pending a controlled first run.
**Alternatives rejected**: Mounting the full genre tree into CWA directly — rejected because it would let Calibre's file-rewriting behavior (new inode on every bake) reach the seeding/serving copies directly, breaking the hardlink economy.
**Links**: docs/ai-context/nerdz-reading-stack.md; kubernetes/apps/home/calibre-web-automated/app/helmrelease.yaml; kubernetes/apps/home/ebook-reconcile/app/helmrelease.yaml
<!-- seeded: review -->
