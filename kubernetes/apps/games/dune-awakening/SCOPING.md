# Dune Awakening Self-Hosted Server — Cluster Deployment Scoping

> **Status: SCOPING ONLY.** Nothing here is wired into `games/kustomization.yaml`, so Flux will not deploy it. This branch (`feat/dune-awakening-scoping`) documents *what a deployment would look like* and where the hard problems are. Decide direction before any of this becomes real.

Companion research: `~/scratch/Dune Awakening/research-self-hosted-server.md`

---

## TL;DR

- **Capacity is not the problem.** The cluster has ample headroom (see below). A 20–40 GB server fits comfortably on one node.
- **The architecture is the problem.** The Dune server *is itself a k3s/Kubernetes cluster* (custom operators + CRDs + Postgres + RabbitMQ + per-map game pods). You'd be running Kubernetes-inside-Kubernetes, or translating an immature community decomposition into native manifests. Neither is clean.
- **AVX2 ✅, GPU ✅** — hardware is fine.
- **Recommendation:** if this gets built, the least-bad path is **KubeVirt VM** (run Funcom's Linux stack as a black-box VM the cluster schedules) *or* **a dedicated Talos/Linux worker** rather than shoehorning it into the shared workload plane. The "translate Compose to app-template" path is GitOps-native but leans on unsupported community projects and forfeits Funcom's lifecycle operators.

---

## 1. Cluster fit (measured 2026-06-02)

| Resource | Per node | Cluster (×3) | Headroom |
|---|---|---|---|
| Nodes | `stanton-01/02/03` (Talos v1.12.6, k8s v1.33.1) | 3 control-plane | — |
| CPU | 20 vCPU (i9-12900H) | 60 vCPU | ~9% used → ~18 vCPU free/node |
| RAM | ~98 GB cap / ~94 GB alloc | ~282 GB alloc | ~20–23 GB used/node → **~70 GB free/node** |
| **AVX2** | ✅ confirmed (Alder Lake) | — | Hard requirement met |
| GPU | Intel iGPU present (NFD label) | — | Not needed by server |

**Storage classes available:**
- `ceph-block` (default, RWO) — for Postgres / per-server save data
- `ceph-filesystem` (RWX) — for shared `Saved/` mount across map pods (Funcom mounts a shared save dir to all game servers)
- `openebs-hostpath` (local, WaitForFirstConsumer) — fastest, node-pinned; good for the game-server scratch if pinned
- `ceph-bucket` — n/a

**Verdict:** A single map (Hagga Basin, ~20 GB) or full set (~40 GB) sits inside one node's free RAM with room to spare. Resource capacity does **not** block this.

---

## 2. The architecture problem

From the research: the server decomposes into ~7 services + N game-server pods:

```
postgres ─┐
admin-rmq ─┤
game-rmq  ─┼─ director ── gateway ── [game-server pod per map partition]
rmq-auth  ─┤        │
text-router┘        └── (Funcom k8s operators spawn/destroy map pods via the k8s API)
```

Funcom ships this as an **Alpine Linux + k3s VHDX**. The official "self-host" experience is: a single-node k3s cluster with four custom operators that watch CRDs and spawn one game-server pod per map. **The operators talk to the k8s API to manage pod lifecycle** — that's the part that resists being dropped into an existing cluster.

### Why it fights our cluster

1. **Talos is immutable & locked down.** No host shell, PodSecurity-capable, designed to run *workloads* — not to host a nested k3s with its own privileged kubelet/cgroup management. Nesting k3s-in-a-pod needs privileged + cgroupv2/mount gymnastics that are fragile on Talos.
2. **CRD/operator collision.** Funcom's operators install cluster-scoped CRDs and watch the API. Running them in our cluster pollutes the cluster-wide CRD space and gives a third-party operator API access. Their operators assume they *own* the cluster.
3. **GitOps mismatch.** Flux wants declarative HelmReleases it reconciles. Funcom's flow is an imperative `battlegroup` CLI bootstrap that mutates its own k3s. These two models don't compose.

---

## 3. Three deployment strategies

### Strategy A — KubeVirt VM (treat it as a black box) ★ least-bad official path
Run the Alpine+k3s Linux image as a **VM** via KubeVirt; the cluster just schedules the VM, the Dune stack lives entirely inside it (its own k3s, untouched).

- ✅ Matches Funcom's supported shape exactly (their k3s, their operators, their CRDs — all isolated inside the VM).
- ✅ No CRD pollution, no privileged pods on the host plane.
- ✅ Survives Funcom updates to the bootstrap with minimal rework.
- ❌ **KubeVirt is not installed** — adds a substantial new platform component (`kubevirt`, CDI) to the cluster.
- ❌ VM RAM is statically reserved (no k8s bin-packing of the game's own pods).
- ❌ Need to import/convert the Funcom VHDX → KubeVirt DataVolume.

### Strategy B — Translate the Compose stack to app-template HelmReleases ★ GitOps-native
Use the community decomposition (Red-Blink / snapetech) — discrete containers for postgres, rabbitmq, text-router, director, gateway, and **statically-defined game-server Deployments per map** — rendered as `bjw-s/app-template` HelmReleases in the `games` namespace.

- ✅ Fully GitOps-native, fits home-ops conventions, k8s bin-packs everything.
- ✅ No nested k3s; uses our Ceph storage, our secrets, our gateways.
- ❌ **Relies on unsupported community projects** (snapetech ~0 stars, Red-Blink "experimental").
- ❌ **Replaces Funcom's operators** — you statically declare each map pod instead of the operator spawning them; lose dynamic map lifecycle (Deep Desert reset cadence etc. needs custom handling).
- ❌ High maintenance: every Funcom server update can break the hand-rolled translation.
- ❌ Steam depot download + `FLS_SECRET` token bootstrap must be modeled (initContainer pulling via SteamCMD into a Ceph PVC).

### Strategy C — Dedicated host / VM outside the cluster ★ simplest, honest
Run Funcom's stack on a dedicated Linux box (or a Proxmox/libvirt VM) the *normal* supported way; leave the Talos cluster out of it.

- ✅ Supported, simplest, most robust; no platform changes.
- ✅ Easy to give 40 GB + pin AVX2 CPU.
- ❌ Not GitOps, not in-cluster — outside the home-ops model entirely.
- ❌ New host to manage (or steal capacity from a stanton node, which are Talos and not VM hosts).

---

## 4. If we go Strategy B — sketch of the app directory

```
kubernetes/apps/games/dune-awakening/
├── ks.yaml                         # Flux Kustomization (depends-on: rook-ceph)
└── app/
    ├── helmrelease.yaml            # app-template: multi-controller (postgres, rmq, director, gateway, text-router, game-hagga)
    ├── externalsecret.yaml         # FLS_SECRET (Funcom self-host token) + steam creds from 1Password (onepassword-connect)
    ├── pvc-saved.yaml              # ceph-filesystem RWX, shared Saved/ across map pods
    └── kustomization.yaml
```

Key wiring decisions to resolve before writing real manifests:
- **SteamCMD bootstrap**: initContainer runs `steamcmd +login anonymous +app_update 4754530 validate` into a Ceph PVC (verify anonymous works for live app, not just PTC).
- **Secret**: `FLS_SECRET` token → `onepassword-connect` ExternalSecret. The token is per-server and tied to a game-owning Steam account.
- **Networking**: game traffic is UDP (UE5) — needs a `LoadBalancer`/Cilium L2 or NodePort, **not** the HTTP Gateway. Confirm ports (query/game UDP range).
- **Game-server pods**: one Deployment per map partition; shared `Saved/` on `ceph-filesystem` (RWX), per-pod scratch on `openebs-hostpath`.
- **RAM**: set requests/limits per map (~12–20 GB Hagga Basin). Consider Funcom's experimental swap flag to halve it — but swap on Talos nodes is a separate decision.

A non-wired draft `helmrelease.yaml` placeholder lives in `app/` for reference. **It is intentionally incomplete and not in any kustomization.**

---

## 5. Open questions / blockers (decide these first)

1. **Which strategy?** A (KubeVirt), B (translate), or C (dedicated host)? This dominates everything else.
2. **Is the extra platform weight worth it?** Strategy A means owning KubeVirt+CDI forever for one game server.
3. **Live depot anonymous pull?** Research only confirmed anonymous SteamCMD for the *PTC* depot (3104830); the live app (4754530) may need authenticated Steam login. Blocks the initContainer design.
4. **UDP ingress**: does Cilium L2 announcement / the LB pool have spare IPs + the right UDP ports for game traffic?
5. **Swap on Talos**: the >50% RAM reduction flag wants swap; Talos swap config is a node-level change (machine config), not trivial.
6. **Do you even want it in-cluster?** Capacity says yes; operational sanity may say "Strategy C, dedicated box." Worth an honest gut-check.

---

## 6. Recommendation

If the goal is *"learn / GitOps-purity / it's already k3s so it feels native"* → **Strategy B**, accepting it's experimental and high-maintenance.

If the goal is *"a server that just works and stays working"* → **Strategy C** (dedicated host), or **Strategy A** if you specifically want it inside the cluster and are willing to adopt KubeVirt.

Capacity, CPU (AVX2), and storage are all green. The decision is purely **architectural philosophy + maintenance appetite**, not resources.
