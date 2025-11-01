# Kyverno Mutation Plan – Enforce `runAsUser`

This guide explains how to add a Kyverno-based admission controller that injects `runAsUser`/`runAsGroup` defaults into pods for the Kashalls-style repo (`home-cluster`). All steps are IaC-only—edit Git, let Flux reconcile, and use `kubectl` only for verification.

- [`01-kyverno-install.md`](./01-kyverno-install.md) – add Kyverno HelmRelease and supporting resources.
- [`02-mutation-policy.md`](./02-mutation-policy.md) – define the ClusterPolicy that assigns `runAsUser`.
- [`03-verification.md`](./03-verification.md) – confirm mutation without imperative changes.
