# Flux KS Migration – Review Guide

## Context
- Branch: `feature/flux-ks-migration`
- Scope: move every Flux `Kustomization` out of `flux-system`, add namespace/replacement components, and convert the VolSync/Gatus templates into reusable components consumed via `spec.components`.
- Docs: high-level migration plan lives in `.codex/Guides/flux-ks-change/plan.md`.

## Files To Inspect First
1. `kubernetes/components/` – new reusable namespace, replacements, volsync, and gatus components.
2. `kubernetes/apps/*/kustomization.yaml` – verify namespace declaration, component include, replacement reference, and namespace patches.
3. Representative Flux objects such as `kubernetes/apps/database/cloudnative-pg/ks.yaml`, `kubernetes/apps/home/bookstack/ks.yaml`, and `kubernetes/apps/network/cloudflared/ks.yaml` to confirm `metadata.namespace`, `spec.targetNamespace`, `components`, and `dependsOn` wiring.
4. Removed legacy templates under `kubernetes/templates/` (now replaced by the components above).

## Diff Access
- Full diff vs. `origin/main` is captured in `REVIEW.diff` (generated with `git diff origin/main...feature/flux-ks-migration`).
- If you prefer running commands:  
  `git checkout feature/flux-ks-migration`  
  `git diff origin/main...`

## Validation Performed
- `kustomize build kubernetes/apps/database --load-restrictor=LoadRestrictionsNone`
- `kustomize build kubernetes/apps/entertainment --load-restrictor=LoadRestrictionsNone`

## Suggested Review Flow
1. Skim `REVIEW.md` (this file) and `.codex/Guides/flux-ks-change/plan.md` for intent.
2. Open `REVIEW.diff` to see the full patch in one place.
3. Spot-check a few namespace directories to make sure custom labels/annotations carried over to `patches/namespace.yaml`.
4. Ensure Flux objects with `dependsOn` across namespaces now declare `namespace` for each dependency and still reference `sourceRef.namespace: flux-system`.
5. Confirm VolSync/Gatus consumers now rely on `spec.components` and that app-level kustomizations no longer include deleted template folders.

Let me know if you need a narrower diff or specific files extracted for the review.
