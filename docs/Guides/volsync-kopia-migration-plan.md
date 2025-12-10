# Volsync Kopia Migration Plan

## Status Overview

| Component | Status | Details |
|-----------|--------|---------|
| Kopia Server | ✅ Running | `https://kopia.nerdz.cloud` |
| MutatingAdmissionPolicy | ✅ Active | Auto-injects NFS volume into volsync mover pods |
| Volsync Component | ✅ Ready | `kubernetes/components/volsync/` |
| NFS Repository | ✅ Initialized | `citadel.internal:/mnt/storage0/backups/VolsyncKopia` |
| Homepage Widget | ✅ Added | Storage section |

### Completed Migrations

| App | Namespace | Size | Status |
|-----|-----------|------|--------|
| romm | games | 156.3 MB | ✅ Hourly backups working |

---

## Critical Conventions

These were learned through trial and error - **do not deviate**:

```yaml
# Storage classes (NOT ceph-block-storage or csi-ceph-blockpool)
storageClassName: ceph-block
volumeSnapshotClassName: csi-ceph-block

# Gateway routing (NOT envoy-internal)
parentRefs:
  - name: internal
    namespace: network
    sectionName: https

# DNS annotation - REQUIRED for hostname resolution
annotations:
  internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}

# Hostname pattern
hostnames:
  - "{{ .Release.Name }}.${SECRET_DOMAIN}}"

# Security context - standard UID for this cluster
runAsUser: 568
runAsGroup: 568
fsGroup: 568

# ExternalSecrets store (NOT "onepassword")
secretStoreRef:
  name: onepassword-connect
  kind: ClusterSecretStore

# Timezone - use variable, not hardcoded
TZ: ${TIMEZONE}
```

---

## Migration Process

### Pre-Flight Checks

```bash
# 1. Check PVC name matches ${APP} pattern
kubectl get pvc -n <namespace> | grep <app>

# 2. Check current security context
kubectl get deploy <app> -n <namespace> -o jsonpath='{.spec.template.spec.securityContext}' | jq

# 3. Check for existing Restic backups
kubectl get replicationsource -n <namespace> <app>-rsrc -o yaml

# 4. Verify Kopia server is healthy
kubectl get pods -n storage -l app.kubernetes.io/name=kopia
```

### Standard Migration (PVC name matches ${APP})

**Step 1: Update kustomization.yaml**

Edit `kubernetes/apps/<namespace>/<app>/app/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./helmrelease.yaml
  - ../../../../templates/gatus/external  # if applicable
components:
  - ../../../../components/volsync  # ADD THIS
# REMOVE any reference to: ../../../../templates/volsync
```

**Step 2: Update ks.yaml with PUID/PGID**

Edit `kubernetes/apps/<namespace>/<app>/ks.yaml`:

```yaml
postBuild:
  substitute:
    APP: <app>
    VOLSYNC_CAPACITY: <size>Gi
    VOLSYNC_PUID: "568"    # ADD THIS
    VOLSYNC_PGID: "568"    # ADD THIS
```

**Step 3: Commit and Reconcile**

```bash
git add kubernetes/apps/<namespace>/<app>/
git commit -m "feat(<app>): migrate volsync backup to Kopia"
git push
flux reconcile source git flux-system
flux reconcile kustomization <app> -n flux-system
```

**Step 4: Verify Migration**

```bash
# Check ReplicationSource created
kubectl get replicationsource -n <namespace> <app>

# Check ExternalSecret synced
kubectl get externalsecret -n <namespace> <app>-volsync

# Watch for successful backup
kubectl describe replicationsource -n <namespace> <app>

# Verify in Kopia
kubectl exec -n storage deployment/kopia -- kopia snapshot list --all | grep <app>
```

### Complex Migration (PVC name doesn't match ${APP})

If the existing PVC has a different name (e.g., `config` instead of `radarr`):

**Step 1: Scale down and snapshot**

```bash
# Suspend flux management
flux suspend kustomization <app> -n flux-system

# Scale down the deployment
kubectl scale deploy <app> -n <namespace> --replicas=0

# Create snapshot of existing data
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: <app>-migration-snapshot
  namespace: <namespace>
spec:
  volumeSnapshotClassName: csi-ceph-block
  source:
    persistentVolumeClaimName: <old-pvc-name>
EOF

# Wait for snapshot to be ready
kubectl get volumesnapshot -n <namespace> <app>-migration-snapshot
```

**Step 2: Create new PVC with correct name**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app>
  namespace: <namespace>
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-block
  dataSource:
    name: <app>-migration-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: <size>Gi
EOF
```

**Step 3: Update HelmRelease**

Modify the HelmRelease to use the new PVC name in persistence section.

**Step 4: Resume and verify**

```bash
flux resume kustomization <app> -n flux-system
# Verify pods come up with new PVC
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<app>
```

**Step 5: Cleanup**

```bash
# Delete old PVC and snapshot after confirming everything works
kubectl delete pvc <old-pvc-name> -n <namespace>
kubectl delete volumesnapshot <app>-migration-snapshot -n <namespace>
```

---

## Apps to Migrate

### Downloads Namespace

| App | PVC Check Command | Priority |
|-----|-------------------|----------|
| qbittorrent | `kubectl get pvc -n downloads qbittorrent` | High |
| radarr | `kubectl get pvc -n downloads radarr` | High |
| radarr-uhd | `kubectl get pvc -n downloads radarr-uhd` | High |
| sonarr | `kubectl get pvc -n downloads sonarr` | High |
| sonarr-uhd | `kubectl get pvc -n downloads sonarr-uhd` | High |
| sonarr-foreign | `kubectl get pvc -n downloads sonarr-foreign` | Medium |
| prowlarr | `kubectl get pvc -n downloads prowlarr` | Medium |
| bazarr | `kubectl get pvc -n downloads bazarr` | Medium |
| readarr | `kubectl get pvc -n downloads readarr` | Medium |
| sabnzbd | `kubectl get pvc -n downloads sabnzbd` | Low |
| recyclarr | `kubectl get pvc -n downloads recyclarr` | Low |

### Entertainment Namespace

| App | PVC Check Command | Priority |
|-----|-------------------|----------|
| plex | `kubectl get pvc -n entertainment plex` | High |
| jellyfin | `kubectl get pvc -n entertainment jellyfin` | Medium |
| tautulli | `kubectl get pvc -n entertainment tautulli` | Medium |
| audiobookshelf | `kubectl get pvc -n entertainment audiobookshelf` | Medium |
| kavita | `kubectl get pvc -n entertainment kavita` | Medium |
| overseerr | `kubectl get pvc -n entertainment overseerr` | Low |

### Home Automation Namespace

| App | PVC Check Command | Priority |
|-----|-------------------|----------|
| home-assistant | `kubectl get pvc -n home-automation home-assistant` | Critical |
| zigbee2mqtt | `kubectl get pvc -n home-automation zigbee2mqtt` | High |

### Home Namespace

| App | PVC Check Command | Priority |
|-----|-------------------|----------|
| paperless | `kubectl get pvc -n home paperless` | High |
| bookstack | `kubectl get pvc -n home bookstack` | Medium |

---

## Gotchas & Troubleshooting

### Known Issues and Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| CSRF errors | Kopia logs show "invalid CSRF token" | Already fixed - `--disable-csrf-token-checks` in Kopia command |
| PVC spec immutable | Can't change storageClassName on existing PVC | Delete PVC, let volsync recreate from backup |
| No data folders on NAS | Expected `<app>/` folder missing | Normal - Kopia uses content-addressable storage. Use `kopia snapshot list` |
| NFS permission denied | Backup fails with permission errors | `chown -R 568:568` on NAS share |
| Gateway not found | Route shows "unknown backend" | Use `internal` not `envoy-internal` |
| DNS not resolving | `NZ_ERROR_UNKNOWN_HOST` | Add `internal-dns.alpha.kubernetes.io/target` annotation |
| ExternalSecret not syncing | Secret stays in "SecretSyncedError" | Check `onepassword-connect` store, verify 1Password item name |

### Kopia Commands Reference

```bash
# List all snapshots
kubectl exec -n storage deployment/kopia -- kopia snapshot list --all

# Check repository status
kubectl exec -n storage deployment/kopia -- kopia repository status

# List policies
kubectl exec -n storage deployment/kopia -- kopia policy list

# Manual garbage collection (after deleting old snapshots)
kubectl exec -n storage deployment/kopia -- kopia maintenance run --full
```

### Volsync Commands Reference

```bash
# Check backup status
kubectl describe replicationsource <app> -n <namespace>

# Trigger manual backup
kubectl patch replicationsource <app> -n <namespace> --type merge -p '{"spec":{"trigger":{"manual":"backup-'$(date +%s)'"}}}'

# Check restore status
kubectl describe replicationdestination <app>-dst -n <namespace>

# Trigger manual restore
kubectl patch replicationdestination <app>-dst -n <namespace> --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

---

## Component File Reference

### Volsync Component Location

`kubernetes/components/volsync/`

```
kubernetes/components/volsync/
├── externalsecret.yaml    # Pulls KOPIA_PASSWORD from 1Password
├── kustomization.yaml     # Component definition
├── pvc.yaml               # PVC with dataSourceRef
├── replicationdestination.yaml  # For restores
└── replicationsource.yaml       # Hourly backups to Kopia
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP` | Required | App name, used for PVC and snapshot naming |
| `VOLSYNC_CAPACITY` | Required | PVC size (e.g., `5Gi`) |
| `VOLSYNC_PUID` | `568` | User ID for backup process |
| `VOLSYNC_PGID` | `568` | Group ID for backup process |
| `VOLSYNC_RETAIN` | `7` | Number of snapshots to keep |
| `VOLSYNC_SCHEDULE` | `0 * * * *` | Cron schedule (hourly) |

---

## Quick Start for Next Session

```bash
# 1. Assess current state of target namespace
kubectl get pvc -n downloads
kubectl get replicationsource -n downloads

# 2. Pick an app and check its structure
ls -la kubernetes/apps/downloads/<app>/app/

# 3. Check if PVC name matches app name
kubectl get pvc -n downloads | grep <app>

# 4. Follow "Standard Migration" or "Complex Migration" steps above

# 5. Verify success
kubectl exec -n storage deployment/kopia -- kopia snapshot list --all | grep <app>
```

---

## Success Criteria

For each migrated app, verify:

1. ✅ ReplicationSource exists and shows successful backups
2. ✅ ExternalSecret synced (shows `SecretSynced`)
3. ✅ `kopia snapshot list` shows snapshots for the app
4. ✅ No errors in volsync mover pod logs
5. ✅ Old Restic ReplicationSource removed (if applicable)
