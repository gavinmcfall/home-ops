# Open Questions — Homelab Infrastructure

Document gaps that need answers before Claude/Codex can act unassisted.

## Infrastructure & Design
### What placeholder values must be populated before `task configure` can succeed?
- **Why this matters**: Missing vars halt rendering and Flux reconciling.
- **What we know**: Taskfile uses `makejinja` with placeholders defined implicitly in `bootstrap/config.yaml`, `scripts/`, and `kubernetes/apps/*`.
- **What we’ve tried**: Running `task configure` locally highlights missing names, but we lack a canonical list. 
- **Blocking**: Deployments fail if placeholders like `${SECRET_DOMAIN}` or `${MEDIA_SERVER}` remain untouched.

### Which areas should reuse `/kubernetes/apps/games/romm` storage patterns?
- **Context**: ROMM uses `existingClaim`, `tmpfs`, and NFS layers inside its HelmRelease.
- **Options considered**: Mirror the multiple mounts across other media-heavy workloads or simplify to PVC-only.
- **Impact**: Media assets may need more storage planning before rollout.

## Operations & Performance
### What’s the best metric for assessing Flux’s health besides the README badges?
- **Behavior**: Flux emits `kustomization` status and HelmRelease events.
- **Tools**: `flux get helmrelease`, Grafana dashboards under `dashboards/`, or `flux logs`.
- **Gap**: Need documented thresholds or alerting guidelines referenced by Manifest docs.

## Historical Context
### Why does ROMM rely on NFS (`server: ${MEDIA_SERVER}`) and `existingClaim: romm-data` simultaneously?
- **Current state**: HelmRelease defines multiple storage layers in `persistence`. 
- **History**: Unknown – may be legacy from older deployments.
- **Migration**: Understanding this would make future storage refactors safer.

---
## Answered Questions
*Move resolved items here with answers and sources.*
