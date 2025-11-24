# Tool Strategy for Homelab Exploration

**Purpose**: Apply a RepoQL-style discipline inside `~/home-ops` using the tools we actually have (rg, task, flux CLI). Treat the repo like a database: inventory structure first, then inspect specific manifests.

---

## 🎯 Core Retrieval Pattern
```
ls / inventory directories → rg (find placeholders/patterns) → task/flux commands (validate) → read specific YAML/Task files for evidence
```
- Start broad with `ls kubernetes/apps` and `rg --files -g"kustomization.yaml"` to understand what exists.
- Narrow with `rg` against placeholders (`${SECRET_DOMAIN}`, `PLANE_DB_URL`) or resource names (`HelmRelease`, `ExternalSecret`).
- Verify with `task configure`, `task kubernetes:kubeconform`, and `flux diff kustomization <namespace>` before drawing conclusions.

---

## 🔧 Tool Selection Matrix
| Question | Tool | Why |
|----------|------|-----|
| "Where is this service defined?" | `rg --files -g"helmrelease.yaml" kubernetes/apps` | Lists all HelmReleases so you can pick the right area. |
| "Which manifests reference `${SECRET_DOMAIN}`?" | `rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps` | Finds every ingress/secret placeholder. |
| "What does Taskfile do for Kubernetes?" | Read `Taskfile.yaml` + `.taskfiles/Kubernetes.yaml` | Shows render/validation tasks, dependencies, env vars. |
| "How does Flux see this change?" | `flux diff kustomization <namespace> --path kubernetes/apps/<namespace>` | Simulates Flux apply like RepoQL verification. |
| "How do I prove a claim?" | Combine `rg`, `sed -n`, file paths | Evidence tables require explicit references (e.g., ROMM HelmRelease). |

---

## 📁 Repository Inventory Commands
```bash
# List top-level context
ls bootstrap scripts talosconfig kubernetes/apps

# Show every HelmRelease + ExternalSecret
rg --files -g"helmrelease.yaml" kubernetes/apps
rg --files -g"externalsecret.yaml" kubernetes/apps

# Enumerate kustomizations (ensures Flux wiring)
rg --files -g"kustomization.yaml" kubernetes/apps

# Inspect Taskfile entry points
task --list | head -n 40
sed -n '1,200p' Taskfile.yaml
```

Use these to build the same "map before reading" habit that RepoQL provides.

---

## 🧭 Placeholder & Pattern Discovery
```bash
# Domain placeholders
rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps
rg -n "PLANE_" -g"*.yaml" kubernetes/apps

# Storage patterns
rg -n "existingClaim" -g"helmrelease.yaml" kubernetes/apps
rg -n "nfs:" -g"helmrelease.yaml" kubernetes/apps

# Flux dependencies
rg -n "dependsOn" -g"helmrelease.yaml" kubernetes/apps
```
ROMM (`kubernetes/apps/games/romm/app/helmrelease.yaml`) is the canonical example for ingress hosts, env placeholders, PVC/NFS mounts, and `dependsOn` wiring.

---

## 🧪 Verification Protocol
1. **Find the claim** – e.g., "Taskfile orchestrates rendering."
2. **Locate the evidence** – `rg -n "configure" Taskfile.yaml`, `sed -n '1,160p' .taskfiles/Kubernetes.yaml`.
3. **Run the command when necessary** – `task configure` / `task kubernetes:kubeconform` / `flux diff kustomization games` to ensure manifests render.
4. **Record it** – Add to the evidence table in the doc you're editing.

Missing data? Document it in `QUESTIONS.md` instead of guessing.

---

## ⚙️ Command Reference
```bash
task configure                 # renders manifests via makejinja + Task modules
task kubernetes:kubeconform    # validates YAML before Flux
task flux:apply path=games/romm # (optional) apply subset via Taskfile module
flux diff kustomization games --path=kubernetes/apps/games/romm/app
flux get helmrelease romm
```
Use `task` for reproducible operations and `flux` for source-of-truth validation. Avoid `kubectl apply`; Flux will revert drift.

---

## Evidence
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| Placeholders (`${SECRET_DOMAIN}`) drive ingress & secrets | `kubernetes/apps/games/romm/app/helmrelease.yaml:65-120` | 🟢 | Hosts, env vars, and persistence all rely on placeholders. |
| Taskfile exposes configure/validate tasks | `Taskfile.yaml`, `.taskfiles/Kubernetes.yaml` | 🟢 | Defines `task configure`, `task kubernetes:kubeconform`, flux helpers. |
| Flux diff mirrors RepoQL verification | `WORKFLOWS.md`, `kubernetes/apps/games/romm/app/helmrelease.yaml` | 🟢 | Docs instruct running `flux diff kustomization <namespace>` before merge. |
