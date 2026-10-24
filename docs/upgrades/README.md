---
description: Index of upgrade plans for changes too consequential to merge as a Renovate PR.
tags: [upgrades, renovate, plan, index]
audience: { human: 70, agent: 30 }
purpose: { north-star: 0, gestalt: 55, reference: 45, research: 0, design: 0, plan: 0, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Upgrade plans

Most Renovate PRs in this repo are safe to merge and watch. A few are not, and the ones that are not share a shape: **the version bump is the smallest part of the change.** Merging them on their own either does nothing, or does something irreversible, or quietly breaks an invariant written down somewhere else.

Each plan here exists because investigating the PR turned up something the PR itself does not say.

| Plan | PRs | What the investigation found |
|---|---|---|
| [Rook-Ceph v1.19.7 → v1.21.x](./rook-ceph-1.21-upgrade-plan.md) | [#1955](https://github.com/gavinmcfall/home-ops/pull/1955), [#1956](https://github.com/gavinmcfall/home-ops/pull/1956) | There is no 1.19→1.21 upgrade path, and 1.20 stops deploying CSI drivers altogether — a new chart is required or every Ceph PVC loses its driver. |
| [Talos v1.12.6 → v1.13.x](./talos-1.13-upgrade-plan.md) | [#1885](https://github.com/gavinmcfall/home-ops/pull/1885) | The upgrade operator that would action it is commented out, so merging the bump changes nothing at runtime — and arms an unprompted three-node roll if the operator is ever enabled. |
| [Sonarr 4.0.20 → v5](./sonarr-v5-upgrade-plan.md) | [#2819](https://github.com/gavinmcfall/home-ops/pull/2819) | Every upstream v5 release is a prerelease, against a one-way Postgres schema migration across three instances. |

## Two constraints that span these plans

**Rook-Ceph and Talos must not overlap.** All Ceph pools are `size 3 min_size 2` over exactly three OSDs, one per node. A node reboot already consumes the entire replica margin; doing it during a storage-layer upgrade removes what makes that upgrade recoverable.

**A PVC snapshot is not a backup for the Postgres-backed apps.** Sonarr and its siblings keep state in CloudNative-PG, not in their config volumes. The protective artefact is the database backup.

## Also deferred, without a plan here

- [#2844](https://github.com/gavinmcfall/home-ops/pull/2844) — Loki chart 18 → 19, a major. The OSS chart moved to `grafana-community`, so the bump is also a source change.
- [#2831](https://github.com/gavinmcfall/home-ops/pull/2831) — the CloudNative-PG Postgres image digest. Renovate found only one of the image's two references; moving both together rolls every database, which is the operation that drifts the `postgres` superuser password. Reasoning is recorded on the PR.

## When a plan is done

Delete it. These describe work to do, not history — git keeps the record.
