# Volsync + Kopia Multi-Destination Backups

This guide walks you through setting up a production-grade backup system using Volsync with Kopia for Kubernetes PVCs. You'll implement a 3-2-1 backup strategy with local NFS and cloud destinations.

## What You'll Learn

- How Volsync orchestrates PVC backups in Kubernetes
- Why Kopia is superior to Restic for backup operations
- Setting up multi-destination backups (NFS + S3)
- Migrating existing apps from Restic to Kopia
- Restoring data from any backup destination

> [!NOTE]
> **GitOps Workflow**: This guide follows GitOps practices. All changes are made by editing files in Git and pushing to trigger Flux reconciliation—never by running `kubectl apply` directly.

---

## Understanding the Architecture

### Why Volsync + Kopia?

**Volsync** is a Kubernetes operator that orchestrates backup and restore operations for Persistent Volume Claims (PVCs). It handles:
- Scheduling backup jobs as Kubernetes pods
- Managing ReplicationSource (backup) and ReplicationDestination (restore) resources
- Coordinating with different backup engines (movers)

**Kopia** is the backup engine that does the actual work:
- Content-addressable storage with deduplication
- Built-in compression and encryption
- Native support for multiple repository types (filesystem, S3, B2, etc.)
- Significantly faster than Restic due to better parallelization

### The 3-2-1 Backup Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Application                          │
│                              PVC                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              Volsync ReplicationSources
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
   ┌──────────┐     ┌──────────┐     ┌──────────┐
   │   NFS    │     │Backblaze │     │Cloudflare│
   │ TrueNAS  │     │    B2    │     │    R2    │
   │ (hourly) │     │ (daily)  │     │ (daily)  │
   └──────────┘     └──────────┘     └──────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
              3 copies, 2 storage types, 1 offsite
```

This implements a proper 3-2-1 strategy:
- **3 copies**: Original PVC + NFS backup + Cloud backup(s)
- **2 storage types**: Local NFS + Cloud object storage
- **1 offsite**: Cloud backups in different geographic regions

### Kopia vs Restic Comparison

| Feature | Restic | Kopia |
|---------|--------|-------|
| Deduplication | Chunk-based | Content-addressed |
| Compression | Per-file | Configurable algorithms |
| Performance | Single-threaded | Highly parallel |
| Repository formats | Limited | Many (S3, B2, filesystem, etc.) |
| Memory usage | Higher | Lower |
| Restore speed | Slower | Faster |

---

## Part 1: Understanding the Component Structure

The Volsync setup uses Kustomize Components—reusable configuration modules that can be added to any application.

### Directory Structure

```
kubernetes/components/volsync/
├── kustomization.yaml          # Main component that includes destinations
├── nfs-truenas/
│   ├── kustomization.yaml      # NFS destination component
│   ├── externalsecret.yaml     # Kopia repository credentials
│   ├── pvc.yaml               # Cache PVC for Kopia
│   ├── replicationdestination.yaml  # For restores
│   └── replicationsource.yaml       # For backups
├── s3-backblaze/
│   ├── kustomization.yaml      # B2 destination component
│   ├── externalsecret.yaml     # B2 credentials
│   └── replicationsource.yaml  # Backup to B2
└── s3-cloudflare/
    ├── kustomization.yaml      # R2 destination component
    ├── externalsecret.yaml     # R2 credentials
    └── replicationsource.yaml  # Backup to R2
```

### How Components Are Used

Applications include the Volsync component in their kustomization:

```yaml
# kubernetes/apps/downloads/radarr/app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./pvc.yaml
components:
  - ../../../../components/volsync
```

The Flux Kustomization provides variables via `postBuild.substitute`:

```yaml
# kubernetes/apps/downloads/radarr/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: radarr
  namespace: downloads
spec:
  # ... other config ...
  postBuild:
    substitute:
      APP: radarr
      VOLSYNC_CAPACITY: 10Gi
```

---

## Part 2: NFS Destination Setup

The NFS destination provides fast, local backups with restore capability.

### ExternalSecret for Kopia Repository

```yaml
# kubernetes/components/volsync/nfs-truenas/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: "${APP}-volsync-nfs"
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect    # Note: NOT "onepassword"
  target:
    name: "${APP}-volsync-nfs"
    template:
      engineVersion: v2
      data:
        KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
  data:
    - secretKey: KOPIA_PASSWORD
      remoteRef:
        key: volsync
        property: KOPIA_PASSWORD
```

### ReplicationSource for Backups

```yaml
# kubernetes/components/volsync/nfs-truenas/replicationsource.yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: "${APP}-nfs"
spec:
  sourcePVC: "${APP}"
  trigger:
    schedule: "0 * * * *"    # Hourly backups
  kopia:
    copyMethod: Snapshot
    snapshotClassName: csi-ceph-block    # Note: NOT "csi-ceph-blockpool"
    repository: "${APP}-volsync-nfs"
    storageClassName: openebs-hostpath
    cacheStorageClassName: openebs-hostpath
    cacheCapacity: 8Gi
    volumeSnapshotClassName: csi-ceph-block
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
    retain:
      hourly: 24
      daily: 7
      weekly: 4
```

### ReplicationDestination for Restores

```yaml
# kubernetes/components/volsync/nfs-truenas/replicationdestination.yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: "${APP}-nfs-dst"
spec:
  trigger:
    manual: restore-once
  kopia:
    copyMethod: Snapshot
    snapshotClassName: csi-ceph-block
    repository: "${APP}-volsync-nfs"
    storageClassName: ceph-block
    cacheStorageClassName: openebs-hostpath
    cacheCapacity: 8Gi
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
    destinationPVC: "${APP}"
    capacity: "${VOLSYNC_CAPACITY}"
```

---

## Part 3: S3 Destinations (Backblaze B2 / Cloudflare R2)

Cloud destinations provide offsite disaster recovery.

### B2 ExternalSecret

```yaml
# kubernetes/components/volsync/s3-backblaze/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: "${APP}-volsync-b2"
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: "${APP}-volsync-b2"
    template:
      engineVersion: v2
      data:
        KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
        AWS_ACCESS_KEY_ID: "{{ .B2_ACCESS_KEY_ID }}"
        AWS_SECRET_ACCESS_KEY: "{{ .B2_SECRET_ACCESS_KEY }}"
  data:
    - secretKey: KOPIA_PASSWORD
      remoteRef:
        key: volsync
        property: KOPIA_PASSWORD
    - secretKey: B2_ACCESS_KEY_ID
      remoteRef:
        key: backblaze
        property: ACCESS_KEY_ID
    - secretKey: B2_SECRET_ACCESS_KEY
      remoteRef:
        key: backblaze
        property: SECRET_ACCESS_KEY
```

### B2 ReplicationSource

```yaml
# kubernetes/components/volsync/s3-backblaze/replicationsource.yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: "${APP}-b2"
spec:
  sourcePVC: "${APP}"
  trigger:
    schedule: "0 3 * * *"    # Daily at 3 AM
  kopia:
    copyMethod: Snapshot
    snapshotClassName: csi-ceph-block
    repository: "${APP}-volsync-b2"
    storageClassName: openebs-hostpath
    cacheStorageClassName: openebs-hostpath
    cacheCapacity: 8Gi
    volumeSnapshotClassName: csi-ceph-block
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
    retain:
      daily: 7
      weekly: 4
      monthly: 3
```

> [!TIP]
> The R2 configuration is nearly identical to B2—just with different credentials and endpoint. Stagger the schedules (e.g., B2 at 3 AM, R2 at 4 AM) to avoid backup contention.

---

## Part 4: NFS Volume Injection with MutatingAdmissionPolicy

Kopia mover pods need access to the NFS share where backups are stored. A MutatingAdmissionPolicy automatically injects the NFS volume mount.

> [!IMPORTANT]
> MutatingAdmissionPolicy is `v1alpha1` in Kubernetes 1.33, not `v1beta1`. Check your cluster version.

### The Policy Definition

```yaml
apiVersion: admissionregistration.k8s.io/v1alpha1
kind: MutatingAdmissionPolicy
metadata:
  name: volsync-nfs-inject
spec:
  failurePolicy: Fail
  matchConstraints:
    matchPolicy: Equivalent
    namespaceSelector: {}
    objectSelector:
      matchLabels:
        volsync.backube/nfs: "true"    # Only pods with this label
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
  matchConditions:
    - name: is-volsync-mover
      expression: "object.metadata.labels.exists(k, k == 'volsync.backube/mover')"
  mutations:
    - patchType: JSONPatch
      jsonPatch:
        expression: |
          [
            JSONPatch{
              op: "add",
              path: "/spec/volumes/-",
              value: {
                "name": "nfs-volsync",
                "nfs": {
                  "server": "10.90.1.69",
                  "path": "/mnt/rust/volsync"
                }
              }
            },
            JSONPatch{
              op: "add",
              path: "/spec/containers/0/volumeMounts/-",
              value: {
                "name": "nfs-volsync",
                "mountPath": "/volsync-nfs"
              }
            }
          ]
```

### Binding the Policy

```yaml
apiVersion: admissionregistration.k8s.io/v1alpha1
kind: MutatingAdmissionPolicyBinding
metadata:
  name: volsync-nfs-inject
spec:
  policyName: volsync-nfs-inject
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: volsync.backube/nfs
          operator: In
          values: ["true"]
```

### Enabling for a Namespace

Add the label to namespaces that need NFS backup:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: downloads
  labels:
    volsync.backube/nfs: "true"
```

---

## Part 5: Migrating an Existing App

This section covers migrating an app from Restic to Kopia backup.

### Step 1: Document Current State

```bash
# Check current backup status
kubectl get replicationsource -n downloads radarr -o yaml

# Verify last successful backup
kubectl describe replicationsource -n downloads radarr | grep -A5 "Last Sync"
```

### Step 2: Scale Down the Application

```bash
# Scale to 0 to ensure data consistency
kubectl scale deployment -n downloads radarr --replicas=0

# Wait for pod termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=radarr -n downloads --timeout=60s
```

### Step 3: Update the Kustomization

Edit the app's kustomization to include the Volsync component:

```yaml
# kubernetes/apps/downloads/radarr/app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./pvc.yaml
components:
  - ../../../../components/volsync    # Add this line
```

### Step 4: Ensure Flux Variables Are Set

```yaml
# kubernetes/apps/downloads/radarr/ks.yaml
spec:
  postBuild:
    substitute:
      APP: radarr
      VOLSYNC_CAPACITY: 10Gi    # Match your PVC size
```

### Step 5: Commit and Reconcile

```bash
cd /home/gavin/home-ops

# Stage and commit
git add kubernetes/apps/downloads/radarr/
git commit -m "feat(radarr): migrate to Kopia backup with Volsync component"

# Push to trigger Flux
git push

# Force reconciliation
flux reconcile kustomization radarr -n flux-system --with-source
```

### Step 6: Verify and Scale Up

```bash
# Check ReplicationSource was created
kubectl get replicationsource -n downloads -l app.kubernetes.io/name=radarr

# Scale back up
kubectl scale deployment -n downloads radarr --replicas=1

# Trigger initial backup
kubectl patch replicationsource radarr-nfs -n downloads \
  --type merge -p '{"spec":{"trigger":{"manual":"initial-backup"}}}'
```

---

## Part 6: Restoring from Backup

### Restore from NFS (Fast)

1. **Scale down the application**:
   ```bash
   kubectl scale deployment -n downloads radarr --replicas=0
   ```

2. **Trigger the restore**:
   ```bash
   kubectl patch replicationdestination radarr-nfs-dst -n downloads \
     --type merge -p '{"spec":{"trigger":{"manual":"restore-now"}}}'
   ```

3. **Monitor progress**:
   ```bash
   kubectl logs -n downloads -l volsync.backube/mover=radarr-nfs-dst -f
   ```

4. **Scale back up**:
   ```bash
   kubectl scale deployment -n downloads radarr --replicas=1
   ```

### Restore from S3 (Disaster Recovery)

For DR scenarios where NFS is unavailable, create a temporary ReplicationDestination pointing to your S3 backup:

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: radarr-b2-restore
  namespace: downloads
spec:
  trigger:
    manual: dr-restore
  kopia:
    copyMethod: Snapshot
    repository: radarr-volsync-b2
    storageClassName: ceph-block
    cacheStorageClassName: openebs-hostpath
    cacheCapacity: 8Gi
    moverSecurityContext:
      runAsUser: 568
      runAsGroup: 568
      fsGroup: 568
    destinationPVC: radarr
    capacity: 10Gi
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| `repository not found` | ExternalSecret not synced | Check `kubectl get externalsecret -n <ns>` for errors |
| Mover pod stuck `Pending` | PVC binding issue | Verify storage class exists and has capacity |
| `permission denied` on NFS | SecurityContext mismatch | Ensure `runAsUser/runAsGroup` matches NFS permissions |
| Backup never completes | Large PVC, slow network | Check mover pod logs, consider increasing timeout |
| `VolumeSnapshotClass not found` | Wrong class name | Use `csi-ceph-block`, not `csi-ceph-blockpool` |

### Checking Backup Status

```bash
# List all ReplicationSources
kubectl get replicationsource -A

# Detailed status for one app
kubectl describe replicationsource radarr-nfs -n downloads

# Check last sync time and duration
kubectl get replicationsource -n downloads -o custom-columns=\
NAME:.metadata.name,\
LAST_SYNC:.status.lastSyncTime,\
DURATION:.status.lastSyncDuration
```

### Viewing Mover Pod Logs

```bash
# Find the mover pod
kubectl get pods -n downloads -l volsync.backube/mover

# Stream logs
kubectl logs -n downloads -l volsync.backube/mover=radarr-nfs -f
```

### Forcing a Manual Backup

```bash
# Trigger immediate backup
kubectl patch replicationsource radarr-nfs -n downloads \
  --type merge -p '{"spec":{"trigger":{"manual":"manual-'$(date +%s)'"}}}'
```

---

## Quick Reference

### Key Resources

| Resource | Purpose |
|----------|---------|
| `ReplicationSource` | Defines backup job (schedule, retention, destination) |
| `ReplicationDestination` | Defines restore configuration |
| `ExternalSecret` | Provides Kopia repository credentials |
| `MutatingAdmissionPolicy` | Auto-injects NFS volumes into mover pods |

### Common Commands

```bash
# Check all backup status
kubectl get replicationsource -A

# Force backup
kubectl patch replicationsource <name> -n <ns> \
  --type merge -p '{"spec":{"trigger":{"manual":"force-'$(date +%s)'"}}}'

# Force restore
kubectl patch replicationdestination <name> -n <ns> \
  --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'

# Watch mover pods
kubectl get pods -A -l volsync.backube/mover -w
```

### Backup Schedule Reference

| Destination | Schedule | Retention |
|-------------|----------|-----------|
| NFS TrueNAS | Hourly (`0 * * * *`) | 24 hourly, 7 daily, 4 weekly |
| Backblaze B2 | Daily (`0 3 * * *`) | 7 daily, 4 weekly, 3 monthly |
| Cloudflare R2 | Daily (`0 4 * * *`) | 7 daily, 4 weekly, 3 monthly |

---

## Glossary

| Term | Definition |
|------|------------|
| **Volsync** | Kubernetes operator that orchestrates PVC backup/restore operations |
| **Kopia** | Backup engine with deduplication, compression, and encryption |
| **Mover Pod** | Temporary pod created by Volsync to perform backup/restore |
| **ReplicationSource** | CRD that defines a backup job |
| **ReplicationDestination** | CRD that defines a restore target |
| **Content-Addressable Storage** | Storage where content is indexed by hash, enabling deduplication |
| **3-2-1 Strategy** | 3 copies of data, 2 different storage types, 1 offsite |

---

## Lessons Learned

These gotchas were discovered during implementation:

| Issue | Wrong | Correct |
|-------|-------|---------|
| ClusterSecretStore name | `onepassword` | `onepassword-connect` |
| VolumeSnapshotClass | `csi-ceph-blockpool` | `csi-ceph-block` |
| MutatingAdmissionPolicy API | `v1beta1` | `v1alpha1` (K8s 1.33) |
| Gateway name | `envoy-internal` | `internal` |
| DNS annotation | `external-dns.alpha...` | `internal-dns.alpha.kubernetes.io/target` |
| PVC dataSource | Can be changed | Immutable after creation—delete and recreate |
| Kopia mover | Standard Volsync | Requires [perfectra1n/volsync](https://github.com/perfectra1n/volsync-kopia) fork |
| Storage class for backups | `ceph-filesystem` | `ceph-block` (see warning below) |

> [!CAUTION]
> The upstream Volsync doesn't have native Kopia support yet. You must use the `perfectra1n/volsync` fork which adds the Kopia mover. Track the upstream PR for when this gets merged.

> [!WARNING]
> **CephFS Sparse File Corruption**: Do not use `ceph-filesystem` storage class for VolSync-backed PVCs. CephFS has a quirk with sparse file handling during restore operations that can silently zero out file contents while preserving file metadata (size, permissions). All VolSync-backed PVCs should use `ceph-block`. Use `ceph-filesystem` only for shared working storage (e.g., media processing) that doesn't need backup/restore.
>
> **Additionally**: Disable `csi.readAffinity.enabled` in your rook-ceph cluster config. This setting can exacerbate CephFS data consistency issues by preferring local OSD reads.
