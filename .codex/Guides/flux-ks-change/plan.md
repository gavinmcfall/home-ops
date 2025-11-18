# Flux Kustomization Migration Plan

## Target Pattern (Kashalls repo)
- Each namespace folder such as `cloned-repos/homelab-repos/Kashalls/infrastructure/kubernetes/apps/database/kustomization.yaml` declares `namespace: <name>`, imports a shared namespace component, and includes `replacements` from `../../components/replacements/ks.yaml` so Flux `Kustomization` objects inherit the correct namespace.
- Every workload directory (for example `.../apps/database/postgres/ks.yaml`) defines its Flux `Kustomization` inside the workload namespace (`metadata.namespace: database`, `spec.targetNamespace: database`) and optionally adds components like `../../../../components/volsync` plus explicit cross-namespace `dependsOn`.
- Namespace boilerplate (actual `Namespace` resource, Flux alert wiring, VolSync bits) lives under `infrastructure/kubernetes/components`, keeping app folders thin.

## Current State (home-ops)
- Namespace directories such as `home-ops/kubernetes/apps/database` render a bespoke `namespace.yaml` and list every `ks.yaml`, but do **not** set the `namespace:` field on the `kustomization`.
- Flux `Kustomization` objects (example: `home-ops/kubernetes/apps/database/mosquitto/ks.yaml`) all live in `flux-system` and rely on `spec.targetNamespace` to deploy workloads elsewhere. `dependsOn` blocks omit namespaces because everything currently sits in `flux-system`.
- Shared tooling/components do not yet exist, so namespace metadata, VolSync wiring, and Flux notifications are duplicated by hand.

## Migration Workstreams

### 1. Shared components foundation
1. Introduce `home-ops/kubernetes/components/namespace` mirroring Kashalls' `components/namespace`:
   - Base `Namespace` manifest with `name: not-used`, default labels (`kustomize.toolkit.fluxcd.io/prune: disabled`) and annotations common to all namespaces.
   - Optional `alerts` subcomponent if we want per-namespace Flux Alert/Provider resources; can start with only the namespace manifest if alerts are handled elsewhere.
2. Create `home-ops/kubernetes/components/replacements/ks.yaml` so Flux `Kustomization` manifests get `metadata.namespace` and `spec.targetNamespace` auto-populated from the namespace component (same logic as Kashalls' file).
3. If VolSync scaffolding should be reusable, port `components/volsync` and adjust it to our naming (PVC sizes, secret names) ahead of time so workloads can opt-in with `components`.
4. Update developer docs/scripts (e.g. `.taskfiles`, `README`, or `just` recipes) to run `kustomize build ... --load-restrictor=LoadRestrictionsNone` because replacements/components live outside each namespace directory.

### 2. Namespace package conversions
1. For each namespace under `home-ops/kubernetes/apps/*`:
   - Set `namespace: <name>` near the top of its `kustomization.yaml`.
   - Replace the direct `namespace.yaml` resource with the shared component and replacements block:
     ```yaml
     components:
       - ../../components/namespace
     replacements:
       - path: ../../components/replacements/ks.yaml
     ```
   - Drop the old `namespace.yaml` file after its metadata has been migrated.
2. Carry forward namespace-specific labels/annotations currently defined in `namespace.yaml` by adding per-namespace patches under a `patches` or `configurations` folder (e.g. `patches/namespace.yaml` that only adds the extra metadata on top of the shared component).
3. Ensure any namespace-level extras (NetworkPolicies, SecretStores, etc.) remain listed under `resources` so behaviour stays unchanged.
4. Validate each namespace with `kustomize build home-ops/kubernetes/apps/<namespace> --load-restrictor=LoadRestrictionsNone` before moving on.

### 3. Flux `Kustomization` updates
1. Update every `ks.yaml` so the Flux object resides in the workload namespace:
   - `metadata.namespace: <workload-namespace>` (use YAML anchors like Kashalls for reuse) and keep `spec.targetNamespace` pointing to the same anchor.
   - Remove any assumptions that they live in `flux-system`.
2. Review `dependsOn` blocks and add `namespace:` for cross-namespace dependencies (e.g. `dependsOn: [{ name: external-secrets-stores, namespace: external-secrets }]`) so reconciliation order still works once the objects move out of `flux-system`.
3. Where workloads need reusable behaviour (VolSync, alerting, image automation, etc.), add the appropriate `spec.components` entries referencing files under `kubernetes/components`.
4. Keep `sourceRef` pinned to `home-kubernetes` in `flux-system`; no change needed there.
5. Adopt Kashalls' `commonMetadata` pattern consistently so selectors remain identical after the move.

### 4. Flux overlays & automation
1. Confirm `home-ops/kubernetes/flux/apps.yaml` patches continue to target the moved objects. The current selector (`labelSelector: substitution.flux.home.arpa/disabled notin (true)`) should still match resources in other namespaces, but we should run `flux build`/`flux diff` to verify the decryption/postBuild patch still applies.
2. Update any scripting that assumed all Flux `Kustomization`s live in `flux-system` (dashboards, alerts, `kubectl` queries, automation).
3. If GitOps bootstrap or observability dashboards hardcode namespace names, extend them to loop over namespaces or use label selectors instead.

### 5. Rollout strategy
1. Pilot the new layout with a low-risk namespace (e.g. `entertainment`) to prove the component + replacements wiring works. Commit and apply via `flux reconcile kustomization cluster-apps`.
2. Convert infrastructure-critical namespaces (database, network, security, flux-system) once the pilot shows clean `flux diff` output.
3. Tackle remaining namespaces in batches, pausing between each batch to ensure `flux get kustomizations` shows all resources healthy inside their new namespaces.
4. Remove obsolete files (`namespace.yaml`, duplicated VolSync manifests) after every namespace has adopted the shared components.

## Validation & Safety Checks
- `kustomize build kubernetes/apps --load-restrictor=LoadRestrictionsNone` succeeds locally and in CI.
- `flux diff kustomization cluster-apps --context <cluster>` (or equivalent) shows only namespace field moves, not resource churn.
- `flux get kustomizations -A` lists every object in its target namespace with `READY True`.
- Cross-namespace dependencies reconcile (`kubectl -n database get kustomization mosquitto` should show `Ready=True` with dependencies satisfied).
- Rollbacks documented: keep commits small per namespace so we can revert if Flux health degrades.
