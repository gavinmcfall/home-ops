---
description: Plan for moving Kubernetes from v1.33.1 to v1.35.x on the existing Talos v1.12.6 nodes, ahead of the platform (Tier 0) Renovate backlog. Revised after a failed first attempt.
tags: [kubernetes, talos, upgrade-k8s, feature-gates, runtime-config, mutatingadmissionpolicy, plan]
audience: { human: 45, agent: 55 }
purpose: { north-star: 0, gestalt: 0, reference: 15, research: 15, design: 5, plan: 65, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: Kubernetes v1.33.1 → v1.35.x

No Renovate PR drives this. `kubernetesVersion` in `talconfig.yaml` is tracked by Renovate, but nothing applies it: the value is only read when talhelper generates machine configs.

> **For agentic workers:** two hops, one minor each, never both in one sitting. The apiserver's `runtime-config` must change **before** the first hop. Every command that changes the cluster is run by a human or on an explicit go-ahead.

## What happened on the first attempt (2026-11-12)

The first version of this plan said the apiserver flags carried both hops unchanged. That was wrong, and the hop to v1.34.13 failed on it.

- `talosctl upgrade-k8s` moved the apiserver on `stanton-01`, then `stanton-02`, to v1.34.13. Both crash-looped (exit 255) and never reported ready. `stanton-03`, still on v1.33.1, was the only apiserver serving for about 18 minutes; the VIP sat on `stanton-01` and returned errors.
- Cause, from the apiserver log: `failed to list *v1beta1.MutatingAdmissionPolicy: the server could not find the requested resource`. The readyz check `informer-sync` never passed.
- Recovery: the apiserver image was set back to v1.33.1 on both nodes. Nothing else had been changed. Workloads, Ceph and etcd were unaffected.

The earlier research checked that `v1alpha1` was still *served* in 1.34. It did not check which version the admission plugin *reads*. Those are different questions and only the second one decides whether the apiserver starts.

## The findings that shape this plan

**The `MutatingAdmissionPolicy` plugin changes the API version it reads, and the version it writes, at different releases.** The cluster runs two policies for VolSync movers (`volsync-mover-jitter`, `volsync-mover-nfs`) with the gate switched on by explicit apiserver flags (📄 `kubernetes/bootstrap/talos/patches/controller/feature-gates.yaml`). Read from upstream source at each tag:

| | v1.33 | v1.34 | v1.35 | v1.36 |
|---|---|---|---|---|
| Gate | alpha, off | beta, off by default | beta, off by default | GA, on |
| Version the plugin **reads** | `v1alpha1` | **`v1beta1`** | `v1beta1` | `v1` |
| Version **written to etcd** | `v1alpha1` | `v1alpha1` | **`v1beta1`** | `v1beta1` |
| `runtime-config` the apiserver needs | `v1alpha1` | `v1alpha1` + **`v1beta1`** | `v1alpha1` + `v1beta1` | `v1beta1` (until manifests and storage move to `v1`) |

Three consequences:

1. **`admissionregistration.k8s.io/v1beta1=true` must be in `runtime-config` before any apiserver starts on 1.34.** With the gate on and that version off, the plugin's informer can never sync. The 1.34 changelog says the same thing in one line; it was not read the first time.
2. **`v1alpha1` must stay enabled as well**, because the four manifests Flux applies are `v1alpha1` (📄 `kubernetes/apps/storage/volsync/app/mutatingadmissionpolicy.yaml`).
3. **1.34 is reversible; 1.35 is not, past 1.34.** 1.34 still writes `v1alpha1`, so a 1.34 apiserver can be set back to 1.33. 1.35 writes `v1beta1`, which a 1.33 apiserver cannot decode.

**The flag can be proven on the current version first.** `admissionregistration.k8s.io/v1beta1` is a registered group-version in v1.33.1 (it serves the deprecated `ValidatingAdmissionPolicy` v1beta1 there), so the v1.33.1 apiserver accepts the key. That allows the flag change and the version change to be separate steps.

**`talosctl upgrade-k8s` does not stop when an apiserver fails to become ready.** It reported `stanton-01` "successfully updated" while that apiserver was crash-looping, and went on to `stanton-02`. Only a timeout on the second node kept the third apiserver alive. Its `--dry-run` did not catch the problem either. A manual canary on one node is the only real gate.

**v1.35 is the ceiling until two other upgrades land** (checked 2026-11-13):

| Component | Running | Kubernetes range it supports | Source |
|---|---|---|---|
| Talos | v1.12.6 | 1.30 – **1.35** | 📚 Talos v1.12 support matrix |
| Rook | v1.19.7 | 1.30 – **1.35** | 📚 Rook v1.19.7 prerequisites |
| Cilium | 1.20.4 | 1.33 – 1.36 | 📚 Cilium v1.20.4 compatibility |
| CloudNative-PG | 1.30.1 | 1.34 – 1.36 tested; 1.33 and 1.37 supported untested | 📚 CNPG supported releases |

Kubernetes 1.36 needs Talos v1.13 **and** Rook v1.20 or later. Kubernetes 1.37 needs Talos v1.14.

**Git already disagrees with the cluster in two places.**

- 📄 `kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml` declares `v1.34.2`. tuppr is not deployed (Plan: `talos-1.13-upgrade-plan.md`), so this is inert.
- 📄 `bootstrap/templates/kubernetes/bootstrap/talos/talconfig.yaml.j2` declares `v1.32.0`.

## Scope

**Covers:**
- Adding `admissionregistration.k8s.io/v1beta1=true` to the apiserver `runtime-config`, in git and on the nodes
- Control plane and kubelet on `stanton-01`, `stanton-02`, `stanton-03`: v1.33.1 → v1.34.13 → v1.35.10 (newest `ghcr.io/siderolabs/kubelet` patch tags on 2026-11-13; re-check on the day)
- Bringing every declared Kubernetes version in git into line with the nodes
- The `alpine/k8s` image in the VolSync restore drill ([#2990](https://github.com/gavinmcfall/home-ops/pull/2990))

**Does not cover:**
- The Talos node OS (Plan: `talos-1.13-upgrade-plan.md`). `talosctl upgrade-k8s` does not reboot nodes.
- Rook/Ceph (Plan: `rook-ceph-1.21-upgrade-plan.md`).
- Enabling tuppr.
- Moving the policy manifests to `v1` and removing the gate. That belongs with the 1.36 hop.

## Prerequisites

- `talosctl` reaches the nodes with 📄 `kubernetes/bootstrap/talos/clusterconfig/talosconfig`; etcd reports three members.
- A fresh etcd snapshot before each hop, copied off the cluster.
- `CephCluster` `HEALTH_OK`; no VolSync mover mid-run. Mover Jobs are mutated with `failurePolicy: Fail`.
- A window clear of the 00:00 UTC backup batch (105 of 108 ReplicationSources run then).
- Every firing alert understood beforehand.

## North Star

All three nodes report kubelet and control plane v1.35.x on Talos v1.12.6; both VolSync admission policies still mutate mover Jobs; at no point is fewer than two apiservers ready; and every Kubernetes version and apiserver flag declared in git equals what the nodes run.

## Stages

### Stage 1: Enable `v1beta1` while still on v1.33.1

- `runtime-config` in 📄 `patches/controller/feature-gates.yaml` shall read `admissionregistration.k8s.io/v1alpha1=true,admissionregistration.k8s.io/v1beta1=true`.
- The same value shall be applied to one node, and that node's apiserver shall report `readyz` ok before the next node is touched.
- If an apiserver does not report ready on v1.33.1 with the new flag, then the flag shall be reverted on that node and the plan stops here.
- When all three are done, `kubectl api-versions` shall list `admissionregistration.k8s.io/v1beta1`.

### Stage 2: Canary one apiserver on v1.34.13

- The apiserver image shall be set to v1.34.13 on **one** node only, by hand, not with `upgrade-k8s`.
- That apiserver shall report `readyz` ok and stay ready, with a restart count that is not rising.
- `kubectl get mutatingadmissionpolicies.v1beta1.admissionregistration.k8s.io` against that node shall list both policies.
- If it does not become ready, then its image shall be set back to v1.33.1. The other two apiservers have not been touched.

### Stage 3: Complete the hop to v1.34.13

- Only after Stage 2 holds, `task talos:upgrade-k8s controller=10.90.3.101 to=v1.34.13` shall run. It skips the node already done.
- While it runs, each node's `readyz` shall be watched directly; the tool's own "successfully updated" is not evidence of readiness.

### Stage 4: Verify and soak

- A `volsync-src-*` Job created after the hop shall carry the `repository` NFS volume and the `jitter` init container.
- Flux shall report all Kustomizations and HelmReleases reconciled.
- The cluster shall run a full 00:00 UTC backup batch and a restore-drill run before the next hop.

### Stage 5: Hop to v1.35.10

- Stages 2 to 4 shall be repeated against `v1.35.10`, with a fresh snapshot and a fresh `--dry-run`.
- This hop is the point of no return to 1.33: once a 1.35 apiserver rewrites a policy, etcd holds `v1beta1`.

### Stage 6: Reconcile declaration with reality

- `kubernetesVersion` in 📄 `talconfig.yaml` and its `.j2` template shall state the version the nodes run.
- `talhelper genconfig` shall be re-run so the generated machine configs carry both the version and the new `runtime-config`. If this is skipped, the next `talosctl apply-config` reverts both.
- 📄 `kubernetesupgrade.yaml` shall state the same version.
- #2990 shall be retargeted to the 1.35 line of `alpine/k8s` and merged.

## Done Criteria

### Node state
- Each node shall report kubelet `v1.35.x`, and its apiserver, controller-manager and scheduler shall run `v1.35.x` images.

### Behaviour preserved
- `admissionregistration.k8s.io/v1alpha1` and `v1beta1` shall both be served.
- A new `volsync-src-*` Job shall show both policy mutations applied.

### Declaration
- No file in git shall declare a Kubernetes version or apiserver `runtime-config` different from what the nodes run.

## Constraints

- **Flag before version.** No apiserver may start on 1.34 without `v1beta1` in `runtime-config`.
- **Canary before `upgrade-k8s`.** The tool will walk a failing change across every apiserver.
- **Never fewer than two ready apiservers.** If one is unready, nothing else is touched until it is.
- **One minor per hop**, with a soak between.
- **Keep the gate and both `runtime-config` versions through 1.35.** Do not tidy them.
- **Do not go to 1.36 from here.** Talos v1.12 and Rook v1.19 both stop at 1.35.
- **Do not overlap with the Talos or Rook upgrades.**
- **Do not merge #2990 as it stands.**

## Operational notes from the first attempt

- Machine config on these nodes is multi-document, so `talosctl patch mc` rejects JSON6902 patches. Use a strategic merge: `-p '{"cluster":{"apiServer":{"image":"registry.k8s.io/kube-apiserver:<version>"}}}'`, with `--mode=no-reboot`.
- In Git Bash, set `MSYS_NO_PATHCONV=1` for any `kubectl get --raw=/readyz` or the path is rewritten.
- When the VIP holder's apiserver is down, address a healthy node directly: `kubectl --server=https://10.90.3.10x:6443`.
- Never print a full machine config (`talosctl get mc -o yaml`); it contains the cluster CA key and join token. Read single fields from `apiserverconfig` or `kubeletspec` instead.

## References

- 📄 `kubernetes/bootstrap/talos/talconfig.yaml:6` — `kubernetesVersion`, Renovate-tracked
- 📄 `kubernetes/bootstrap/talos/patches/controller/feature-gates.yaml` — gate and `runtime-config`
- 📄 `kubernetes/apps/storage/volsync/app/mutatingadmissionpolicy.yaml` — the four `v1alpha1` objects
- 📄 `.taskfiles/Talos/Taskfile.yaml` — `upgrade-k8s` task
- 📚 `kubernetes/kubernetes` at tags `v1.33.1`, `v1.34.13`, `v1.35.10`, `v1.36.6`:
  - `staging/src/k8s.io/apiserver/pkg/admission/plugin/policy/mutating/plugin.go` — the version the plugin reads
  - `pkg/kubeapiserver/default_storage_factory_builder.go` — the version written to etcd
  - `pkg/registry/admissionregistration/rest/storage_apiserver.go` — the versions that can be served
  - `staging/src/k8s.io/apiserver/pkg/features/kube_features.go` — gate maturity
- 📚 `CHANGELOG-1.34.md`, `CHANGELOG-1.35.md` — "set `--runtime-config=admissionregistration.k8s.io/v1beta1=true`"; "storage version for MutatingAdmissionPolicy is updated to v1beta1"
- 📚 [Talos: upgrading Kubernetes](https://www.talos.dev/latest/kubernetes-guides/upgrading-kubernetes/)
- Plan: `talos-1.13-upgrade-plan.md`, Plan: `rook-ceph-1.21-upgrade-plan.md` — both gate the hop after this one

**Error policy:** an unready apiserver is a stop, not something to wait out. Set that node's apiserver image back to the last version that worked and confirm `readyz` before doing anything else. From 1.34 that is a clean revert. From 1.35 it is a revert to 1.34 only; getting back to 1.33 means restoring the etcd snapshot.
