# 02 – Define the MutatingAdmissionPolicy

> **IaC-only reminder:** Author YAML in the repo; let Flux apply it. No imperative `kubectl apply`.

## Files to add
- `kubernetes/apps/security/mutating-policies/default-run-as-user.yaml`
- Update `kubernetes/apps/security/kustomization.yaml` to reference the file (or directory glob).

## Policy YAML
```yaml
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingAdmissionPolicy
metadata:
  name: default-run-as-user
spec:
  failurePolicy: Fail
  reinvocationPolicy: IfNeeded
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  matchConditions:
    - name: non-exempt-namespace
      expression: >
        !['kube-system','flux-system','rook-ceph','security'].exists(ns, ns == object.metadata.namespace)
    - name: pod-missing-run-as-user
      expression: >
        has(object.spec) && (!has(object.spec.securityContext) || !has(object.spec.securityContext.runAsUser))
  mutations:
    - patchType: JSONPatch
      jsonPatch:
        expression: >
          [
            JSONPatch{
              op: "add",
              path: "/spec/securityContext",
              value: object.spec.securityContext.orValue(PodSpec.securityContext{})
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsUser",
              value: 568
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsGroup",
              value: 568
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsNonRoot",
              value: true
            }
          ]
---
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingAdmissionPolicyBinding
metadata:
  name: default-run-as-user
spec:
  policyName: default-run-as-user
```

### Notes
- The pod-level `securityContext` applies to all containers that don’t explicitly override `runAsUser`.
- To enforce per-container defaults as well, add additional `JSONPatch` entries for `/spec/containers/0/securityContext/runAsUser` etc., or create separate policies matching `object.spec.containers.exists(...)`.
- You can add a label-based opt-out by extending `matchConditions`:
  ```yaml
  expression: >
    !has(object.metadata.labels) || object.metadata.labels['run-as-user.skip'] != 'true'
  ```
- Start with a limited namespace set; widen as confidence grows.
