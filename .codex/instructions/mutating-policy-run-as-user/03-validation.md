# 03 – Validation & Monitoring

> **IaC-only reminder:** Use kubectl solely for inspection.

## Checklist
1. **Policy presence**
   - `kubectl get mutatingadmissionpolicies` should list `default-run-as-user` (note API is v1beta1).
   - `kubectl get mutatingadmissionpolicybindings` shows the binding.

2. **Test Pod**
   - Add a test Deployment/Pod manifest via Git with no `runAsUser`.
   - After Flux reconciliation, inspect:
     ```bash
     kubectl get pod <name> -o yaml | rg "runAs"
     ```
     Expect `runAsUser: 568`, `runAsGroup: 568`, `runAsNonRoot: true` at the pod level.

3. **Exemption test**
   - Deploy a pod in an exempt namespace or with opt-out label.
   - Confirm it retains original securityContext.

4. **Metrics / Auditing**
   - The API server does not expose per-policy metrics yet. Use audit logs (if enabled) or count pods lacking runAsUser after creation.

5. **Failure handling**
   - If mutations fail and `failurePolicy: Fail`, pod admission will be denied. Monitor API server events for failures and adjust policy accordingly.

## Troubleshooting
- Ensure the cluster feature gate supports `MutatingAdmissionPolicy` (Kubernetes v1.33+).
- Check API server logs if policies are not invoked.
- Verify `matchConditions` expressions using CEL syntax (e.g., run through `cel-cli` or simplify expressions for debugging).
