# Dune Awakening Self-Hosted Server — Cluster Deployment Scoping

> **Status: SCOPING ONLY.** Nothing here is wired into `games/kustomization.yaml`, so Flux will not deploy it. This branch (`feat/dune-awakening-scoping`) documents *what a deployment would look like*. Decide direction before any of this becomes real.

Companion research: `~/scratch/Dune Awakening/research-self-hosted-server.md`

---

## Corrected premise (supersedes the earlier "K8s-in-K8s" framing)

k3s **is** Kubernetes. Everything Funcom deploys *into* their k3s is ordinary Kubernetes API objects (Deployments, StatefulSets, Services, CRDs, operators) — portable to any conformant cluster. The bundled k3s is Funcom's **packaging convenience** for people without a cluster, not a technical requirement. There is no nested-Kubernetes here: we transplant the workloads onto the existing Talos cluster and let Flux own them. **It does not matter which Kubernetes runs underneath.**

The community project **`snapetech/DuneAwakeningSelfHost`** already proves this: it flattens the stack into explicit containers via `compose.yaml`, **dropping Funcom's operators entirely**. That `compose.yaml` is the single best blueprint — translate it to `bjw-s/app-template` HelmReleases.

---

## The plan in one paragraph

Obtain the Funcom server **image tarballs** from the Steam depot (app `4754530`), push them to **a registry we control**, then run the components as plain Flux-managed workloads in the `games` namespace: Postgres + RabbitMQ (StatefulSets), director/gateway/text-router (Deployments), and **one game-server Deployment per map partition** (operator-free, per snapetech). Swap k3s's bundled infra (local-path storage, NodePort/klipper, Traefik) for Ceph + Cilium L2 (UDP) + cert-manager. Inject the Funcom Live Services JWT as a Secret. Patch the advertised public IP. Done.

---

## 1. Cluster fit (measured 2026-06-02)

| Resource | Per node | Headroom |
|---|---|---|
| Nodes | `stanton-01/02/03` (Talos v1.12.6, k8s v1.33.1) | — |
| CPU | 20 vCPU (i9-12900H) | ~9% used → ~18 free/node |
| RAM | ~98 GB cap / ~94 GB alloc | **~70 GB free/node** |
| **AVX2** | ✅ confirmed (Alder Lake) | hard requirement met |
| Storage | `ceph-block` (RWO), `ceph-filesystem` (RWX), `openebs-hostpath` (local), `ceph-bucket` (S3) | — |

A 20 GB (single map) → 40 GB (all maps) server fits inside one node's free RAM. **Capacity is not a constraint.**

---

## 2. The workloads (from snapetech `compose.yaml`)

All images live under the internal tag `registry.funcom.com/funcom/self-hosting/` (see §3 — that host is **not public DNS**, confirmed; it's a local containerd tag).

| Component | Image (internal tag) | k8s shape |
|---|---|---|
| Game server (every map) | `…/seabass-server:<build>-0-shipping` | Deployment per map partition |
| PostgreSQL | `…/igw-postgres:17.4-alpine-fc-13` | StatefulSet + Ceph PVC |
| RabbitMQ ×2 (admin + game) | `…/seabass-server-rabbitmq:<build>-0-shipping` | StatefulSet(s) |
| DB init/utils | `…/seabass-server-db-utils:<build>-0-shipping` | Job |
| Battlegroup Director | `…/seabass-server-bg-director:<build>-0-shipping` | Deployment |
| Text Router | `…/seabass-server-text-router:<build>-0-shipping` | Deployment |
| Gateway | `…/seabass-server-gateway:<build>-0-shipping` | Deployment |

`<build>` is a Steam build number, e.g. `1968181-0-shipping`. Tags change every Funcom update.

**Operators: skip them.** Funcom ships 4 operators (`BattleGroup`, `Database`, `Server`, `Utilities`) + CRDs (`BattleGroup`, `ServerSet`, `ServerSetScale`, `ServerGateway`, `MessageQueue`, `Database`) baked into the VHDX. Their *only* job is spawning one game pod per map. snapetech replaces that with static Deployments. This sidesteps two unknowns at once: the operator image names and the CRD schemas are **not publicly documented** (would require dumping from a live instance). Operator-free = nothing to extract.

---

## 3. THE blocker: image delivery (registry is internal-only)

**Confirmed 2026-06-02:** `registry.funcom.com` returns nothing from public resolvers (1.1.1.1 and 8.8.8.8), while `funcom.com` resolves. The images are **not internet-pullable**. Funcom delivers them as **OCI tarballs in the Steam depot**, imported into containerd via `ctr images import` with that internal tag.

Implication for Talos (immutable OS — can't casually `ctr import` per node in a GitOps way): **we host the images ourselves.**

**Delivery design:**
1. **Download** — SteamCMD `+app_update 4754530 validate` to fetch the depot (~5 GB). The *live* app needs an authenticated Steam login (game-owning account) — anonymous only confirmed for PTC `3104830`. Run on a helper box or a one-off Job with Steam creds in a Secret.
2. **Extract & push** — load the tarballs, retag to a registry we control, push.
3. **Reference** — HelmReleases pull from our registry with normal `imagePullPolicy`.
4. **Updates** — re-download + re-push on each Funcom build; automatable (CronJob / n8n) since tags are build-stamped.

**Where to host the images** (pick one):
- In-cluster **`zot`/`registry:2`** backed by **`ceph-bucket`** (Rook S3) — clean, GitOps-native, no external dep. *(Recommended.)*
- Existing registry if you already run one (Harbor/Gitea/etc.).
- `talosctl image` preload per node — works but imperative, not declarative; re-do on every node wipe.

---

## 4. k3s-isms to swap

| k3s default | Our cluster | Action |
|---|---|---|
| `local-path` StorageClass | `ceph-block` (Postgres/RabbitMQ RWO), `ceph-filesystem` (shared `Saved/` RWX) | set `storageClassName` on PVCs |
| NodePort / klipper-lb | Cilium L2 `LoadBalancer` (UDP-capable) | LB services for game UDP + RabbitMQ game TLS |
| Traefik | not used by the stack | ignore; Gateway API if a Director UI is wanted |
| cert-manager | **already present — keep** | RabbitMQ game queue needs TLS-AMQP |
| `imagePullPolicy: Always` on placeholder `0-0-shipping` | pin real tag from our registry | the VHDX auto-retag hack is irrelevant once we host images |

---

## 5. Networking

- **Game traffic: UDP.** Funcom k3s default ≈ `27015-27050` (per-partition) + `27115-27150` (inter-gateway/IGW). Configurable via `K8S_POOL_GAME_PORT_BASE` / `GAME_UDP_PORT_RANGE` (community Docker uses `7777+`). One UDP port per active map partition.
- **RabbitMQ game subscription:** TCP `31982` (TLS-AMQP, must be WAN-reachable).
- **Admin/management** (Director UI, RabbitMQ mgmt): LAN-only.
- **Public IP advertisement:** game binary takes `-ExternalAddress`; config also hardcodes `HOST_DATACENTER_IP_ADDRESS: 127.0.0.1` in ~3 places — **must** be set to the real public IPv4 or clients can't connect. In k8s inject via downward API / stable LB IP.
- **hostNetwork?** Unconfirmed whether game pods need `hostNetwork: true` vs Cilium UDP LB for stable port advertisement. Cilium supports UDP LB; resolve during first bring-up.

---

## 6. Auth flow

- **Steam download:** app `4754530`, authenticated (buyer's Steam account). No separate token for the download itself.
- **FLS JWT:** obtained from `account.duneawakening.com`; becomes `FLS_SECRET` / `DUNE_JWT` env injected into director, gateway, and game pods. Store as a Kubernetes Secret (SOPS or `onepassword-connect` ExternalSecret).

---

## 7. Proposed app directory (operator-free, Strategy "just deployments")

```
kubernetes/apps/games/dune-awakening/
├── ks.yaml                         # Flux Kustomization (dependsOn: rook-ceph, cert-manager)
└── app/
    ├── helmrelease.yaml            # app-template multi-controller (postgres, rmq x2, director, gateway, text-router, game-<map> x N)
    ├── externalsecret.yaml         # FLS_SECRET / DUNE_JWT + steam creds (onepassword-connect)
    ├── pvc-saved.yaml              # ceph-filesystem RWX shared Saved/
    └── kustomization.yaml
# plus (separate app) an in-cluster registry if we go that route:
kubernetes/apps/<ns>/dune-registry/  # zot backed by ceph-bucket
```

A non-wired DRAFT `app/helmrelease.yaml` sketch lives alongside this file. **Intentionally incomplete, not in any kustomization.**

---

## 8. Decisions to make (in order)

1. **Operator-free static Deployments** (snapetech model, matches your "just deployments" goal) vs. transplanting Funcom's operators+CRDs. → **Recommend operator-free.** Sidesteps undocumented operator images/CRD schemas; cost is hand-managing the per-map Deployment list.
2. **Image hosting:** in-cluster `zot` on `ceph-bucket` (recommended) vs. existing registry vs. `talosctl` preload.
3. **Which maps to run:** Hagga Basin only (~20 GB) vs. full set incl. Deep Desert (~40 GB).
4. **UDP exposure:** Cilium L2 LoadBalancer vs. hostNetwork — settle at first bring-up.
5. **Update automation:** manual re-push vs. CronJob/n8n on Funcom build bumps.

---

## 9. Hard dependencies / what we still can't get from the desk

- **The image tarballs require owning the game + an authenticated SteamCMD pull.** Can't be fetched anonymously for the live app. This is the gate to *any* real work.
- **Exact `compose.yaml` env/wiring** — pull directly from snapetech before writing manifests (it's the source of truth for ports, env vars, service dependencies).
- **CRD schemas / operator images** — only needed if we *keep* operators. Operator-free path makes this moot.
- **Live confirmation of hostNetwork vs LB, and the real UDP port base** — first-deploy empirical.

---

## Bottom line

Your instinct holds: this is **just containers and manifests**, and the underlying Kubernetes is irrelevant. The work is (a) hosting the Steam-delivered images on our own registry, (b) translating snapetech's `compose.yaml` to app-template HelmReleases, (c) swapping k3s-bundled infra for Ceph/Cilium/cert-manager, (d) injecting the FLS token and public IP. Capacity, CPU, and storage are all green. The only true gate is the authenticated Steam image pull.
