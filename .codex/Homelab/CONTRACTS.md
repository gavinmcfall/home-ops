# Homelab Integration Contracts

## GitOps Stability
### Stable Interfaces
- **Flux sync**: The `main` branch renders manifests via `task configure` and Flux applies them under `kubernetes/apps/*`; every area must list its HelmRelease in the local `kustomization.yaml`.
- **Taskfile operations**: `task init`/`task configure`/`task kubernetes:kubeconform` are the supported entry points for rendering and validating templates (see `Taskfile.yaml`).
- **ExternalSecret placeholders**: All workloads reference secrets via placeholders such as `${SECRET_DOMAIN}`, `${DB_URI}`, or `PLANE_*`; real values live in private vaults.

### Response Contract
| Operation | Guarantee |
|-----------|-----------|
| `task configure` | Renders all `kubernetes/apps/*/app` HelmReleases with current placeholder substitutions; fails if `makejinja` encounters missing vars. |
| `flux diff kustomization <area>` | Shows exactly what Flux will apply for the area by rendering the HelmRelease values and secrets. |
| `flux reconcile kustomization <area>` | Applies GitOps changes idempotently; it either finishes or surfaces errors in `flux get helmrelease`. |

### Breaking Change Policy
- **Add placeholder fields**: ✅ Allowed if you document the new variable in `TEMPLATE_GUIDE.md`. |
- **Change placeholder names** (e.g., `${SECRET_DOMAIN}` → `${SITE_DOMAIN}`): ❌ Requires updating all HelmReleases, ExternalSecrets, README/TEMPLATE guide, and verifying `task configure`. |
- **Swap storage provider** (e.g., moving ROMM from NFS to Ceph): ❌ Requires migrating PVC definitions and updating evidence in `ARCHITECTURE.md`/`DOMAIN.md`.

## Event Contracts
### Published Events
- Flux HelmRelease events and `kustomization` statuses (success/failure) recorded by Flux.
- GitHub Actions artifacts for Taskfile runs and Renovate updates help consumers understand why a change exists.

### Guarantees
- **Ordering**: Flux applies overlays sequentially per `kustomization` dependency chain.
- **Delivery**: Flux ensures at least one attempt; `obsidian` dashboards track successes/failures.
- **Retention**: Logs and artifacts from Taskfile/Flux remain available for 30 days in GitHub/Flux.

### Consumed Events
| Event | Source | Purpose |
|-------|--------|---------|
| `flux.kustomization` status changes | Flux | Notifies dependent kustomizations (e.g., `games` depends on `rook-ceph`). |
| `external-secrets.sync` | ExternalSecrets | Drives pod restarts when vault secrets rotate. |

## Integration Examples
```bash
# Validate ROMM values before commit
task configure
flux diff kustomization games --path=kubernetes/apps/games/romm/app
```
```bash
# Simulate missing secrets for troubleshooting
kubectl apply -f kubernetes/apps/games/romm/app/externalsecret.yaml
kubectl describe secret romm-secret
```

## Versioning Strategy
- The repo stays on a single `main` branch; tags/branches are not deployed directly.
- Chart versions inside each `helmrelease.yaml` (see `kubernetes/apps/games/romm/app/helmrelease.yaml:8-33`) are pinned to avoid drift.

## Evidence
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| Taskfile is the entry point | `Taskfile.yaml` | 🟢 | Tasks like `init`, `configure`, and `kubernetes:kubeconform` orchestrate configuration. |
| Flux + HelmRelease workflow | `kubernetes/apps/games/romm/app/helmrelease.yaml` | 🟢 | Shows Flux-specific settings (`interval`, `dependsOn`, `values`). |
| Placeholder strategy keeps secrets out of Git | `kubernetes/apps/games/romm/app/helmrelease.yaml:65-140` | 🟢 | Uses `${SECRET_DOMAIN}`, `envFrom` referencing `romm-secret`, etc. |
