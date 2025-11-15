# Homelab Knowledge Base

**Goal**: Deliver the “aha!” context for the home-ops repository so every helper understands how `Taskfile.yaml`, `bootstrap/`, `talosconfig/`, and the Flux overlays under `kubernetes/apps/*` combine into a single GitOps control plane.

---

## The Problem
This repo powers every part of the homelab—from Talos node configs to HelmReleases—but the knowledge lives across scripts, Taskfiles, GitHub Actions, and dozens of app directories. Without a curated view you must:
- Reverse-engineer Taskfile orchestration (`Taskfile.yaml`, `.taskfiles/*`).
- Inspect each area (e.g., `kubernetes/apps/games/romm/app/helmrelease.yaml`) to infer placeholder conventions.
- Learn Talos + bootstrap workflows from scattered scripts.

Result: newcomers waste hours rediscovering GitOps invariants, placeholder maps, and storage expectations before touching a single manifest.

---

## The Solution
`.codex/Homelab` follows a structured pattern:

Start with foundation docs that explain philosophy and tooling, drill into repository capsules (architecture, domain, contracts, workflows), and keep every claim tied back to evidence.
- **Foundation docs** explain philosophy, tooling, and mental models.
- **Repository capsules** describe architecture, domain invariants, integration contracts, and workflows.
- **Evidence tables** link every claim back to concrete files inside `/home/gavin/home-ops`.

Read these docs in <15 minutes and you can answer “Where does this change belong?” or “What breaks if I rename `${SECRET_DOMAIN}`?” without spelunking the entire repo.

---

## Quick Start
1. **Read `TOOLS.md`** – Search strategy, command recipes, verification patterns.
2. **Read this README** – Understand the story, ownership, and navigation cues.
3. **Read `ARCHITECTURE.md`** – Mental model, key decisions, constraints (GitOps/Talos/Flux pipeline).
4. **Read `DOMAIN.md`** – Rules/invariants, glossary, and lifecycle diagrams.
5. **Read `CONTRACTS.md`** – Integration guarantees for Taskfile, Flux, and ExternalSecrets.
6. **Skim `WORKFLOWS.md` + `QUESTIONS.md`** – How to ship safely and which gaps remain.

Need deeper context? Drop into `kubernetes/apps/<area>/app` for the HelmRelease, ExternalSecret, and kustomization referenced here.

---

## What’s Inside
### Foundation Documents
- **`GESTALT.md`** – Fast mental model of the Taskfile → Flux → ExternalSecrets pipeline plus invariant capsules.
- **`ARCHITECTURE.md`** – GitOps pattern, Taskfile decisions, placeholder strategy, constraints (`Taskfile.yaml`, `kubernetes/apps/games/romm/app/helmrelease.yaml`).
- **`DOMAIN.md`** – Rules like “Flux + Taskfile are the authority,” storage invariants, glossary, state machines.
- **`CONTRACTS.md`** – Guarantees for Taskfile, Flux, ExternalSecrets, and breaking-change policy.
- **`WORKFLOWS.md`** – Step-by-step HelmRelease onboarding and rolling update playbooks.
- **`TOOLS.md`** – Retrieval strategy (`rg`, `task`, `flux diff`), verification ideas, snippet commands.
- **`QUESTIONS.md`** – Known unknowns (placeholder inventory, ROMM storage history, Flux metrics).
- **`TEMPLATE_GUIDE.md`** – Placeholder index, evidence standards, maintenance cadence.

### Repository Surface Area
- **GitOps pipeline**: `Taskfile.yaml`, `.taskfiles/*`, `makejinja.toml`, and `bootstrap/` render everything Flux sees.
- **Cluster manifests**: `kubernetes/apps/<area>/app/{helmrelease,externalsecret}.yaml` plus area `kustomization.yaml` (ROMM is the canonical example).
- **Talos + scripts**: `talosconfig/` and `scripts/` hold node configs, bootstrap helpers, and install automation.
- **Dashboards & automation**: `dashboards/` feed the badges in `README.md`; Renovate/Flux GHAs enforce automation.

---

## Navigation Philosophy
**Progressive disclosure** – start broad, zoom in only as needed:
```
README (story, owners)
    ↓
ARCHITECTURE / DOMAIN (mental model)
    ↓
CONTRACTS / WORKFLOWS (how to act)
    ↓
Specific app manifests under kubernetes/apps/* (implementation)
```

Never edit YAML blind—verify claims using the evidence links or run `task configure` + `flux diff` before touching manifests.

---

## Critical Invariants
- **GitOps Authority**: `task configure` must render manifests before Flux (`kubernetes/apps/*` never edited manually). Violating this just reverts on next sync (`Taskfile.yaml`, `ARCHITECTURE.md`).
- **Placeholder Discipline**: `${SECRET_DOMAIN}`, `${MEDIA_SERVER}`, `${DB_URI}`, and app-specific env vars stay as placeholders. Real values arrive via ExternalSecrets and never land in Git (`kubernetes/apps/games/romm/app/helmrelease.yaml:65-140`).
- **Storage Declaration**: Any workload needing persistence (ROMM, databases) declares PVC/NFS mounts in the HelmRelease `persistence` block before Flux deploys it (`kubernetes/apps/games/romm/app/helmrelease.yaml:102-140`).
- **Flux Wiring**: Each area’s HelmRelease must be referenced by a `kustomization.yaml`; otherwise Flux silently ignores it (`kubernetes/apps/games/kustomization.yaml`).

These invariants appear across `ARCHITECTURE.md`, `DOMAIN.md`, and `CONTRACTS.md`. Breaking them is the fastest path to pods stuck in `Pending` or Flux loops.

---

## Integration Map
| Dependency | Purpose | Source |
|------------|---------|--------|
| **Taskfile + Makejinja** | Render templates, wrap secrets, run kubeconform | `Taskfile.yaml`, `.taskfiles/*`, `makejinja.toml` |
| **Flux** | Applies everything under `kubernetes/apps/*`, respects dependsOn/remediation | `kubernetes/apps/games/romm/app/helmrelease.yaml` |
| **ExternalSecrets** | Bridges placeholders (e.g., `romm-secret`, `PLANE_DB_URL`) to real secrets | `kubernetes/apps/<area>/app/externalsecret.yaml` |
| **Talos configs** | Define node bootstrap + upgrades | `talosconfig/`, `bootstrap/` |

Outputs feed:
- **Monitoring dashboards** under `dashboards/` → README badges.
- **GitHub Actions / Renovate** → automated PRs documented in `WORKFLOWS.md`.

---

## Getting Started in the Repo
```bash
task init                   # seed config.yaml and direnv values
task configure              # render templates + manifests
task kubernetes:kubeconform # validate manifests commonly
flux diff kustomization games --path=kubernetes/apps/games/romm/app
```
- Adding an app? Follow `WORKFLOWS.md` to create the HelmRelease, ExternalSecret, and kustomization entry.
- Refreshing secrets? Update the ExternalSecret, sync your vault, and rerun `task configure`.
- Verifying? `flux get kustomizations` + `flux get helmrelease <name>` confirm reconciliation status.

---

## Maintenance & Contribution
- Follow `TEMPLATE_GUIDE.md` before adding docs—capture timeless patterns, cite sources, avoid secrets.
- Update `ARCHITECTURE.md` and `DOMAIN.md` whenever GitOps patterns, placeholders, or storage strategies change.
- Log unanswered questions or pending migrations in `QUESTIONS.md`; future work should resolve or move them to the “Answered” section.
- Keep evidence tables fresh whenever moving files or renaming directories referenced here.

---

## Success Metrics
✅ Anyone can orient themselves in <20 minutes and know where to place a change.
✅ `task configure` + `flux diff` are run before every PR, preventing surprise reconciles.
✅ Placeholder inventory lives in `TEMPLATE_GUIDE.md`, so secrets never leak.
✅ Storage-heavy workloads document their claims/mounts before shipping.

If those aren’t true, update the relevant doc or create an issue in `/home/gavin/home-ops`.

---

## Evidence
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| GitOps workflow = Taskfile → Flux | `Taskfile.yaml`, `kubernetes/apps/games/romm/app/helmrelease.yaml` | 🟢 | Taskfile renders/validates; HelmRelease shows Flux interval/dependsOn. |
| Placeholders guard secrets | `kubernetes/apps/games/romm/app/helmrelease.yaml:65-140` | 🟢 | `${SECRET_DOMAIN}`, `envFrom` referencing ExternalSecret names. |
| Storage + wiring requirements | `kubernetes/apps/games/romm/app/helmrelease.yaml:90-150`, `kubernetes/apps/games/kustomization.yaml` | 🟢 | Shows `persistence` + required kustomization pointers. |
| Dashboards/automation exist | `README.md:1-130`, `dashboards/` | 🟢 | README badges and dashboards folder show observability output. |
