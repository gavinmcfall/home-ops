# 03 – Verification & Monitoring

> **IaC-only reminder:** Validation uses read-only kubectl commands—no imperative patches.

## Quick Checks
1. **Kyverno readiness**
   - `kubectl get pods -n security` → `kyverno` pods should be Running.
   - `kubectl logs -n security deploy/kyverno -f` to confirm no webhook errors.

2. **Mutation behaviour**
   - Deploy a sample workload via Git (e.g., `kubernetes/tests/run-as-user-check/deployment.yaml`) without securityContext.
   - After Flux applies:
     ```bash
     kubectl get pod -n tests <pod> -o yaml | rg "runAs"
     ```
     Expect injected `runAsUser: 568`, `runAsGroup: 568`, `runAsNonRoot: true`.

3. **Audit results**
   - `kubectl get clusterpolicy set-default-run-as-user -o yaml` → check `status.rules[].mutate.count`.
   - Kyverno metrics: scrape `kyverno-policies-mutation-total` to observe hits.

4. **Escaping the policy**
   - Label a namespace or pod with `kyverno.io/ignore: "true"` through Git.
   - Ensure mutation is skipped (pod retains original securityContext).

5. **Switch to enforce**
   - Once satisfied, update policy `validationFailureAction: enforce` in Git and reconvene.

## Troubleshooting
- Check Kyverno events: `kubectl get events -n security --field-selector involvedObject.kind=Pod`.
- Use `kyverno cli test` locally against YAML samples before committing.
- Monitor webhook latency via Kyverno metrics to ensure no bottleneck.
