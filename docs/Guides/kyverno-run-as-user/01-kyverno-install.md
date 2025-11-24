# 01 – Install Kyverno via Flux

> **IaC-only reminder:** All manifests should be committed to Git and applied by Flux. `kubectl` is for inspection only.

## Repository Targets (Kashalls layout)
- `kubernetes/flux/repositories/helm/kyverno.yaml` already exists (OCI repo). Confirm version/tag desired.
- Add Kyverno release under `kubernetes/apps/security/kyverno/` (new namespace if absent).

## Steps
1. **Namespace & kustomization**
   - Create `kubernetes/apps/security/namespace.yaml` if `security` namespace doesn’t exist.
   - Add `kubernetes/apps/security/kyverno/ks.yaml` referencing the namespace + HelmRelease path.

2. **HelmRelease manifest** (`kubernetes/apps/security/kyverno/app/helmrelease.yaml`)
   - Chart: `kyverno`, use repo `kyverno` (OCI) with desired version (e.g., `v3.2.x`).
   - Values to set:
     - `replicaCount` (e.g., 1/2 depending on cluster size).
     - `serviceMonitor.enabled: true` if Prometheus is scraping.
     - `resources` sized appropriately.
     - `admissionController.service.type: ClusterIP` (default).
     - `config`: exclude namespaces (`kube-system`, `flux-system`, `rook-ceph`, `security`, etc.) using `config.resourceFilters`.
     - Optional: set `generateSuccessEvents: false` to reduce noise.

3. **Flux wiring**
   - Ensure `kubernetes/apps/security/kustomization.yaml` includes the new `kyverno` app.
   - Flux `ks.yaml` should cascade (namespace → app → policies).

4. **Additional RBAC**
   - Not usually required; Kyverno installs its own service account. If PodSecurity Standards are enforced, allow Kyverno deployment accordingly.

5. **Commit & Reconcile**
   - Commit the new manifests.
   - After pushing, use `flux reconcile kustomization cluster-apps-security` (or equivalent) to expedite.

## Validation
- `kubectl get pods -n security` shows `kyverno` pods Running.
- `kubectl get mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg` present.
- Kyverno metrics endpoint available if enabled.
