# 01 – Prerequisites & Repo Layout

> **IaC-only reminder:** Make changes through Git and Flux; `kubectl` is for observation only.

## Kubernetes Requirements
- Cluster version ≥ 1.33 (Talos 1.10.4 reports v1.33.1) with the `MutatingAdmissionPolicy` feature gate enabled (default for beta).
- Admission registration API server feature enabled (standard).

## Repository Conventions
- Use the same structure as other cluster-scoped manifests. Example placement (mirroring Kashalls’ repo):
  - `kubernetes/apps/security/mutating-policies/` – new directory for admission policies.
  - `kustomization.yaml` in `kubernetes/apps/security` updated to include the policies directory.
- No additional controller required; the API server evaluates the policy natively.

## Namespaces / Exceptions
- Decide which namespaces should be exempt (e.g., `kube-system`, `flux-system`, `rook-ceph`, `security`).
- Exemptions will be handled via `matchConditions` or label-based checks in the policy.
