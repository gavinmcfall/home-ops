# Envoy Migration Rollback Plan

## Reference points
- **Branch**: `envoy-route-migration`
- **Latest migration commit (head)**: `365e00b1 chore(envoy): Final cleanup before tomorrow`
- **Pre-migration baseline**: `f572cb76 chore(codex): New plan for envoy migration` (merge-base with `origin/main`)
- **Primary validation command**: `task kubernetes:kubeconform`
- **Smoke test**: `flux diff kustomization network/envoy-gateway --path kubernetes/apps/network/envoy-gateway`

## Before the PR merges
If you need to stop the rollout before the PR is merged:
1. Checkout the branch locally and hard-reset to the baseline.
   ```bash
   git checkout envoy-route-migration
   git reset --hard f572cb76
   git push --force-with-lease origin envoy-route-migration
   ```
2. This deletes all migration commits from the PR; open a follow-up PR if you still need selective changes.

## After the PR merges
Assuming the PR merges as a single merge commit on `main`, revert that merge to restore every manifest to the baseline.

1. **Update local main and capture the merge SHA.**
   ```bash
   git checkout main
   git fetch origin
   git pull --ff-only origin main
   git log --merges -n 3 --oneline
   ```
   Identify the merge commit for the Envoy migration (it should list `envoy-route-migration` in the log).

2. **Create a revert commit.** Use `-m 1` so git keeps the pre-merge tree.
   ```bash
   export MERGE_SHA=<merge commit from step 1>
   git revert -m 1 "$MERGE_SHA"
   ```
   If multiple follow-up commits landed after the merge, revert them as well (newest to oldest) so the branch matches `f572cb76`.

3. **Validate manifests.**
   ```bash
   task kubernetes:kubeconform
   flux diff kustomization network/envoy-gateway --path kubernetes/apps/network/envoy-gateway
   ```
   (Add other `flux diff` invocations for namespaces you touched if needed.)

4. **Push the revert.**
   ```bash
   git push origin main
   ```
   Optionally open a short “Revert envoy migration” PR so reviewers can confirm.

5. **Force Flux to reconcile.** (Run from your workstation with kubeconfig pointing at the cluster.)
   ```bash
   flux reconcile kustomization cluster-apps --with-source
   flux reconcile kustomization network --with-source
   flux get kustomizations --watch
   ```
   Ensure the `kube-system`, `network`, and `home` namespace resources roll back successfully.

6. **Cluster smoke tests.**
   - `kubectl -n network get gateways,httproutes`
   - Hit a few representative services (e.g., `https://hass.<domain>`, `https://grafana.<domain>`) to verify nginx ingress works again.

7. **Document the incident.** Capture which services broke, timestamps, and why the revert happened so you can adjust the migration plan.

## Emergency rollback (cluster already broken)
If the cluster is unhealthy and you cannot wait for git/Flux:
1. Checkout the existing `main` worktree and create a temporary branch:
   ```bash
   git checkout -b emergency-envoy-rollback
   git reset --hard f572cb76
   ```
2. Build ad-hoc manifests and push them straight to Flux (only if absolutely necessary):
   ```bash
   export KUBE_CONFIG=~/kubeconfig
   kubectl apply -k kubernetes/apps/network/ingress-nginx
   # repeat for other namespaces that need immediate recovery
   ```
3. Once services recover, continue with the formal Git revert so Flux returns to managing state.

## Post-rollback cleanup
- Close or revert the original PR branch (`envoy-route-migration`) so it cannot be accidentally merged again.
- Capture any manual Envoy objects that remain in-cluster (`kubectl get httproutes -A`) and ensure they are deleted or re-applied only when ready.
- Schedule a retrospective before attempting another migration; update this rollback plan with lessons learned.
