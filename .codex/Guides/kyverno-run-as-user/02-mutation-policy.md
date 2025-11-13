# 02 – Create Mutation Policy for `runAsUser`

> **IaC-only reminder:** Define policies in Git; Flux should create/update them. `kubectl` is only for log/manifest inspection.

## File Layout (Kashalls repo)
- Add under `kubernetes/apps/security/kyverno/policies/`.
  - Example: `default-run-as-user.yaml`.
- Extend `kustomization.yaml` to include the policies directory.

## Policy Outline (`ClusterPolicy`)
- Kind: `ClusterPolicy` (global enforcement).
- Metadata: `name: set-default-run-as-user`.
- `spec`:
  ```yaml
  background: true
  validationFailureAction: audit   # use 'enforce' once confident
  rules:
    - name: set-run-as-user
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces:
                - "*"
              namespaceSelector:
                matchExpressions:
                  - key: kyverno.io/ignore
                    operator: DoesNotExist
      exclude:
        any:
          - resources:
              namespaces: [kube-system, flux-system, rook-ceph, security]
      preconditions:
        all:
          - key: "{{ request.object.spec.securityContext.runAsUser || '' }}"
            operator: Equals
            value: ""
      mutate:
        patchesJson6902: |
          - op: add
            path: "/spec/securityContext/runAsUser"
            value: 568
          - op: add
            path: "/spec/securityContext/runAsGroup"
            value: 568
          - op: add
            path: "/spec/securityContext/runAsNonRoot"
            value: true
        foreach:
          - list: "request.object.spec.containers"
            patchesJson6902: |
              - op: add
                path: "/securityContext/runAsUser"
                value: 568
              - op: add
                path: "/securityContext/runAsGroup"
                value: 568
              - op: add
                path: "/securityContext/runAsNonRoot"
                value: true
            preconditions:
              all:
                - key: "{{ element.securityContext.runAsUser || '' }}"
                  operator: Equals
                  value: ""
          - list: "request.object.spec.initContainers"
            ... (same structure)
  ```
- Consider using Kyverno `variables` to keep user/group values configurable (e.g., configmap-driven).
- Provide escape hatch: label namespace or pod with `kyverno.io/ignore: "true"` to bypass.

## Audit Mode First
- Start with `validationFailureAction: audit` to confirm mutations occur without blocking.
- Switch to `enforce` when confident.

## Commit & Reconcile
- Commit policy, update kustomization.
- Reconcile via Flux to apply.
