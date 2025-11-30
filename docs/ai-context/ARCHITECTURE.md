# Homelab Architecture Overview

## Core Pattern
**Pattern**: GitOps + templated manifest pipeline. Taskfile and Makejinja render values (`Taskfile.yaml`, `.taskfiles/*`, `makejinja.toml`), Flux applies the results under `kubernetes/apps/*`, and Talos controls node configuration locally.
**Chosen Because**: Keeps every change traceable in Git, avoids manual `kubectl`, and lets Flux automatically roll out updates.
**Trade-off**: Bundle of placeholders means deployments fail until secrets (placeholders like `${SECRET_DOMAIN}`) are resolved, so authors must update documents before merges.
**Not Because**: This is not a multi-tenant SaaS platform—it's tuned for a single homelab operator.

## Key Decisions
### Decision 1: Taskfile-driven render pipeline
**Context**: Need reproducible templates for configs used by Flux and Talos.
**Decision**: Use `Taskfile.yaml` to orchestrate `makejinja`, flux checks, and `kubeconform` validation.[Taskfile.yaml:1-80]
**Consequences**:
- ✅ Every developer runs the same `task configure` command so manifests match what Flux will apply.
- ⚠️ Taskfile adds indirection; you must keep vars in sync (e.g., `bootstrap/config.yaml`, `scripts/`).
- ❌ Manual `kubectl apply` is discouraged because it bypasses GitOps.

### Decision 2: Flux + HelmRelease per app
**Context**: Desire flexible service ownership while keeping the cluster consistent.
**Decision**: Each app (games, plane, etc.) lives in its own `kubernetes/apps/<namespace>` folder with HelmRelease, ExternalSecret, and kustomization manifests.[kubernetes/apps/games/romm/app/helmrelease.yaml]
**Impact**:
- ✅ Dependencies/lifecycle captured via `dependsOn`, `remediation`, and pinned chart versions.
- ⚠️ You need to wire the HelmRelease into the area `kustomization.yaml` or Flux will skip it.
- ❌ Rolling out ephemeral workloads requires new directories or careful cleanup.

### Decision 3: Placeholder-first secret management
**Context**: Repo is public; sensitive values must not leak.
**Decision**: Use placeholder names (`${SECRET_DOMAIN}`, `${NFS_STORAGE_HOST}`, `PLANE_*`) and resolve them through ExternalSecrets or manual replacements before deployment.[kubernetes/apps/games/romm/app/helmrelease.yaml:90-140]
**Alternatives Considered**: Inline secrets, sealed secrets.
**Why This Won**: Placeholders keep reviewers confident nothing secret is checked in while still documenting required keys.

## Constraints
### Must Always Be True
1. Flux only applies what `task configure` renders; never directly edit generated artifacts under `kubernetes/apps/*`.
2. Placeholder values such as `${SECRET_DOMAIN}` and `${MEDIA_SERVER}` must be documented before use.
3. Storage-heavy workloads should explicitly define PVCs/NFS mounts to avoid missing resources at runtime.

### Performance Targets
- **Designed For**: A handful of Flux reconcilable workloads (games, plane, observability) with moderate traffic.
- **Not Designed For**: Public-facing, high-throughput APIs with sub-100ms guarantees.
- **Scaling Strategy**: Add nodes via `talosconfig/` updates and `task configure`, then let Flux redeploy.

## Operational Limits
### Resource Limits
| Resource | Limit | What Happens When Exceeded |
|----------|-------|---------------------------|
| Flux reconciliation interval | ~5m | Delay in deployment; `flux get kustomizations` shows `Reconciling` until fixed. |
| PVC capacity | Defined per workload | Apps like ROMM fail with `Pending` pods if claim is missing. |
| Template vars | Taskfile variables | Missing placeholders stop `makejinja` rendering.

### Circuit Breakers
- **Secrets placeholder mismatch**: Flux fails; check `${SECRET_DOMAIN}` usage in `kubernetes/apps/*/app/helmrelease.yaml`.
- **Storage path misconfig**: ROMM's `media` mount references `${MEDIA_SERVER}` and requires the `romm-data` claim, documented in `kubernetes/apps/games/romm/app/helmrelease.yaml`.

## Common Failures
### Flux can't render HelmRelease
**Symptoms**: `helm` hook errors in Flux status.
**Cause**: Missing placeholder, invalid value, or unrendered template from `.taskfiles/Kubernetes`.
**Immediate Fix**: Run `task configure` locally, check `kubernetes/apps/<namespace>/app` output for errors.
**Long-term Fix**: Document required placeholders in `TEMPLATE_GUIDE.md` and evidence table.

### Secrets unresolved
**Symptoms**: Pods crash with missing env entries or fail `envFrom`.
**Cause**: ExternalSecret not populated from vault yet.
**Fix**: Trigger vault sync (ExternalSecrets logs) and ensure login to private 1Password before pushing.

### Storage claim missing
**Symptoms**: Pods stay `Pending` waiting for `romm-data` or other PVCs.
**Cause**: PVC definition absent or claim mismatch.
**Fix**: Create PVC or update HelmRelease to use existing claim, then rerun `flux diff`.

## Monitoring
### Key Metrics
- `flux_kustomization_status` – ensures overlays are healthy.
- `${SERVICE}_request_duration_seconds` – tracked via dashboards referenced in `README.md`.
- `external_secrets_sync_success_total` – watch for missing secrets before deployments.

### Dashboards
- Grafana dashboards configured via `dashboards/` and exposed by Flux.
- Status badges referenced in `README.md` (e.g., `https://status.${SECRET_DOMAIN}`).

## Technology Stack
- **Runtime**: Kubernetes (Talos) with Helm + Flux.
- **Provisioning**: Taskfile/Makejinja templates, `bootstrap/` scripts, `talosconfig/` configs.
- **Secrets**: ExternalSecrets + placeholder names (see `TEMPLATE_GUIDE.md`).
- **Storage**: PVCs and NFS mounts defined in HelmRelease values (ROMM example). Adjust via `kubernetes/apps/*/app/helmrelease.yaml`.
- **Validation**: `task kubernetes:kubeconform`, `flux diff`, `flux reconcile`.

---
## Evidence
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| Taskfile orchestrates rendering/validation | `Taskfile.yaml` | 🟢 | Includes `.taskfiles/Kubernetes`, `.taskfiles/Talos`, `.taskfiles/Flux`, etc., plus renders via `makejinja`. |
| Fluent HelmRelease layout per area | `kubernetes/apps/games/romm/app/helmrelease.yaml` | 🟢 | Shows values, env placeholders, dependencies, storage definitions. |
| Secrets handled through placeholders | `kubernetes/apps/games/romm/app/helmrelease.yaml:65-140` | 🟢 | `${SECRET_DOMAIN}`, ExternalSecret references, `envFrom`. |
