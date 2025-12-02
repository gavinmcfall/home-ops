# Volsync + Kopia in this cluster

This note captures the current backup setup (Volsync + restic), why Kopia is attractive, and a concrete path to add Kopia while keeping the existing Flux/kustomize patterns.

## Current state (this repo)
- Volsync deployed from the upstream chart v0.13.1 (`kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml`); CSI snapshot-controller is present.
- Templates at `kubernetes/templates/volsync` are restic-based (Backblaze B2 + Cloudflare R2 ExternalSecrets, ReplicationSource + ReplicationDestination, PVC seeded via `dataSourceRef`, cache on `openebs-hostpath`, storage on `ceph-block`).
- Apps opt in via postBuild substitution (`APP`, `VOLSYNC_CAPACITY`) and add `../../../../templates/volsync` to their `kustomization.yaml` (example: `kubernetes/apps/entertainment/audiobookshelf/ks.yaml`).
- No Kopia mover or Kopia server is deployed; no KopiaMaintenance jobs; offsite targets are restic.

## Why add Kopia
- Faster + safer incrementals: Volsync’s Kopia mover keeps block-level dedup inside a repository instead of per-snapshot fulls. Less network/storage, better for frequent jobs.
- Repo health + retention: KopiaMaintenance handles prune/repack; corruption is surfaced sooner. Restic pruning can be slower on large repos.
- Multiple backends: Use NAS (`citadel.internal`) for hot restores and optionally sync to B2/R2 for offsite, using the same toolset.
- Operational parity with peers: onedr0p and joryirving both run Volsync+Kopia; you can lift their patterns with minimal drift.

## Implementation plan
1) **Upgrade Volsync chart to a Kopia-capable build**
   - Bump to ~0.17.x with the perfectra1n image (ships Kopia mover) like onedr0p/joryirving.
   - Keep `manageCRDs: true`, `metrics.disableAuth: true`, and run as non-root.

2) **Deploy a Kopia server in-cluster**
   - Use bjw-s app-template HelmRelease (see onedr0p `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` or joryirving `.../base/storage/kopia/helmrelease.yaml`).
   - Back it by NAS export on `citadel.internal` (e.g., `/srv/nfs/volsync-kopia`); mount at `/repository`.
   - ExternalSecret supplies `KOPIA_PASSWORD` and `KOPIA_REPOSITORY=filesystem:///repository`; enable web UI if desired.
   - Optional: add `nfs-scaler` (KEDA) to scale Kopia to zero if NAS is unreachable.

3) **Add a Kopia-based Volsync component/template**
   - Mirror onedr0p/joryirving components: ReplicationSource/ReplicationDestination using `spec.kopia`, `copyMethod: Snapshot`, cache PVC on hostpath, storage on ceph-block, retention (e.g., hourly 24, daily 7).
   - PVC uses `dataSourceRef` -> `${APP}-dst` so restores create a fresh PVC.
   - Keep the same postBuild vars (`APP`, `VOLSYNC_CAPACITY`, optional storageClass overrides) to avoid app changes.
   - Ensure mover securityContext matches app UID/GID; set `enableFileDeletion: true` if you want deletions propagated.

4) **Maintenance + monitoring**
   - Add `KopiaMaintenance` CR (daily/6h) against the Kopia repo secret to prune/repack.
   - Keep PrometheusRule alerts from the Volsync chart; add Grafana dashboard if desired (see onedr0p/joryirving).

5) **Offsite strategy**
   - Option A: Keep restic B2/R2 templates for a second target (parallel jobs).
   - Option B: Use Kopia `repository sync-to` to push the NAS repo to B2 or R2 on a schedule (reduces double backup jobs).

## Minimal kustomize wiring (pattern)
- Flux KS: add postBuild substitutions (`APP`, `VOLSYNC_CAPACITY`) and include the Kopia volsync component/template in `app/kustomization.yaml`.
- Secrets: ExternalSecret for Kopia repo creds (`${APP}-volsync-secret`) plus optional offsite secret.
- KS depends on storage if needed (rook-ceph) to ensure PVC classes exist before Volsync runs.

## Restore flow (Kopia mover)
1) Stop writers if needed (scale app to 0 or pause).
2) Set `ReplicationDestination.spec.trigger.manual: restore-once` (or annotate) and apply; Volsync rehydrates `${APP}-dst` and the bound app PVC via `dataSourceRef`.
3) Scale app back up; confirm data.

## References to copy from
- onedr0p Kopia server: `/home/gavin/cloned-repos/homelab-repos/onedr0p(Devin)/home-ops/kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml`
- onedr0p Kopia Volsync component: `/home/gavin/cloned-repos/homelab-repos/onedr0p(Devin)/home-ops/kubernetes/components/volsync`
- joryirving Kopia server: `/home/gavin/cloned-repos/homelab-repos/LilDrukenSmurf(joryireving)/home-ops/kubernetes/apps/base/storage/kopia/helmrelease.yaml`
- joryirving Kopia Volsync component: `/home/gavin/cloned-repos/homelab-repos/LilDrukenSmurf(joryireving)/home-ops/kubernetes/components/volsync`
