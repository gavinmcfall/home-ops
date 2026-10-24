---
description: Plan for taking Rook-Ceph from v1.19.7 to v1.21.x, which cannot be done as the single jump Renovate proposes.
tags: [rook, ceph, storage, csi, upgrade, plan]
audience: { human: 40, agent: 60 }
purpose: { north-star: 0, gestalt: 0, reference: 10, research: 15, design: 10, plan: 65, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: Rook-Ceph v1.19.7 → v1.21.x

Supersedes the direct merge of [#1955](https://github.com/gavinmcfall/home-ops/pull/1955) (operator group) and [#1956](https://github.com/gavinmcfall/home-ops/pull/1956) (cluster chart), both of which propose `v1.19.7 ➔ 1.21.0` in one step.

> **For agentic workers:** this plan changes the storage layer every stateful app in the cluster depends on. Each stage ends in a verification gate. Do not begin a stage until the previous gate passes.

## Why Renovate's PRs cannot simply be merged

Three findings, each independently blocking:

1. **The upgrade path is sequential.** Rook documents 1.19→1.20 and 1.20→1.21 as separate guides; there is no 1.19→1.21 path. 📚 [rook-upgrade (release-1.21)](https://raw.githubusercontent.com/rook/rook/release-1.21/Documentation/Upgrade/rook-upgrade.md) covers only 1.20.x→1.21.x and states "Before upgrading to v1.20, ensure the cluster is already on at least v1.19.5."
2. **Rook 1.20 stops deploying CSI drivers.** 📚 "Rook no longer deploys CSI drivers." A separate `ceph-csi-drivers` Helm chart must be installed or "the CSI driver will fail due to missing service accounts" — meaning every Ceph PVC in the cluster loses its driver. This repo has no `ceph-csi` chart of any kind (📄 `grep -rln ceph-csi kubernetes/` returns nothing).
3. **CVE-2025-30156 couples Rook and Ceph versions.** 📚 Rook ≥ v1.20.6 must be paired with Ceph ≥ v20.2.4 or v19.2.6, and "Ceph reports health errors until users rotate core CephX keys."

## Scope

**Covers:**
- Rook operator and cluster charts from v1.19.7 to a v1.20.x gate, then to v1.21.x
- Introducing a `ceph-csi-drivers` HelmRelease and migrating the two customised CSI settings onto it
- Pinning `cephVersion` explicitly and moving Ceph to ≥ v20.2.4
- CephX core key rotation required by CVE-2025-30156

**Does not cover:**
- Talos or Kubernetes version changes (Plan: `talos-1.13-upgrade-plan.md`) — but see Constraints, the two must not overlap
- Any change to pool layout, OSD count, or device classes

## Enables

- Unblocks the two oldest PRs in the repo, and with them the Rook/Ceph line generally
- Closes CVE-2025-30156
- Moves CSI driver management onto the `ceph-csi-operator` CRs that the cluster already carries, making CSI configuration explicit in git rather than an implicit side effect of the Rook chart

## Prerequisites

- `CephCluster` reporting `HEALTH_OK`, all PGs `active+clean`. 📄 Observed state at planning: `HEALTH_OK`, 169 PGs across 12 pools, `3 osds: 3 up, 3 in`, 1.2 TiB used of 5.2 TiB, mon quorum `a,b,c`, 1 CephFS (1 active + 1 hot standby MDS), 2 RGW daemons.
- Kubernetes ≥ v1.31 (📚 the 1.20 minimum). 📄 Nodes report `v1.33.1`, so this is satisfied.
- A current, *restore-tested* backup position for every Ceph-backed PVC. The nightly `volsync-restore-drill` exercises the three oldest restore points; confirm no volume is beyond the `VolSyncRestorePointStale` 30-day bound before starting.
- Exports of the existing CSI state, taken **before** touching the operator:
  - `kubectl get drivers.csi.ceph.io -A -o yaml`
  - `kubectl get operatorconfigs.csi.ceph.io -A -o yaml`
  📄 Both resources exist already: `rook-ceph.cephfs.csi.ceph.com`, `rook-ceph.rbd.csi.ceph.com`, and `operatorconfig/ceph-csi-operator-config`, alongside the `csi.ceph.io` CRDs (`cephconnections`, `clientprofiles`, `clientprofilemappings`, `drivers`, `operatorconfigs`).

## North Star

Ceph returns to `HEALTH_OK` with all PGs `active+clean` on Rook v1.21.x and Ceph ≥ v20.2.4; every Ceph-backed PVC still mounts; a newly created PVC binds on both `ceph-block` and `ceph-filesystem`; and CSI driver configuration is declared in git rather than inherited from the Rook chart.

## Stages

### Stage 1 — Make the implicit explicit (no version change)

The repo pins no `cephVersion` (📄 no match for `cephVersion` under `kubernetes/apps/rook-ceph/`), so the Ceph daemon version is whatever the chart defaults to. A chart bump therefore moves Ceph *and* Rook together, invisibly.

- The `CephCluster` spec shall pin `cephVersion.image` to the digest the cluster already runs, so that a Rook chart bump changes Rook alone.
- 📄 The running daemon version is `ceph version 20.2.1 (6a49aff47758778a5f5951e731d437c317f72fb2) tentacle`.

**Gate:** `flux build` clean; no pod restarts; `ceph versions` unchanged.

### Stage 2 — Adopt `ceph-csi-drivers` while still on Rook 1.19

Introducing the CSI chart *before* the operator bump separates "CSI moves house" from "Rook changes version", so a failure has one cause.

- A `ceph-csi-drivers` HelmRelease shall exist, reconciling the same `Driver` resources the cluster already has.
- The two customised settings shall move onto the new chart: `csi.cephFSKernelMountOptions: ms_mode=prefer-crc` and `csi.enableLiveness: true` (📄 `kubernetes/apps/rook-ceph/rook-ceph/app/helmrelease.yaml:21-23`).
- Where the operator chart still owns CSI in 1.19, the two shall not fight: confirm which controller reconciles the `Driver` CRs before and after.

**Gate:** CSI provisioner and plugin pods healthy on all three nodes; a scratch PVC binds and mounts on `ceph-block` and on `ceph-filesystem`; an existing pod survives a delete/reschedule.

### Stage 3 — Ceph to ≥ v20.2.4, then rotate CephX keys

- The `cephVersion` pin shall move to ≥ v20.2.4, and Ceph shall return to `HEALTH_OK`.
- When Rook reaches ≥ v1.20.6, the core CephX keys shall be rotated, because 📚 Ceph reports health errors until they are.
- If Ceph reports a CephX-related health error after the Rook bump, then key rotation is the remediation, not a regression to investigate.

**Gate:** `ceph status` `HEALTH_OK`; `ceph versions` shows every mon/mgr/osd/mds/rgw on the new version; all PGs `active+clean`.

### Stage 4 — Rook 1.19.7 → 1.20.9

📚 Chart order is `rook-ceph`, then the CSI drivers chart, then `rook-ceph-cluster`. 📄 Latest 1.20 patch is `v1.20.9`; taking the newest 1.20 also satisfies the ≥ v1.20.6 CVE floor in one move.

- The operator chart shall reach v1.20.9 before the cluster chart is touched.
- Where custom CSI images are set, the operator shall be scaled down before `helm upgrade`, because 📚 a race can otherwise restore old images.
- The cluster chart shall then reach v1.20.9.

**Gate:** both HelmReleases `Ready=True` reporting v1.20.9; `ceph status` `HEALTH_OK`; CSI pods healthy; scratch PVC binds; an existing stateful app restarts cleanly.

### Stage 5 — Rook 1.20.9 → 1.21.x

Same order as Stage 4. 📚 "Any official 1.20 patch release should work for any official 1.21 patch release."

**Gate:** as Stage 4, at v1.21.x. Then close #1955 and #1956 (or let Renovate close them once the versions match).

## Done Criteria

### Version state
- The `rook-ceph` and `rook-ceph-cluster` HelmReleases shall both report `Ready=True` on the same v1.21.x chart version.
- The `CephCluster` shall pin `cephVersion` explicitly, at ≥ v20.2.4.

### Storage correctness
- The `CephCluster` shall report `HEALTH_OK` with all PGs `active+clean`.
- When a new PVC is created on `ceph-block` or `ceph-filesystem`, it shall bind and mount.
- While the upgrade is in progress, no Ceph-backed PVC shall become unmountable for longer than a pod reschedule.

### CSI ownership
- CSI driver configuration shall be declared in git via the `ceph-csi-drivers` chart, including `ms_mode=prefer-crc` and liveness.
- If the CSI driver pods lose their service accounts, then the `ceph-csi-drivers` chart is missing or misconfigured — 📚 the named failure mode of the 1.20 change.

### Security
- Core CephX keys shall have been rotated after Rook reaches ≥ v1.20.6.

## Constraints

- **One stage at a time, each behind its gate.** Storage failure is not a recoverable-by-retry class of failure.
- **Must not overlap the Talos upgrade.** All pools are `size 3 min_size 2` across exactly three OSDs, one per node (📄 `ceph osd pool ls detail`, `ceph osd tree`). A node reboot already removes one of the three replicas; doing that during a Rook/Ceph upgrade removes the margin that makes the upgrade recoverable.
- **Do not skip 1.20.** Not a preference — there is no documented 1.19→1.21 path, and the CSI change lands in 1.20.
- **Do not merge #1955 and #1956 as-is at any point**, including "just the operator one": both carry the 1.21.0 jump.
- **Leave pool geometry alone.** Changing replication or OSD layout during a version upgrade confuses attribution.

## References

- 📚 [Rook 1.21 upgrade guide](https://raw.githubusercontent.com/rook/rook/release-1.21/Documentation/Upgrade/rook-upgrade.md)
- 📚 [Rook 1.20 upgrade guide](https://raw.githubusercontent.com/rook/rook/release-1.20/Documentation/Upgrade/rook-upgrade.md) — breaking changes, CSI chart, CVE-2025-30156, Kubernetes ≥ v1.31
- 📚 Rook issue [#18203](https://github.com/rook/rook/issues/18203) — referenced by the CVE note for clusters coming from v1.18 or lower
- 📄 `kubernetes/apps/rook-ceph/rook-ceph/app/helmrelease.yaml` — operator chart and the two CSI settings
- 📄 `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml` — cluster chart, `version: v1.19.7`
- Plan: `talos-1.13-upgrade-plan.md` — must not run concurrently

**Error policy:** on any gate failure, stop and diagnose; do not advance a stage and do not retry a Helm upgrade that failed mid-way without first establishing Ceph health. `cleanupOnFail` is set on HelmReleases in this repo — a failed upgrade can delete resources Helm has adopted, which is how qBittorrent's config PVC was destroyed by #2871. Render charts with `helm template` and confirm the PVC count before applying any storage change.
