# immich18 - CloudNativePG Cluster with pgBackRest

PostgreSQL 18 cluster for Immich with dual-destination backups to Backblaze B2 and Cloudflare R2.

## Architecture

```
immich18 (3 replicas)
    │
    └── pgbackrest plugin
            │
            ├── Repo 1: Backblaze B2 (primary)
            │   └── WAL archives + full backups
            │
            └── Repo 2: Cloudflare R2 (secondary)
                └── WAL archives + full backups
```

## Backup Configuration

- **WAL archiving**: Async to BOTH repositories simultaneously
- **Full backups**: Two ScheduledBackups, one per repository
- **Retention**: 14 full backups, 30 diff backups, 7 days WAL per repo

## Restore Procedure

CloudNativePG doesn't support in-place restore. You bootstrap a **new cluster** from backup.

### Option 1: Restore to Same Cluster Name (Replace)

1. **Scale down immich** to prevent database connections:
   ```bash
   kubectl scale deploy -n default immich-server immich-machine-learning --replicas=0
   ```

2. **Delete the existing cluster**:
   ```bash
   kubectl delete cluster immich18 -n database
   ```

3. **Edit immich18.yaml** - Comment out `initdb`, uncomment `recovery`:
   ```yaml
   bootstrap:
     recovery:
       source: pgbackrest-backup

   externalClusters:
     - name: pgbackrest-backup
       plugin:
         name: pgbackrest.dalibo.com
         parameters:
           repositoryRef: immich18-repository
   ```

4. **Apply and wait**:
   ```bash
   flux reconcile kustomization cloudnative-pg-immich18 -n database --force
   kubectl get cluster immich18 -n database -w
   ```

5. **After restore completes**, revert immich18.yaml to `initdb` (for future fresh deployments) and scale immich back up.

### Option 2: Restore to New Cluster Name (Side-by-side)

1. Create a new cluster manifest with different name (e.g., `immich18-restored`)
2. Use `recovery` bootstrap pointing to the same repository
3. Validate data, then switch immich to the new cluster
4. Delete old cluster when confirmed

### Point-in-Time Recovery (PITR)

Add `recoveryTarget` to restore to a specific moment:

```yaml
bootstrap:
  recovery:
    source: pgbackrest-backup
    recoveryTarget:
      targetTime: "2025-01-15 10:30:00"  # ISO 8601 format
```

Other target options:
- `targetLSN`: Restore to specific LSN
- `targetXID`: Restore to specific transaction ID
- `targetImmediate`: Stop as soon as consistent state reached

### Restore from Specific Repository

By default, restores from repo 1 (B2). To restore from R2:

```yaml
externalClusters:
  - name: pgbackrest-backup
    plugin:
      name: pgbackrest.dalibo.com
      parameters:
        repositoryRef: immich18-repository
        selectedRepository: "2"  # 1=B2, 2=R2
```

## Verify Backups

```bash
# Check backup status
kubectl get backups -n database

# Check scheduled backups
kubectl get scheduledbackups -n database

# View pgbackrest info from sidecar
kubectl exec -n database immich18-1 -c plugin-pgbackrest -- pgbackrest info
```

## Files

| File | Purpose |
|------|---------|
| `immich18.yaml` | Cluster definition with restore template |
| `repository.yaml` | pgBackRest dual-repo config (B2 + R2) |
| `scheduledbackup.yaml` | Two scheduled backups (one per repo) |
| `externalsecret.yaml` | Credentials from 1Password |
| `externalsecret-flux.yaml` | Flux substitution variables |
| `kustomization.yaml` | Kustomize resources list |
