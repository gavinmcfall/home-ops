# Homelab Template Guide

## Philosophy
Document exactly what can’t be inferred from code within this repo: GitOps rules, placeholder requirements, failure patterns, and render workflows.

## Point Allocation
| File | Points | Purpose |
|------|--------|---------|
| `README.md` | 35 | Repo story, boundaries, integration map, getting started. |
| `ARCHITECTURE.md` | 35 | Decisions, constraints, failure modes, monitoring. |
| `CONTRACTS.md` | 20 | Promises to consumers (Taskfile, Flux, secrets). |
| `DOMAIN.md` | 10 | Rules/invariants and glossary. |
| Supporting docs | Not scored | Questions, workflows, tooling, templates.

## Placeholder Map
Use placeholders to keep secrets private.
- `${SECRET_DOMAIN}` – Domain suffix for all exposed hosts (replaces actual DNS). Mentioned in `kubernetes/apps/*` HelmRelease ingresses.
- `${MEDIA_SERVER}` / `${MEDIA_ROOT}` – NFS host/path used by ROMM’s `media` section.
- `${DB_URI}` / `${DB_USER}` – Database endpoints referenced by workloads (resolve in ExternalSecrets).
- `${KUBE_NAMESPACE}` – Namespace placeholders used in `kustomization` overlays.
- `${STATUS_PAGE}` – Observability endpoint referenced in `README.md` badges.

Explain what each placeholder maps to before using it elsewhere.

## Evidence Standards
Each claim must cite a source and confidence level. Sample table:
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| HelmRelease uses placeholders | `kubernetes/apps/games/romm/app/helmrelease.yaml` | 🟢 | `${SECRET_DOMAIN}` used in ingress host. |
| Taskfile orchestrates renders | `Taskfile.yaml` | 🟢 | `task configure` renders templates. |
| Bootstrap/Talos scripts | `bootstrap/`, `talosconfig/` | 🟢 | Provide node config and bootstrapping logic. |

## Maintenance Commitment
| File | Review Frequency | Trigger |
|------|------------------|---------|
| `README.md` | Quarterly | New area or infrastructure change.
| `ARCHITECTURE.md` | On pattern change | Taskfile or Flux workflow update.
| `CONTRACTS.md` | Before breaking change | New placeholder, chart, or secret strategy.
| `DOMAIN.md` | When rules shift | New automation or storage pattern.
| Supporting docs | Continuous | Questions/workflows evolve.

## Tips
1. Start with `README.md` for high-level context.
2. Keep placeholder explanations in this guide if you add new ones.
3. Update the Evidence sections in each doc so Claude/Codex know where the facts came from.
