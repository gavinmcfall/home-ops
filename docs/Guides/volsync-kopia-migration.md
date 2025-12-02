# Deep Dive: Volsync + Kopia for Kubernetes PVC Backup

## Executive Summary

Volsync and Kopia work together to provide robust, deduplicated, encrypted PVC backups in Kubernetes. **Volsync** is the orchestration layer (Kubernetes operator) that manages backup schedules and triggers, while **Kopia** is the backup engine that handles deduplication, compression, encryption, and repository storage.

---

## How They Work Together

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         VOLSYNC + KOPIA ARCHITECTURE                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │   App Pod    │    │   Volsync    │    │     Kopia Repository     │   │
│  │              │    │  Controller  │    │                          │   │
│  │  ┌────────┐  │    │              │    │  ┌────────────────────┐  │   │
│  │  │  PVC   │  │    │  Watches:    │    │  │ NFS / S3 / R2 / B2 │  │   │
│  │  │ (data) │──┼────┼─►Replication │────┼─►│                    │  │   │
│  │  └────────┘  │    │   Source     │    │  │ Deduplicated blobs │  │   │
│  │              │    │              │    │  │ Encrypted at rest  │  │   │
│  └──────────────┘    │  Creates:    │    │  │ Compressed (zstd)  │  │   │
│                      │  Mover Jobs  │    │  └────────────────────┘  │   │
│                      └──────────────┘    │                          │   │
│                                          │  ┌────────────────────┐  │   │
│                             ▲            │  │   Kopia Web UI     │  │   │
│                             │            │  │   (optional)       │  │   │
│                      ┌──────┴──────┐     │  └────────────────────┘  │   │
│                      │ Mover Pod   │     │                          │   │
│                      │ (kopia CLI) │─────┼─► Backup/Restore ops     │   │
│                      └─────────────┘     └──────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Relationship

| Component | Role | What It Does |
|-----------|------|--------------|
| **Volsync** | Orchestrator | Watches ReplicationSource CRDs, creates mover pods on schedule, manages PVC snapshots |
| **Kopia** | Backup Engine | Deduplicates data, compresses with zstd, encrypts, stores in repository |
| **Mover Pod** | Worker | Ephemeral pod created by Volsync containing Kopia CLI to execute backup/restore |
| **Repository** | Storage | Centralized location (NFS/S3/R2) where Kopia stores deduplicated backup blobs |

---

## Backup Flow (Step by Step)

```
1. TRIGGER (Schedule or Manual)
   └── Volsync controller sees ReplicationSource schedule: "0 * * * *" (hourly)

2. SNAPSHOT (if copyMethod=Snapshot)
   └── Volsync requests CSI VolumeSnapshot of source PVC
   └── Point-in-time consistent copy created

3. MOVER POD CREATION
   └── Volsync creates temporary pod with:
       - Kopia CLI binary
       - Mounted snapshot/PVC
       - Repository credentials (from Secret)
       - NFS/S3 repository access

4. KOPIA BACKUP EXECUTION
   └── kopia snapshot create /source
       - Scans all files
       - Chunks data into blocks
       - Deduplicates against existing blocks
       - Compresses new blocks (zstd-fastest)
       - Encrypts with repository password
       - Uploads only new/changed blocks

5. RETENTION ENFORCEMENT
   └── kopia snapshot expire
       - Keeps: 24 hourly, 7 daily (configurable)
       - Removes old snapshot metadata

6. CLEANUP
   └── Volsync deletes mover pod
   └── Volsync deletes temporary snapshot (if used)
   └── Updates ReplicationSource status with last sync time
```

---

## Restore Flow

```
1. TRIGGER (Manual annotation)
   └── User sets trigger.manual: "restore-once" on ReplicationDestination

2. MOVER POD CREATION
   └── Volsync creates restore mover pod

3. KOPIA RESTORE EXECUTION
   └── kopia snapshot restore <snapshot-id> /destination
       - Fetches required blocks from repository
       - Decompresses and decrypts
       - Writes files to destination PVC

4. PVC AVAILABLE
   └── ReplicationDestination.status.latestImage points to restored data
   └── New PVC can use ReplicationDestination as dataSourceRef
```

---

## Three Implementation Approaches Compared

### Your Current Approach (Gavin)
**Backend**: Restic with dual destinations (Backblaze B2 + Cloudflare R2)

```
Templates (kubernetes/templates/volsync/):
├── claim.yaml        # PVC with ReplicationDestination dataSourceRef
├── backblaze.yaml    # ReplicationSource → B2
└── r2.yaml           # ReplicationSource → R2

Apps include via kustomization.yaml:
  resources:
    - ../../../../templates/volsync
```

**Characteristics**:
- Uses standard Volsync with Restic mover
- Dual-destination redundancy (B2 + R2)
- ExternalSecrets from 1Password
- Template-based (postBuild substitution)

### onedr0p's Approach (Devin)
**Backend**: Kopia with centralized NFS repository

```
volsync-system/:
├── volsync/          # perfectra1n/volsync fork (Kopia support)
├── kopia/            # Kopia server with Web UI
└── maintenance/      # KopiaMaintenance CRD for cleanup

components/:
├── volsync/          # Reusable Kustomize component
└── nfs-scaler/       # KEDA-based scaling for NFS availability
```

**Characteristics**:
- Uses perfectra1n/volsync fork with native Kopia mover
- Centralized NFS repository on NAS (expanse.internal)
- Kopia Web UI for browsing backups
- MutatingAdmissionPolicy auto-injects NFS volume
- KEDA scales pods to 0 when NFS unavailable

### joryirving's Approach (Jory)
**Backend**: Kopia with NFS + jitter for large clusters

```
storage/:
├── volsync/              # perfectra1n/volsync fork
├── kopia/                # Kopia server
└── volsync-maintenance/  # Scheduled cleanup jobs

components/:
└── volsync/              # With jitter injection
```

**Characteristics**:
- Same perfectra1n/volsync fork
- **Jitter injection**: Random 0-30s delay prevents thundering herd
- Custom busybox/kopia images
- MutatingAdmissionPolicy for NFS injection

---

## Key Concept: Kopia Mover vs Restic Mover

| Feature | Kopia Mover | Restic Mover |
|---------|-------------|--------------|
| **Deduplication** | Block-level, content-defined | Block-level |
| **Compression** | zstd (configurable levels) | zstd |
| **Encryption** | AES-256-GCM | AES-256 |
| **Repository Types** | Filesystem, S3, B2, SFTP, etc. | S3, B2, Azure, GCS, etc. |
| **Volsync Support** | Via perfectra1n fork | Native in upstream |
| **Web UI** | Yes (optional server) | No |
| **Parallelism** | Configurable | Limited |

**Why use Kopia over Restic?**
1. Better deduplication algorithm (smaller backups)
2. Optional web UI for browsing/restoring
3. Better parallelism support
4. Repository server mode for centralized access

---

## Critical Configuration Elements

### ReplicationSource (Backup)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: myapp
spec:
  sourcePVC: myapp                    # PVC to backup
  trigger:
    schedule: "0 * * * *"             # Cron schedule (hourly)
  kopia:                              # or 'restic:' for Restic
    repository: myapp-volsync-secret  # Secret with credentials
    copyMethod: Snapshot              # Snapshot or Direct
    storageClassName: ceph-block
    volumeSnapshotClassName: csi-ceph-blockpool
    compression: zstd-fastest
    retain:
      hourly: 24
      daily: 7
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
```

### ReplicationDestination (Restore)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: myapp-dst
spec:
  trigger:
    manual: restore-once              # Only restore on-demand
  kopia:
    repository: myapp-volsync-secret
    copyMethod: Snapshot
    capacity: 10Gi                    # Must match or exceed source
    storageClassName: ceph-block
    volumeSnapshotClassName: csi-ceph-blockpool
```

### Repository Secret (Kopia Filesystem)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-volsync-secret
stringData:
  KOPIA_PASSWORD: "your-encryption-password"
  KOPIA_REPOSITORY: "filesystem:///repository"
  KOPIA_FS_PATH: "/repository"
```

### Repository Secret (Restic S3)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-volsync-secret
stringData:
  RESTIC_PASSWORD: "your-encryption-password"
  RESTIC_REPOSITORY: "s3:s3.us-west-000.backblazeb2.com/bucket/myapp"
  AWS_ACCESS_KEY_ID: "keyid"
  AWS_SECRET_ACCESS_KEY: "secretkey"
```

---

## Architecture Decision: Repository Strategy

### Option A: Cloud Object Storage (Your Current)
```
App1 ──► Restic ──► Backblaze B2
    └──► Restic ──► Cloudflare R2
```
**Pros**: Off-site, redundant, no NAS dependency
**Cons**: Egress costs, slower restores, no web UI

### Option B: Centralized NFS + Kopia (onedr0p/joryirving)
```
App1 ─┬─► Kopia ──► NFS Repository ──► Kopia Web UI
App2 ─┤                │
App3 ─┘                └──► (Optional) Sync to B2/R2
```
**Pros**: Fast local restores, web UI, deduplication across apps
**Cons**: NAS is SPOF, needs separate off-site sync

### Option C: Hybrid (Recommended)
```
App ──► Kopia ──► NFS (fast local)
              └──► Scheduled sync to B2/R2 (off-site)
```
**Pros**: Best of both worlds
**Cons**: More complex setup

---

## MutatingAdmissionPolicy Pattern

Both onedr0p and joryirving use this clever pattern to auto-inject NFS access:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingAdmissionPolicy
metadata:
  name: volsync-mover-nfs
spec:
  matchConstraints:
    resourceRules:
      - apiGroups: ["batch"]
        resources: ["jobs"]
        operations: ["CREATE"]
    matchPolicy: Equivalent
  matchConditions:
    - name: is-volsync-job
      expression: "object.metadata.name.startsWith('volsync-')"
  mutations:
    - patchType: JSONPatch
      jsonPatch:
        expression: |
          [
            {"op": "add", "path": "/spec/template/spec/volumes/-",
             "value": {"name": "repository", "nfs": {"server": "nas.internal", "path": "/volsync"}}},
            {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-",
             "value": {"name": "repository", "mountPath": "/repository"}}
          ]
```

This eliminates needing to configure NFS in every app's Volsync secret.

---

## Maintenance Operations

### Kopia Repository Maintenance (Required)
```yaml
apiVersion: volsync.backube/v1alpha1
kind: KopiaMaintenance
metadata:
  name: volsync-maintenance
spec:
  repository: volsync-maintenance-secret
  schedule: "0 */6 * * *"  # Every 6 hours
```

**What it does**:
1. `kopia maintenance run` - Prunes deleted snapshots
2. `kopia blob gc` - Removes orphaned blobs
3. `kopia cache clear` - Cleans up cache

### Repository Unlock (for stuck locks)
```bash
kubectl exec -it kopia-pod -- kopia repository disconnect
kubectl exec -it kopia-pod -- kopia repository connect filesystem --path=/repository
```

---

## Monitoring

### PrometheusRule Alerts
```yaml
- alert: VolSyncVolumeOutOfSync
  expr: volsync_volume_out_of_sync > 0
  for: 15m
  labels:
    severity: critical
```

### Key Metrics
- `volsync_replication_source_status` - Backup status
- `volsync_volume_out_of_sync` - Sync status
- `volsync_replication_destination_status` - Restore readiness

---

## Migration Path: Restic → Kopia

If you want to migrate from your current Restic setup to Kopia:

1. **Deploy perfectra1n/volsync fork** (replaces upstream)
2. **Deploy Kopia server** with NFS-backed repository
3. **Add MutatingAdmissionPolicy** for NFS injection
4. **Update templates** to use `kopia:` instead of `restic:`
5. **Schedule maintenance** with KopiaMaintenance CRD
6. **Optional**: Keep Restic to B2/R2 as secondary backup

---

## Implementation Plan: Fully Restic-Free with Kopia Repository Sync

### Goal
Migrate from Restic to a fully Kopia-based backup system:
1. **Primary**: Kopia → NFS on citadel.internal (hourly backups via Volsync)
2. **Replicated**: Kopia sync-to → Backblaze B2 (daily sync)
3. **Replicated**: Kopia sync-to → Cloudflare R2 (daily sync)

**Key Insight**: Apps backup once to NFS. A separate sync job replicates blobs to cloud. Same password restores from any location.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│              KOPIA-ONLY ARCHITECTURE (Fully Restic-Free)                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   STEP 1: Apps backup to NFS via Volsync (hourly)                       │
│   ┌─────────┐                                                            │
│   │ App PVC │──► Kopia Mover ──► NFS Repository                         │
│   └─────────┘    (hourly)        citadel.internal:/mnt/storage0/backups/volsync          │
│                                       │                                  │
│                                       │ All apps share one               │
│                                       │ deduped repository               │
│                                       ▼                                  │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │                    Kopia NFS Repository                        │     │
│   │  • Hourly snapshots from all apps                             │     │
│   │  • Cross-app deduplication                                    │     │
│   │  • Web UI for browsing (kopia.domain.com)                     │     │
│   │  • Fast local restores                                        │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                       │                                  │
│   STEP 2: CronJobs sync repository to cloud (daily)                     │
│                                       │                                  │
│                    ┌──────────────────┴──────────────────┐              │
│                    ▼                                      ▼              │
│   ┌─────────────────────────────┐    ┌─────────────────────────────┐   │
│   │   kopia-sync-b2 CronJob     │    │   kopia-sync-r2 CronJob     │   │
│   │   Schedule: 0 2 * * *       │    │   Schedule: 0 3 * * *       │   │
│   │   kopia repository sync-to  │    │   kopia repository sync-to  │   │
│   └─────────────┬───────────────┘    └─────────────┬───────────────┘   │
│                 ▼                                    ▼                   │
│   ┌─────────────────────────────┐    ┌─────────────────────────────┐   │
│   │      Backblaze B2           │    │      Cloudflare R2          │   │
│   │   (S3-compatible bucket)    │    │   (S3-compatible bucket)    │   │
│   │   Same encryption keys      │    │   Same encryption keys      │   │
│   │   Same snapshots            │    │   Same snapshots            │   │
│   └─────────────────────────────┘    └─────────────────────────────┘   │
│                                                                          │
│   RESTORE: Same password works for NFS, B2, or R2                       │
│   Priority: NFS (fastest) → B2/R2 (if NAS down)                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Kopia Fixes Restic's Locking

**Restic's Problem**:
- Uses file-based locks to prevent concurrent writes
- Crashed/killed mover jobs leave stale locks
- Next backup fails: `repository is already locked by PID xxx`
- Requires manual intervention: `restic unlock`

**Kopia's Solution**:
- Content-addressable storage (no locks needed)
- Multiple writers can safely write simultaneously
- No stale lock cleanup required
- Built-in maintenance handles orphan blob cleanup

---

### Implementation Steps

#### Phase 1: Deploy Kopia Infrastructure

**1.1 Switch to perfectra1n/volsync fork**

File: `kubernetes/apps/volsync-system/volsync/app/ocirepository.yaml` (NEW)
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: volsync
  namespace: flux-system
spec:
  interval: 12h
  url: oci://ghcr.io/home-operations/charts-mirror/volsync-perfectra1n
  ref:
    tag: 0.17.15
```

File: `kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml` (MODIFY)
```yaml
spec:
  chart:
    spec:
      chart: volsync
      sourceRef:
        kind: OCIRepository  # Changed from HelmRepository
        name: volsync
        namespace: flux-system
  values:
    fullnameOverride: volsync
    image:
      repository: ghcr.io/perfectra1n/volsync
      tag: v0.16.13
    kopia: *image
    restic: *image
```

**1.2 Deploy Kopia Server**

File: `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` (NEW)
- Deploy Kopia with Web UI
- Mount `citadel.internal:/path/to/volsync` at `/repository`
- Expose via HTTPRoute for web access

**1.3 Add MutatingAdmissionPolicy for NFS**

File: `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml` (NEW)
```yaml
# Auto-inject NFS mount into all Volsync mover jobs
# Targets jobs with name prefix "volsync-"
# Mounts citadel.internal:/mnt/storage0/backups/volsync at /repository
```

**1.4 Add Kopia Maintenance**

File: `kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml` (NEW)
```yaml
apiVersion: volsync.backube/v1alpha1
kind: KopiaMaintenance
metadata:
  name: volsync-maintenance
spec:
  repository: volsync-maintenance-secret
  schedule: "0 */6 * * *"  # Every 6 hours
```

#### Phase 2: Update Templates

**New template structure (Restic-free):**
```
kubernetes/templates/volsync/
├── claim.yaml           # PVC (dataSourceRef to Kopia destination)
├── kopia.yaml           # Kopia → NFS (hourly, primary)
├── backblaze.yaml       # DELETE (replaced by sync job)
└── r2.yaml              # DELETE (replaced by sync job)
```

**2.1 kopia.yaml (replaces backblaze.yaml and r2.yaml)**
```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: "${APP}-volsync-kopia"
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: "${APP}-volsync-kopia-secret"
    template:
      data:
        KOPIA_FS_PATH: /repository
        KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
        KOPIA_REPOSITORY: filesystem:///repository
  dataFrom:
    - extract:
        key: volsync-kopia-template
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: "${APP}"
spec:
  sourcePVC: "${VOLSYNC_CLAIM:-${APP}}"
  trigger:
    schedule: "0 * * * *"  # Hourly
  kopia:
    compression: zstd-fastest
    copyMethod: "${VOLSYNC_COPYMETHOD:-Snapshot}"
    repository: "${APP}-volsync-kopia-secret"
    volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:-csi-ceph-block}"
    storageClassName: "${VOLSYNC_STORAGECLASS:-ceph-block}"
    accessModes: ["${VOLSYNC_ACCESSMODES:-ReadWriteOnce}"]
    parallelism: 2
    retain:
      hourly: 24
      daily: 7
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: "${APP}-dst"
spec:
  trigger:
    manual: restore-once
  kopia:
    repository: "${APP}-volsync-kopia-secret"
    copyMethod: Snapshot
    volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:-csi-ceph-block}"
    storageClassName: "${VOLSYNC_STORAGECLASS:-ceph-block}"
    accessModes: ["${VOLSYNC_ACCESSMODES:-ReadWriteOnce}"]
    capacity: "${VOLSYNC_CAPACITY}"
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
```

#### Phase 3: Deploy Kopia Sync CronJobs

**3.1 Sync to Backblaze B2**
```yaml
# kubernetes/apps/volsync-system/kopia/sync/cronjob-b2.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kopia-sync-b2
  namespace: volsync-system
spec:
  schedule: "0 2 * * *"  # Daily at 2am
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: kopia-sync
            image: ghcr.io/home-operations/kopia:0.22.2
            command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "Connecting to source repository..."
              kopia repository connect filesystem --path=/repository --password="${KOPIA_PASSWORD}"
              echo "Syncing to Backblaze B2..."
              kopia repository sync-to s3 \
                --bucket="${B2_BUCKET}" \
                --endpoint="${B2_ENDPOINT}" \
                --access-key="${B2_ACCESS_KEY}" \
                --secret-access-key="${B2_SECRET_KEY}" \
                --parallel=4 \
                --delete
              echo "Sync complete!"
            envFrom:
            - secretRef:
                name: kopia-sync-b2-secret
            volumeMounts:
            - name: repository
              mountPath: /repository
              readOnly: true
          volumes:
          - name: repository
            nfs:
              server: citadel.internal
              path: /mnt/storage0/backups/volsync
```

**3.2 Sync to Cloudflare R2**
```yaml
# kubernetes/apps/volsync-system/kopia/sync/cronjob-r2.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kopia-sync-r2
  namespace: volsync-system
spec:
  schedule: "0 3 * * *"  # Daily at 3am (staggered)
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: kopia-sync
            image: ghcr.io/home-operations/kopia:0.22.2
            command:
            - /bin/sh
            - -c
            - |
              set -e
              kopia repository connect filesystem --path=/repository --password="${KOPIA_PASSWORD}"
              kopia repository sync-to s3 \
                --bucket="${R2_BUCKET}" \
                --endpoint="${R2_ENDPOINT}" \
                --access-key="${R2_ACCESS_KEY}" \
                --secret-access-key="${R2_SECRET_KEY}" \
                --parallel=4 \
                --delete
            envFrom:
            - secretRef:
                name: kopia-sync-r2-secret
            volumeMounts:
            - name: repository
              mountPath: /repository
              readOnly: true
          volumes:
          - name: repository
            nfs:
              server: citadel.internal
              path: /mnt/storage0/backups/volsync
```

**3.3 ExternalSecrets for sync credentials**
```yaml
# kubernetes/apps/volsync-system/kopia/sync/externalsecret-b2.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: kopia-sync-b2
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: kopia-sync-b2-secret
  dataFrom:
    - extract:
        key: volsync-kopia-template  # KOPIA_PASSWORD
    - extract:
        key: backblaze               # B2_BUCKET, B2_ENDPOINT, B2_ACCESS_KEY, B2_SECRET_KEY
```

#### Phase 4: 1Password Secrets

**Create new entry: `volsync-kopia-template`**
```
KOPIA_PASSWORD: <strong-encryption-password>
```

**Update existing: `backblaze`**
```
B2_BUCKET: your-bucket-name
B2_ENDPOINT: s3.us-west-000.backblazeb2.com
B2_ACCESS_KEY: keyId
B2_SECRET_KEY: applicationKey
```

**Update existing: `cloudflare`**
```
R2_BUCKET: your-bucket-name
R2_ENDPOINT: <account-id>.r2.cloudflarestorage.com
R2_ACCESS_KEY: accessKeyId
R2_SECRET_KEY: secretAccessKey
```

---

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `volsync-system/volsync/app/ocirepository.yaml` | CREATE | OCI source for perfectra1n chart |
| `volsync-system/volsync/app/helmrelease.yaml` | MODIFY | Switch to perfectra1n fork |
| `volsync-system/volsync/app/mutatingadmissionpolicy.yaml` | CREATE | NFS injection for mover jobs |
| `volsync-system/kopia/app/helmrelease.yaml` | CREATE | Kopia server + web UI |
| `volsync-system/kopia/app/externalsecret.yaml` | CREATE | Kopia credentials |
| `volsync-system/kopia/ks.yaml` | CREATE | Flux Kustomization |
| `volsync-system/kopia/sync/cronjob-b2.yaml` | CREATE | Sync to B2 CronJob |
| `volsync-system/kopia/sync/cronjob-r2.yaml` | CREATE | Sync to R2 CronJob |
| `volsync-system/kopia/sync/externalsecret-b2.yaml` | CREATE | B2 credentials |
| `volsync-system/kopia/sync/externalsecret-r2.yaml` | CREATE | R2 credentials |
| `volsync-system/volsync/maintenance/kopiamaintenance.yaml` | CREATE | Repository maintenance |
| `templates/volsync/kopia.yaml` | CREATE | Kopia template (replaces backblaze+r2) |
| `templates/volsync/backblaze.yaml` | DELETE | No longer needed |
| `templates/volsync/r2.yaml` | DELETE | No longer needed |
| `templates/volsync/claim.yaml` | MODIFY | Point to Kopia destination |

---

### Gradual Migration Strategy (Don't Smash Your Systems)

The key is running both systems in parallel until you're confident, then cutting over.

#### Week 1: Infrastructure Only (No App Changes)

```
┌─────────────────────────────────────────────────────────────────┐
│  WEEK 1: Deploy Kopia alongside existing Restic                 │
│                                                                  │
│  Existing Restic backups continue running normally              │
│  New Kopia infrastructure deployed but not used by apps yet    │
└─────────────────────────────────────────────────────────────────┘
```

**Steps:**
1. Create NFS share on citadel: `/mnt/storage0/backups/volsync` (alongside crunchydata backups)
2. Create 1Password entry: `volsync-kopia-template`
3. Deploy perfectra1n/volsync fork (keeps Restic working)
4. Deploy Kopia server + web UI
5. Set up MutatingAdmissionPolicy
6. **Do NOT modify any app templates yet**

**Validation:**
- [ ] Kopia web UI accessible
- [ ] Restic backups still running on schedule
- [ ] No changes to existing app behavior

#### Week 2: Pilot App (Single App Migration)

```
┌─────────────────────────────────────────────────────────────────┐
│  WEEK 2: Migrate ONE non-critical app                           │
│                                                                  │
│  recyclarr: Kopia to NFS (hourly)                               │
│  All other apps: Still Restic to B2/R2 (existing)              │
└─────────────────────────────────────────────────────────────────┘
```

**Steps:**
1. Pick pilot app: `recyclarr` (low-risk, small data)
2. Create app-specific Kopia ReplicationSource manually (not via template)
3. Keep existing Restic ReplicationSources running in parallel
4. Wait 24-48 hours, verify Kopia backups appearing in web UI
5. Test restore from Kopia to a test PVC
6. If restore works, disable Restic for this app only

**Validation:**
- [ ] Kopia snapshots visible in web UI for recyclarr
- [ ] Hourly backups running
- [ ] Test restore successful
- [ ] Restic backups for other apps unaffected

#### Week 3: Sync Jobs + More Apps

```
┌─────────────────────────────────────────────────────────────────┐
│  WEEK 3: Enable cloud sync + migrate more apps                  │
│                                                                  │
│  Kopia NFS → Sync to B2 + R2 (CronJobs)                        │
│  Migrate 3-5 more apps to Kopia                                 │
│  Keep Restic as fallback for remaining apps                    │
└─────────────────────────────────────────────────────────────────┘
```

**Steps:**
1. Deploy sync CronJobs (B2 and R2)
2. Run first sync manually: `kubectl create job --from=cronjob/kopia-sync-b2 kopia-sync-b2-manual`
3. Verify blobs appear in B2/R2 buckets
4. Test connecting to B2 repository: `kopia repository connect s3 --bucket=... --password=...`
5. Migrate 3-5 more apps (bazarr, prowlarr, sabnzbd, etc.)

**Validation:**
- [ ] Sync jobs completing successfully
- [ ] Blobs visible in B2 and R2 buckets
- [ ] Can connect and list snapshots from cloud repositories
- [ ] Multiple apps backing up via Kopia

#### Week 4: Template Cutover

```
┌─────────────────────────────────────────────────────────────────┐
│  WEEK 4: Update templates, full migration                       │
│                                                                  │
│  All apps: Kopia to NFS (hourly)                                │
│  Cloud: Synced via CronJobs (daily)                             │
│  Restic: Disabled (templates deleted)                           │
└─────────────────────────────────────────────────────────────────┘
```

**Steps:**
1. Update templates:
   - Create `templates/volsync/kopia.yaml`
   - Modify `templates/volsync/claim.yaml` to use Kopia destination
   - Delete `templates/volsync/backblaze.yaml`
   - Delete `templates/volsync/r2.yaml`
2. Commit and push
3. Flux reconciles all apps to new templates
4. Old Restic ReplicationSources are deleted (pruned)

**Validation:**
- [ ] All apps showing Kopia backups in web UI
- [ ] Cloud syncs running daily
- [ ] No Restic ReplicationSources remaining
- [ ] Restore test from each destination (NFS, B2, R2)

#### Week 5+: Cleanup & Monitoring

**Steps:**
1. Delete old Restic data from B2/R2 (after 30 days retention)
2. Remove unused 1Password entries
3. Set up alerting for:
   - Volsync sync failures
   - Kopia sync job failures
   - Repository out of sync

---

### Rollback Plan

If issues arise at any stage:

**During Week 1-2:**
- Restic is still primary, just delete Kopia resources
- No data loss risk

**During Week 3:**
- Re-enable Restic for affected apps
- Kopia and Restic can coexist

**During Week 4:**
- Restore templates from git history
- Re-create Restic ReplicationSources
- Kopia backups remain as secondary

**Key Point:** Keep your old Restic backups in B2/R2 for at least 30 days after full cutover.

---

## Sources

- [Kopia Repository Sync-to S3](https://kopia.io/docs/reference/command-line/common/repository-sync-to-s3/) - Sync command reference
- [Kopia Synchronization](https://kopia.io/docs/advanced/synchronization/) - How repository sync works
- [Kopia Repository Server](https://kopia.io/docs/repository-server/) - Server mode for web UI
- [perfectra1n/volsync fork](https://github.com/perfectra1n/volsync) - Kopia mover support for Volsync
- [VolSync Documentation](https://volsync.readthedocs.io/en/latest/) - Official Volsync docs
