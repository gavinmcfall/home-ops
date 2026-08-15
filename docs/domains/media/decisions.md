---
description: "Movies & TV — decision records: the whys behind this domain"
tags: ["Media", "Decisions"]
audience: ["LLMs", "Humans"]
categories: ["DecisionRecord[100%]"]
---

# Movies & TV — Decisions

Append-only. Never regenerated. New entries at the top. Format:

## YYYY-MM-DD — Chose X over Y
**Why**: ...
**Alternatives rejected**: Y (reason), Z (reason)
**Links**: manifests / PRs / external docs

## 2025-12-08 — Adopted TechnoTim's prometheus-plex-exporter fork over the generic Grafana registry Plex dashboard
**Why**: TechnoTim's fork ships custom dashboards (`plex.json`, `plex-streaming.json`) purpose-built for his exporter's metric names; exportarr provides a per-instance Prometheus exporter for each arr instance (Sonarr x3, Radarr x2) using their native APIs, and tautulli-exporter covers stream/user metrics.
**Alternatives rejected**: Generic Grafana registry Plex dashboard (ID 17891) — its metrics don't reliably match a generic Plex exporter.
**Links**: docs/Guides/plex-arr-monitoring-stack.md; kubernetes/apps/observability/exporters/{plex-exporter,tautulli-exporter,exportarr-sonarr,exportarr-radarr}
<!-- seeded: review -->
