---
description: "Observability — decision records: the whys behind this domain"
tags: ["Observability", "Decisions"]
audience: ["LLMs", "Humans"]
categories: ["DecisionRecord[100%]"]
---

# Observability — Decisions

Append-only. Never regenerated. New entries at the top. Format:

## YYYY-MM-DD — Chose X over Y
**Why**: ...
**Alternatives rejected**: Y (reason), Z (reason)
**Links**: manifests / PRs / external docs

## 2026-06-12 — Primary telemetry object store is in-cluster Ceph RGW, not Backblaze B2
**Why**: InfluxDB 3's object store is the primary, continuously-accessed datastore — compaction and any cache-miss query read Parquet straight from it. Pointing that at an off-site bucket would mean constant egress and internet latency on the hot path, so the primary store must be local. Ceph RGW was already live in-cluster (the same pattern `zot` uses for its registry bucket).
**Alternatives rejected**: Backblaze B2 as the primary store (rejected — hot-path egress/latency); B2 is kept as a deferred cold archive for genuinely aged data only.
**Links**: docs/infrastructure-roadmap/otel-telemetry-backbone.md; kubernetes/apps/observability/otel-collector
<!-- seeded: review -->

## 2026-06-12 — InfluxDB 3 Enterprise over Core for the OTel telemetry backbone
**Why**: InfluxDB 3 Core caps query windows at 72 hours; Enterprise's compactor lifts that limit so the full history stays queryable. Enterprise is free for at-home, non-commercial use, so the cap was the only real cost of Core.
**Alternatives rejected**: InfluxDB 3 Core (rejected — 72h query-window cap unacceptable for long-term dashboards).
**Links**: docs/infrastructure-roadmap/otel-telemetry-backbone.md
<!-- seeded: review -->

## 2026-06-12 — OTel telemetry sink is InfluxDB, not Prometheus
**Why**: AI-CLI and application telemetry is high-cardinality and event-shaped (session id, repo, model, cost) — exactly what would blow up Prometheus's TSDB, and exactly what a columnar time-series store handles well. It also keeps continuity with the pre-existing dev-telemetry pattern that already wrote to InfluxDB.
**Alternatives rejected**: Feeding the same signals into Prometheus/kube-prometheus-stack (rejected — cardinality risk to the cluster-infra TSDB); the two planes coexist by design rather than merging.
**Links**: docs/infrastructure-roadmap/otel-telemetry-backbone.md; kubernetes/apps/observability/otel-collector/app/helmrelease.yaml
<!-- seeded: review -->

## 2026-05-17 — Swapped dcgm-exporter for nvidia-gpu-exporter (NVML-based) on pyro-01
**Why**: dcgm-exporter was crash-looping; initial diagnosis suspected Pascal/DCGM incompatibility, but `kubectl describe` showed it was actually OOMKilled at a too-tight 256Mi memory limit (DCGM's hostengine wants ~500MiB to initialise). Rather than retry dcgm-exporter at a higher (1Gi) limit, `nvidia-gpu-exporter` (an NVML wrapper around `nvidia-smi`) was chosen — it idles at ~30MiB and surfaces every metric the dashboard needed for the single-GPU-tenant use case.
**Alternatives rejected**: Retrying dcgm-exporter with a 1Gi memory limit (rejected — heavier footprint for no per-pod GPU attribution benefit, since only one tenant uses the GPU today).
**Links**: docs/observability-audit-2026-05.md
<!-- seeded: review -->
