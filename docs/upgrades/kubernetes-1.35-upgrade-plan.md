---
description: Plan for moving Kubernetes from v1.33.1 to v1.35.x on the existing Talos v1.12.6 nodes, ahead of the platform (Tier 0) Renovate backlog.
tags: [kubernetes, talos, upgrade-k8s, feature-gates, plan]
audience: { human: 45, agent: 55 }
purpose: { north-star: 0, gestalt: 0, reference: 15, research: 10, design: 5, plan: 70, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: Kubernetes v1.33.1 → v1.35.x

No Renovate PR drives this. `kubernetesVersion` in `talconfig.yaml` is tracked by Renovate, but nothing applies it: the value is only read when talhelper generates machine configs.

> **For agentic workers:** two hops, one minor each, never both in one sitting. Every command that changes the cluster is run by a human or on an explicit go-ahead.

## The findings that shape this plan

**v1.35 is the ceiling until two other upgrades land.** Three independent limits meet at the same version (checked 2026-11-13):

| Component | Running | Kubernetes range it supports | Source |
|---|---|---|---|
| Talos | v1.12.6 | 1.30 – **1.35** | 📚 Talos v1.12 support matrix |
| Rook | v1.19.7 | 1.30 – **1.35** | 📚 Rook v1.19.7 prerequisites |
| Cilium | 1.20.4 | 1.33 – 1.36 | 📚 Cilium v1.20.4 compatibility |
| CloudNative-PG | 1.30.1 | 1.34 – 1.36 tested; 1.33 and 1.37 supported untested | 📚 CNPG supported releases |

Kubernetes 1.36 needs Talos v1.13 (range 1.31 – 1.36) **and** Rook v1.20 or later. Kubernetes 1.37 needs Talos v1.14 (range 1.33 – 1.37). So this plan stops at 1.35, and the Talos and Rook plans are what unlock the next hop.

**The alpha admission API in use here survives both hops unchanged.** The cluster runs two `MutatingAdmissionPolicy` objects for VolSync movers (`volsync-mover-jitter`, `volsync-mover-nfs`) on `admissionregistration.k8s.io/v1alpha1`, switched on by explicit apiserver flags (📄 `kubernetes/bootstrap/talos/patches/controller/feature-gates.yaml`). Read from upstream source at each target tag:

| | v1.33 | v1.34 | v1.35 | v1.36 |
|---|---|---|---|---|
| `MutatingAdmissionPolicy` gate | alpha, off | beta, **off by default** | beta, **off by default** | GA, on |
| `v1alpha1` storage still in the apiserver | yes | yes | yes | yes |
| Newer API version available | – | `v1beta1` | `v1beta1` | `v1` |
| `ImageVolume` gate | beta, off | beta, off | beta, on | GA, locked on |

The gate is still off by default in 1.34 and 1.35, so the existing `feature-gates` and `runtime-config` flags must **stay exactly as they are** for both hops. Removing them as a tidy-up would switch the policies off: mover Jobs would be created without the `repository` NFS volume, so every backup to the shared Kopia repository would fail, and source Jobs would lose their `jitter` init container. Moving the manifests to `v1` and dropping the flags belongs with the 1.36 hop.

**Git already disagrees with the cluster in two places.**

- 📄 `kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml` declares `v1.34.2`. tuppr is not deployed (Plan: `talos-1.13-upgrade-plan.md`), so this is inert, but it reads as "already on 1.34".
- 📄 `bootstrap/templates/kubernetes/bootstrap/talos/talconfig.yaml.j2` declares `v1.32.0`, older than the cluster.

## Scope

**Covers:**
- Control plane and kubelet on `stanton-01`, `stanton-02`, `stanton-03`: v1.33.1 → v1.34.13 → v1.35.10 (newest `ghcr.io/siderolabs/kubelet` patch tags on 2026-11-13; re-check on the day)
- Bringing every declared Kubernetes version in git into line with the nodes
- The `alpine/k8s` image in the VolSync restore drill, which tracks the cluster's kubectl minor ([#2990](https://github.com/gavinmcfall/home-ops/pull/2990))

**Does not cover:**
- The Talos node OS (Plan: `talos-1.13-upgrade-plan.md`). `talosctl upgrade-k8s` does not reboot nodes.
- Rook/Ceph (Plan: `rook-ceph-1.21-upgrade-plan.md`).
- Enabling tuppr. Introducing the operator and performing an upgrade together gives a failure two candidate causes; that decision stays with the Talos plan.
- Migrating the `MutatingAdmissionPolicy` manifests off `v1alpha1`.

## Enables

- Clears the way for the Tier 0 platform PRs, whose charts increasingly assume a newer API surface
- Makes the `alpine/k8s` bump in #2990 mergeable at the cluster's own minor
- Leaves the cluster one hop (plus Talos and Rook) from current

## Prerequisites

- `talosctl` reaches the nodes with 📄 `kubernetes/bootstrap/talos/clusterconfig/talosconfig`, and etcd reports three members (confirmed 2026-11-13; leader `stanton-01`).
- An etcd snapshot taken immediately before each hop and copied off the cluster. This is the only real way back (see Error policy).
- etcd defragmented. `etcdDatabaseHighFragmentationRatio` is firing on all three members: 454 MB on disk, 206 MB in use.
- `CephCluster` `HEALTH_OK`.
- No VolSync mover mid-run. Mover Jobs are mutated by the alpha policies above with `failurePolicy: Fail`, so a Job created while an apiserver restarts is the workload most exposed to this change.
- Every firing alert understood, so new ones are attributable. On 2026-11-13 ten were firing, none blocking: `KubeJobFailed` ×3, `KubePodNotReady` (`home-automation/postcraft`), `KubeDeploymentReplicasMismatch`, `TargetDown`, the three etcd fragmentation alerts.
- The local `talosctl` (v1.13.4) accepts the hop in `--dry-run` against v1.12.6 nodes.

## North Star

All three nodes report kubelet and control plane v1.35.x on Talos v1.12.6; both VolSync admission policies still mutate mover pods; etcd holds three healthy members throughout; and every Kubernetes version declared in git equals what the nodes run.

## Stages

### Stage 1: Pre-flight

- All Prerequisites shall hold before the first hop.
- `talosctl --nodes 10.90.3.101 upgrade-k8s --to v1.34.13 --dry-run` shall complete and its reported changes shall be read before anything is applied.
- If the dry run proposes changing `feature-gates` or `runtime-config`, then stop: the machine config and this plan disagree.

### Stage 2: Hop to v1.34.13

- The upgrade shall run through the repo task: `task talos:upgrade-k8s controller=10.90.3.101 to=v1.34.13`.
- While it runs, each node's apiserver, controller-manager and scheduler are replaced in turn, then its kubelet. Pods are not drained and nodes are not rebooted.
- When it finishes, all three nodes shall report `v1.34.13` and the three control-plane pods on each node shall run the `v1.34.13` image.

### Stage 3: Verify and soak

- Both `MutatingAdmissionPolicy` objects and their bindings shall still be listed.
- A `volsync-src-*` Job created after the hop shall carry the `repository` NFS volume and the `jitter` init container the policies inject. This is the check that proves the flags survived.
- Flux shall report all Kustomizations and HelmReleases reconciled.
- The cluster shall run a full VolSync cycle and a restore-drill run before the next hop.

### Stage 4: Hop to v1.35.10

- Stage 1's snapshot and dry run shall be repeated against `v1.35.10`, then Stage 2 and Stage 3.
- `ImageVolume` becomes on-by-default at 1.35; the explicit `ImageVolume=true` flags are redundant but valid and shall be left alone.

### Stage 5: Reconcile declaration with reality

- `kubernetesVersion` in 📄 `kubernetes/bootstrap/talos/talconfig.yaml` and its `.j2` template shall state the version the nodes run.
- `talhelper genconfig` shall be re-run so the generated machine configs match. If this is skipped, the next `talosctl apply-config` reverts the control plane images.
- 📄 `kubernetesupgrade.yaml` shall state the same version.
- #2990 shall be retargeted to the 1.35 line of `alpine/k8s` and merged.

## Done Criteria

### Node state
- Each node shall report kubelet `v1.35.x`.
- Each node's apiserver, controller-manager and scheduler shall run `v1.35.x` images.

### Behaviour preserved
- `admissionregistration.k8s.io/v1alpha1` shall still be served.
- A new `volsync-src-*` Job shall show both policy mutations applied.
- `apiserver_requested_deprecated_apis` shall show no series with a `removed_release` of 1.36 or earlier that was not present before.

### Declaration
- No file in git shall declare a Kubernetes version different from the one the nodes run.

## Constraints

- **One minor per hop.** `upgrade-k8s` does not skip minors, and a soak between hops is what makes a regression attributable.
- **Do not edit the feature-gate or runtime-config flags in this work.** See the table above.
- **Do not go to 1.36 from here.** Talos v1.12 and Rook v1.19 both stop at 1.35.
- **Do not overlap with the Talos or Rook upgrades.** Same three nodes, same etcd members.
- **Do not merge #2990 as it stands.** It proposes kubectl 1.37 against a 1.33 cluster; #2917 was closed for the same reason.

## References

- 📄 `kubernetes/bootstrap/talos/talconfig.yaml:6` — `kubernetesVersion`, Renovate-tracked
- 📄 `kubernetes/bootstrap/talos/patches/controller/feature-gates.yaml` — the flags that must not move
- 📄 `kubernetes/apps/storage/volsync/app/mutatingadmissionpolicy.yaml` — the four `v1alpha1` objects
- 📄 `.taskfiles/Talos/Taskfile.yaml` — `upgrade-k8s` task
- 📚 [Talos: upgrading Kubernetes](https://www.talos.dev/latest/kubernetes-guides/upgrading-kubernetes/)
- 📚 `kubernetes/kubernetes` at tags `v1.34.13`, `v1.35.10`, `v1.36.6`: `staging/src/k8s.io/apiserver/pkg/features/kube_features.go`, `pkg/features/kube_features.go`, `pkg/registry/admissionregistration/rest/storage_apiserver.go`
- Plan: `talos-1.13-upgrade-plan.md`, Plan: `rook-ceph-1.21-upgrade-plan.md` — both gate the hop after this one

**Error policy:** Kubernetes does not support downgrading a control plane by a minor once the newer apiserver has written to etcd, so after a hop completes the way back is restoring the etcd snapshot, not re-running the task with the old version. If the first node's control plane does not come back healthy, stop: the other two apiservers are still on the old version and still serving. Do not start a second hop to get past a problem in the first.
