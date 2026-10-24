---
description: Plan for moving the three Talos nodes from v1.12.6 to v1.13.x, including the finding that the repo's automated upgrade operator is disabled.
tags: [talos, kubernetes, nodes, tuppr, upgrade, plan]
audience: { human: 45, agent: 55 }
purpose: { north-star: 0, gestalt: 0, reference: 10, research: 10, design: 10, plan: 70, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: Talos v1.12.6 → v1.13.x

Covers [#1885](https://github.com/gavinmcfall/home-ops/pull/1885) (`ghcr.io/siderolabs/installer v1.12.6 ➔ v1.13.12`).

> **For agentic workers:** every stage here reboots a node that holds one of exactly three Ceph OSDs. Serialise strictly, and recover Ceph fully between nodes.

## The finding that shapes this plan

**Merging #1885 does nothing to the cluster, and that is the trap.**

The PR touches three files (📄 `gh pr view 1885 --json files`):

| File | Effect of the bump |
|---|---|
| `kubernetes/bootstrap/talos/talconfig.yaml` | `talosVersion: v1.12.6 → v1.13.12`. Consumed by talhelper when machine configs are generated — **not** by Flux. |
| `bootstrap/templates/kubernetes/bootstrap/talos/talconfig.yaml.j2` | Same value in the template. |
| `kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml` | `spec.talos.version`. Would drive an automated rolling upgrade — **if tuppr were deployed.** |

tuppr is not deployed. 📄 `kubernetes/apps/system-upgrade/kustomization.yaml:12` reads `# - ./tuppr/ks.yaml` — commented out. The `system-upgrade` namespace holds no resources, there is no tuppr HelmRelease, and the cluster has no `tuppr.home-operations.com` CRDs, so `kubectl get talosupgrades` errors with "the server doesn't have a resource type".

Two consequences:

1. Merging #1885 alone declares v1.13.12 in git while the nodes keep running v1.12.6 — drift that reads as "already upgraded" to anyone scanning the repo. 📄 Nodes report `Talos (v1.12.6)`, Kubernetes `v1.33.1`.
2. If tuppr is later enabled with that version already bumped, it would immediately roll all three nodes, unprompted.

So the decision this plan needs from a human is **which mechanism** to use. The stages below assume the manual talhelper/talosctl route, with the tuppr route described as the alternative.

## Scope

**Covers:**
- Talos node OS from v1.12.6 to a chosen v1.13.x on `stanton-01`, `stanton-02`, `stanton-03`
- Resolving the declared-vs-actual version drift that merging #1885 would otherwise create
- The decision of whether to re-enable tuppr or upgrade by hand

**Does not cover:**
- The Kubernetes version. `kubernetesVersion: v1.33.1` is a separate pinned value in the same file (📄 `kubernetes/bootstrap/talos/talconfig.yaml:6`, tracked by Renovate against `ghcr.io/siderolabs/kubelet`) and should move in its own change.
- Rook/Ceph versions (Plan: `rook-ceph-1.21-upgrade-plan.md`) — see Constraints.
- The `alpine/k8s` image used by `volsync-restore-drill`, which tracks the *cluster's* kubectl minor. [#2917](https://github.com/gavinmcfall/home-ops/pull/2917) was closed for proposing v1.37.1 against a v1.33 cluster; it becomes correct to revisit once Kubernetes itself moves.

## Enables

- Unblocks the oldest open PR in the repo
- Restores a working, declared node-upgrade mechanism (either tuppr re-enabled, or a documented manual path), rather than dormant config that looks automated
- Unblocks the Kubernetes version line, which is pinned alongside Talos

## Prerequisites

- `CephCluster` `HEALTH_OK`, all PGs `active+clean`, all 3 OSDs `up`/`in`.
- No VolSync `ReplicationSource` mid-sync. The dormant TalosUpgrade CR already encodes exactly this gate and it is worth keeping (📄 `talosupgrade.yaml`): `status.conditions.filter(c, c.type == "Synchronizing").all(c, c.status == "False")`, plus `status.ceph.health in ['HEALTH_OK']`.
- etcd healthy with all three control-plane members. These are the same three nodes, so each reboot also removes an etcd member.
- A chosen target patch release of Talos v1.13, confirmed compatible with Kubernetes v1.33.1.
- Console/out-of-band access to each node, in case one does not come back.

## North Star

All three nodes report Talos v1.13.x and Kubernetes v1.33.1; Ceph returns to `HEALTH_OK` with all PGs `active+clean` after each reboot; etcd keeps quorum throughout; and the version declared in `talconfig.yaml` matches what the nodes run.

## Decision required before Stage 1

- **Option A — manual (talhelper + talosctl).** Matches the repo's current reality. `talhelper genconfig`, then `talosctl upgrade --image ghcr.io/siderolabs/installer:<version>` one node at a time. Full control over pacing; no new component.
- **Option B — re-enable tuppr.** Uncomment `./tuppr/ks.yaml`, deploy the operator, let it roll nodes using the health gates already written. Repeatable for every future Talos bump, but introduces the operator *and* performs an upgrade at the same time, so a failure has two candidate causes. If chosen, deploy tuppr while `spec.talos.version` still reads v1.12.6, confirm it reconciles to a no-op, and only then bump.

Option B with that split is the better long-term shape; Option A is the smaller change. Either way, `talconfig.yaml` must end up matching the nodes.

## Stages

### Stage 1 — Pre-flight

- The Ceph and VolSync gates in Prerequisites shall all pass before any node is touched.
- Node order shall be fixed in advance, upgrading the node **not** currently hosting the active Ceph mgr last where that is knowable.

### Stage 2 — First node

- One node shall be cordoned and drained, then upgraded, then rebooted (`rebootMode: powercycle` is what the dormant CR specifies).
- When the node returns, it shall rejoin etcd, report `Ready`, and its OSD shall return `up`/`in`.
- The cluster shall return to `HEALTH_OK` with all PGs `active+clean` **before** the next node is considered.

### Stage 3 — Remaining nodes, serially

- While any PG is not `active+clean`, no further node shall be upgraded.

### Stage 4 — Reconcile declaration with reality

- `talconfig.yaml`, the `.j2` template, and `talosupgrade.yaml` shall all state the version the nodes actually run, at which point #1885 is satisfied (merged, or closed in favour of the change that did it).

## Done Criteria

### Node state
- Each of the three nodes shall report Talos v1.13.x and Kubernetes v1.33.1.
- Each node shall report `Ready` with no lingering cordon or taint from the upgrade.

### Cluster integrity
- etcd shall report three healthy members.
- The `CephCluster` shall report `HEALTH_OK` with all PGs `active+clean`.
- When a node is rebooted, the cluster shall keep serving: all pools are `size 3 min_size 2` over three OSDs, so two replicas remain and I/O continues.
- If a second OSD or node becomes unavailable while one is down, then PGs drop below `min_size` and I/O stops — so no second node may be touched until the first is fully recovered.

### Declaration
- The Talos version in git shall equal the version the nodes run.
- If tuppr is enabled, then it shall be deployed at the version the nodes already run first, and only bumped afterwards.

## Constraints

- **Strictly one node at a time.** Three nodes, three OSDs, `min_size 2`: one node down is the entire tolerance. This is also why the health gate between nodes is `active+clean`, not merely `HEALTH_OK`.
- **Must not overlap the Rook/Ceph upgrade** (Plan: `rook-ceph-1.21-upgrade-plan.md`). Both consume the same single-replica margin.
- **Do not bump `kubernetesVersion` in the same change.** Two moving parts, one reboot, no attribution.
- **Do not merge #1885 on its own as a tidy-up.** Until the nodes are upgraded it creates drift, and it arms tuppr if tuppr is ever enabled.
- **The control plane is the worker set.** There is no separate pool to fall back on; every reboot is a control-plane reboot.

## References

- 📄 `kubernetes/bootstrap/talos/talconfig.yaml` — `talosVersion`, `kubernetesVersion`, Renovate annotations
- 📄 `kubernetes/apps/system-upgrade/kustomization.yaml:12` — the commented-out `./tuppr/ks.yaml` that makes tuppr dormant
- 📄 `kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml` — `rebootMode: powercycle` and the VolSync/Ceph health-check expressions worth reusing
- 📚 [Talos upgrade documentation](https://www.talos.dev/latest/talos-guides/upgrading-talos/) — confirm the chosen v1.13 patch and its supported Kubernetes range before starting
- 📚 [talhelper](https://github.com/budimanjojo/talhelper) — generates machine configs from `talconfig.yaml`
- Plan: `rook-ceph-1.21-upgrade-plan.md` — mutually exclusive with this work

**Error policy:** if a node fails to return, do not proceed to the next node under any circumstances — the remaining two hold a bare etcd quorum and the minimum Ceph replica count. Recover or replace the failed node first. Treat "Ceph is still backfilling" as a stop condition, not a yellow light.
