# Plane Deployment Approach Review

## Summary
- Deploy Plane into the `home` namespace using the upstream `makeplane/plane` Helm chart pinned to the v1.0.0 release.
- Structure manifests at `kubernetes/apps/home/plane/` mirroring the Sonarr layout (`ks.yaml`, `app/{kustomization,helmrelease,externalsecret}.yaml`, optional `pvc.yaml`).
- Consume existing cluster services for Postgres (CloudNativePG), Dragonfly Redis, and rook-ceph S3 storage; only placeholders with `PLANE_*` keys land in Git.

## Manifests & Layout
- `ks.yaml`: reference `./kubernetes/apps/home/plane/app`, set `targetNamespace: home`, attach VolSync template if a PVC is required, and populate `postBuild.substitute` with `VOLSYNC_*` values when a claim is used.
- `app/kustomization.yaml`: include ExternalSecret, HelmRelease, PVC (if any), and `../../../../templates/volsync` only when backups are desired.
- `app/helmrelease.yaml`: define the Helm chart (`repo: plane`, `chart: plane`), add dependencies on rook-ceph, database services, or volsync as needed, and map values for all Plane components (frontend, backend, space, admin, live) with the provided tags + digests.
- `app/externalsecret.yaml`: follow the Sonarr/Open WebUI pattern, pulling from the 1Password cluster store and templating secrets as `PLANE_*` placeholders (DB URIs, Redis URL, S3 credentials, Django `SECRET_KEY`, admin/OIDC credentials, SMTP settings); match the repo convention where each left-hand key maps to a 1Password field named `PLANE_<KEY>`.

## Configuration Inputs
- Database: CNPG endpoint `postgres17-rw.database.svc.cluster.local:5432`; create separate databases/users per Plane service if required, otherwise reuse a single database with component-specific schemas.
- Cache: point Plane’s Redis settings to `dragonfly.database.svc.cluster.local:6379` with authentication placeholders.
- Object Storage: configure rook-ceph S3 bucket details (endpoint, bucket, access key, secret key) through secrets; ensure the chart is set to use S3-compatible storage.
- Ingress: expose via the `external` ingress class with host `plane.${SECRET_DOMAIN}`; omit Tailscale since this app is externally exposed.
- Persistence: provision a PVC (e.g., 20Gi, rook-ceph block) for uploads/attachments if the chart expects local storage, then wire into VolSync for backups.

## Validation & Delivery
- Run `task kubernetes:kubeconform` for manifest validation, and `flux diff kustomization plane --path kubernetes/apps/home/plane` to review Helm output.
- Commit via conventional message (e.g., `feat(plane): deploy plane stack`) and include kubeconform/flux artifacts in the PR description.
- After secrets exist in 1Password, re-render and confirm ExternalSecret sync before promoting to production.
