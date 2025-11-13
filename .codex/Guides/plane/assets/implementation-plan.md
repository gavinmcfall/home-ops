# Plane Deployment Implementation Plan

## 1. Scaffold Repository Structure
- Create `kubernetes/apps/home/plane/` mirroring the Sonarr layout: top-level `ks.yaml` and `app/` folder with `kustomization.yaml`, `helmrelease.yaml`, `externalsecret.yaml`, and (if required) `pvc.yaml` plus the shared VolSync template include.
- Ensure `.gitkeep` or subdirectories are established only where necessary; follow existing repo naming conventions (lowercase, hyphen-free app folder).

## 2. Author Flux Kustomization (`ks.yaml`)
- Set `targetNamespace: home` and apply common labels with `app.kubernetes.io/name: plane`.
- Configure `dependsOn` entries for:
  - `cluster-apps-rook-ceph-cluster`
  - `dragonfly-cluster`
  - `cloudnative-pg-cluster17`
- If VolSync is used, add the template include and populate `postBuild.substitute` values (`VOLSYNC_CLAIM`, `VOLSYNC_CAPACITY`).

## 3. Compose App Kustomization (`app/kustomization.yaml`)
- Reference `externalsecret.yaml`, `helmrelease.yaml`, and any PVC/VolSync templates.
- Keep resources ordered logically (secrets, PVC, HelmRelease) for diff readability.

## 4. Draft ExternalSecret (`app/externalsecret.yaml`)
- Pull from the `onepassword-connect` `ClusterSecretStore` and write to `plane-secret`.
- Organize keys by function (database, Redis, S3, runtime secrets, optional integrations) and follow the `PLANE_<KEY>` convention (e.g., `PLANE_DB_HOST`, `PLANE_REMOTE_REDIS_URL`, `PLANE_S3_ACCESS_KEY`).
- Provide anchors for DB values reused by the init container and Plane env vars; include `POSTGRES_SUPER_PASS` from the shared CNPG secret extract.
- Add placeholders for:
  - `secret_key`, `live_server_secret_key` (include comment showing `openssl rand -hex 32` generation).
  - S3 bucket (`PLANE_DOCSTORE_BUCKET`) and 150 MiB upload limit (`PLANE_DOC_UPLOAD_SIZE_LIMIT`).
  - `NEXT_PUBLIC_DEPLOY_URL` / `cors_allowed_origins` defaults (`https://plane.${SECRET_DOMAIN}`) so they can be overridden later.
- Include extracts for `cloudnative-pg` and `rook-ceph` entries; append any additional 1Password items as needed.

## 5. Build HelmRelease (`app/helmrelease.yaml`)
- Reference the upstream chart with:
  - `chart: plane-ce`
  - `version: 1.2.2`
  - `sourceRef` pointing to the existing `makeplane` HelmRepository in `flux-system`.
- Set update/install remediation defaults consistent with other apps (retry, rollback).
- Under `values`:
  - Pin each component image to the supplied v1.0.0 tag + digest (`plane-frontend`, `plane-backend`, `plane-admin`, `plane-space`, `plane-live`).
  - Disable bundled Postgres/Redis/Minio (`local_setup: false`), but leave RabbitMQ enabled (`local_setup: true`).
  - Wire environment values to the ExternalSecret via `envFrom` and explicit entries (remote Redis URL, docstore bucket, upload limit, public URLs).
  - Configure ingress with class `external`, host `plane.${SECRET_DOMAIN}`, and annotation `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}`; no Tailscale block.
  - Surface resource requests/limits for each Plane deployment, using the defaults from `values.yaml` so they are adjustable later.
  - If local persistence is needed (e.g., shared temp storage), reference `existingClaim` for the PVC; otherwise rely on S3 only.
- Include an init container (using `ghcr.io/home-operations/postgres-init`) wired with the same env anchors as Sonarr to create the database.

## 6. Optional Persistent Volume
- If Plane requires a local PVC (beyond S3), define `app/pvc.yaml` using the rook-ceph storage class and size (default 20 Gi) and reference it in both HelmRelease persistence and VolSync template.
- If no PVC is needed initially, skip this file and omit VolSync references.

## 7. Validation Workflow
- After authoring manifests, run:
  - `task configure` (if any Makejinja templates were touched).
  - `task kubernetes:kubeconform` to ensure schema compliance.
  - `flux diff kustomization plane --path kubernetes/apps/home/plane` for Helm output review.
- Capture kubeconform and flux diff summaries for the eventual PR description.

## 8. Commit Strategy
- Create a feature branch from `main`, group the Plane deployment manifests into a single conventional commit (e.g., `feat(plane): deploy plane stack`).
- Exclude any secret material; only placeholders belong in Git.
- Prepare PR notes covering impacted app (`plane`), dependencies, and validation evidence (kubeconform output, flux diff screenshots/logs).
