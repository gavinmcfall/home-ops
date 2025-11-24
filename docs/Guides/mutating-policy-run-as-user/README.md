# MutatingAdmissionPolicy Plan – Default `runAsUser`

This guide describes how to enforce a default `runAsUser`/`runAsGroup` using the native Kubernetes `MutatingAdmissionPolicy` API (v1beta1), similar to WaifuLabs’ approach. All actions are IaC-only: commit YAML to Git, let Flux reconcile, and use `kubectl` just to observe.

- [`01-prereqs.md`](./01-prereqs.md) – prerequisites and repo layout.
- [`02-policy-definition.md`](./02-policy-definition.md) – author the MutatingAdmissionPolicy + binding.
- [`03-validation.md`](./03-validation.md) – verify the mutation is happening.
