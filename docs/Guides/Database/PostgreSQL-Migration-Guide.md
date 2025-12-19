# PostgreSQL Migration Guide

Two approaches for migrating PostgreSQL clusters in CloudNativePG.

## Approach 1: pg_dump Direct Pipe (Established Clusters)

Use when the target cluster already exists and you need to migrate data.

### Prerequisites

- Source cluster running and accessible
- Target cluster running with pgBackRest configured
- All apps using the database scaled down

### Steps

**1. Scale down all apps**

```bash
kubectl scale deploy -n <namespace> <app1> <app2> ... --replicas=0
```

**2. Verify no active connections**

```bash
kubectl exec -n database <source-cluster>-1 -c postgres -- psql -U postgres -c \
  "SELECT datname, usename, client_addr, state FROM pg_stat_activity WHERE datname IS NOT NULL;"
```

**3. Migrate via direct pipe**

```bash
kubectl exec -n database <source-cluster>-1 -c postgres -- pg_dumpall -U postgres | \
  kubectl exec -i -n database <target-cluster>-1 -c postgres -- psql -U postgres
```

Expected errors (safe to ignore):
```
ERROR:  role "postgres" already exists
ERROR:  role "streaming_replica" already exists
```

**4. Verify migration**

```bash
# Compare database counts
kubectl exec -n database <source-cluster>-1 -c postgres -- psql -U postgres -c \
  "SELECT COUNT(*) FROM pg_database WHERE datname NOT IN ('template0', 'template1');"

kubectl exec -n database <target-cluster>-1 -c postgres -- psql -U postgres -c \
  "SELECT COUNT(*) FROM pg_database WHERE datname NOT IN ('template0', 'template1');"

# Spot check critical tables
kubectl exec -n database <target-cluster>-1 -c postgres -- psql -U postgres -d <database> -c \
  "SELECT COUNT(*) FROM <table>;"
```

**5. Update app ExternalSecrets**

Change hostname from `<source>-rw.database.svc.cluster.local` to `<target>-rw.database.svc.cluster.local`:

```bash
find kubernetes/apps -name "*.yaml" -exec grep -l "<source>-rw" {} \; | \
  xargs sed -i 's/<source>-rw\.database\.svc\.cluster\.local/<target>-rw.database.svc.cluster.local/g'
```

**6. Commit, push, and scale apps back up**

```bash
git add -A && git commit -m "refactor: migrate apps to <target>"
git push
kubectl scale deploy -n <namespace> <app1> <app2> ... --replicas=1
```

**7. Cleanup old cluster**

```bash
flux suspend kustomization <source-kustomization> -n database
kubectl delete cluster <source-cluster> -n database
rm -rf kubernetes/apps/database/cloudnative-pg/<source-cluster>/
# Edit ks.yaml to remove the Kustomization
git add -A && git commit -m "chore: remove <source-cluster>"
git push
```

---

## Approach 2: Live Import (New Cluster Bootstrap)

Use when creating a new cluster and importing from an existing one. Performs logical replication - no downtime for read operations.

### Prerequisites

- Source cluster running and accessible
- Target cluster does NOT exist yet (will be created with import bootstrap)

### Steps

**1. Create target cluster with import bootstrap**

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <target-cluster>
  namespace: database
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18
  storage:
    size: 20Gi
    storageClass: openebs-hostpath

  bootstrap:
    initdb:
      import:
        type: monolith
        databases: ["*"]
        roles: ["*"]
        source:
          externalCluster: <source-cluster>

  externalClusters:
    - name: <source-cluster>
      connectionParameters:
        host: <source-cluster>-rw.database.svc.cluster.local
        user: postgres
        dbname: postgres
      password:
        name: <secret-name>
        key: password
```

**2. Apply and wait for import**

```bash
kubectl apply -f <target-cluster>.yaml
kubectl get pods -n database -w
```

Watch for:
- `<target>-1-import-*` pod (performs the import)
- `<target>-1` pod (primary starts after import)
- `<target>-2`, `<target>-3` (replicas join)

**3. Verify import completed**

```bash
kubectl get cluster <target-cluster> -n database
# STATUS should be "Cluster in healthy state"
```

**4. Update bootstrap for future recovery**

After successful import, update the cluster spec to use standard recovery:

```yaml
spec:
  bootstrap:
    recovery:
      source: &previousCluster <target-cluster>-v1

  externalClusters:
    - name: *previousCluster
      barmanObjectStore:
        # ... your backup config
```

**5. Update apps and cleanup**

Same as Approach 1, steps 5-7.

---

## When to Use Which

| Scenario | Approach |
|----------|----------|
| Target cluster already exists | Approach 1 (pg_dump) |
| Fresh migration to new cluster | Approach 2 (Live Import) |
| Major version upgrade | Either (both work) |
| Minimal downtime required | Approach 2 (read-only during import) |
| Simple, predictable process | Approach 1 (pg_dump) |

## Tips

- **Always verify data** after migration before scaling apps back up
- **Keep source cluster** for a few days after migration as fallback
- **Trigger a backup** on the new cluster immediately after migration
- **Monitor logs** for database connection errors after scaling apps up
- **Restart apps** if they cached the old secret values (ExternalSecret refresh may not trigger pod restart)
