# Ceph Upgrade Guide: Reef → Squid

A step-by-step guide for upgrading Ceph in a Rook-managed Kubernetes cluster from Reef (v18) to Squid (v19).

---

## Prerequisites

> [!CAUTION]
> **Rook v1.18+ Required.** Squid is only supported by Rook v1.18 or later.
> Check the [Rook releases](https://github.com/rook/rook/releases) page to confirm your version.

### Before You Begin

- [ ] Rook operator is v1.18 or later
- [ ] Ceph is running Reef v18.2.x
- [ ] `require_osd_release` is set to `reef`
- [ ] Cluster health is `HEALTH_OK`
- [ ] All PGs are `active+clean`
- [ ] All OSDs are `up` and `in`

### Verify Your Starting Point

```bash
# Check Rook version - must be v1.18+
kubectl -n rook-ceph get deploy rook-ceph-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Ceph version - must be Reef
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 18.2.x (...) reef (stable)

# Check OSD release requirement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release reef

# Verify cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
# Should show: HEALTH_OK
```

---

## Understanding Squid

### What's New in Squid (v19.2.x)

Ceph Squid was released March 2025. Key features include:

- BlueStore performance improvements
- Enhanced RGW multi-site support
- CephFS snapshot improvements
- Better NVMe device handling

### Breaking Changes

| Change | Impact | Action Required |
|--------|--------|-----------------|
| RGW timestamps truncated to seconds | Object timestamps may appear to move backwards briefly | None - transient |
| CephFS `fs rename` requires offline | Only if renaming filesystems | Plan downtime if needed |
| OSD shard defaults changed (HDD only) | NVMe/SSD unaffected | None |
| iSCSI bug (Issue #68215) | Only if using iSCSI | Check release notes |

### Version Compatibility

| Component | Required Version |
|-----------|------------------|
| Rook Operator | v1.18+ |
| Ceph (current) | Reef v18.2.x |
| Ceph (target) | Squid v19.2.x |

---

## Part 1: Pre-Upgrade Backup

> [!CAUTION]
> **Do not skip backups.** These are your only recovery option if something goes wrong.

### Step 1.1: Create Backup Directory

```bash
BACKUP_DIR=~/backups/ceph/reef-to-squid-$(date +%Y%m%d)
mkdir -p $BACKUP_DIR
echo "Backups will be stored in: $BACKUP_DIR"
```

### Step 1.2: Backup Ceph State

```bash
# Cluster status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/ceph-status.txt

# OSD layout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree > $BACKUP_DIR/osd-tree.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd df tree > $BACKUP_DIR/osd-df.txt

# Pool configuration
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls detail > $BACKUP_DIR/pools.txt

# CRUSH map
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd crush dump > $BACKUP_DIR/crush-map.json

# Configuration
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump > $BACKUP_DIR/config-dump.txt

# Daemon versions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/versions.txt
```

### Step 1.3: Backup Kubernetes Resources

```bash
# CephCluster CR
kubectl -n rook-ceph get cephcluster -o yaml > $BACKUP_DIR/cephcluster.yaml

# Rook operator
kubectl -n rook-ceph get deploy rook-ceph-operator -o yaml > $BACKUP_DIR/rook-operator.yaml

# Running pods
kubectl get pods -n rook-ceph -o wide > $BACKUP_DIR/pods.txt

# PVCs using Ceph
kubectl get pvc -A | grep -E "ceph-block|ceph-filesystem" > $BACKUP_DIR/pvcs.txt
```

---

## Part 2: Upgrade Ceph to Squid

### Step 2.1: Set Safety Flags

```bash
# Prevent OSD out marking during upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout

# Prevent unnecessary data movement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance

# Verify flags are set
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should include: noout,norebalance
```

### Step 2.2: Update Ceph Image

**File:** `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

Change:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.7  # Reef
    allowUnsupported: false
```

To:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3-20250717  # Squid
    allowUnsupported: false
```

> [!NOTE]
> Check [Quay.io](https://quay.io/repository/ceph/ceph?tab=tags) for the latest v19.2.x build tag.

### Step 2.3: Deploy via GitOps

```bash
cd ~/home-ops

git add kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml
git commit -m "feat(rook-ceph): upgrade Ceph from Reef v18.2.7 to Squid v19.2.3

Breaking changes reviewed - no impact on current configuration.

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"

git push
```

### Step 2.4: Monitor the Upgrade

Rook upgrades daemons in this order: MON → MGR → OSD → MDS → RGW

```bash
# Watch pods restart
kubectl -n rook-ceph get pods -w

# In another terminal, watch Ceph status
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s'

# Check daemon versions as upgrade progresses
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
```

> [!WARNING]
> During the upgrade you may see:
> - `HEALTH_WARN` - Normal during daemon restarts
> - Brief PG degradation - Normal, will recover
>
> **Only worry if:** Status stays in `HEALTH_ERR` for more than 10 minutes.

**Expected upgrade time:** 30-60 minutes for a 3-node cluster.

### Step 2.5: Verify All Daemons Upgraded

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
```

**Expected output:**
```json
{
    "mon": {
        "ceph version 19.2.3 (...) squid (stable)": 3
    },
    "mgr": {
        "ceph version 19.2.3 (...) squid (stable)": 2
    },
    "osd": {
        "ceph version 19.2.3 (...) squid (stable)": 3
    },
    "mds": {
        "ceph version 19.2.3 (...) squid (stable)": 2
    },
    "rgw": {
        "ceph version 19.2.3 (...) squid (stable)": 2
    }
}
```

All components must show Squid. If any show Reef, wait for them to upgrade.

### Step 2.6: Finalize Squid Upgrade

> [!CAUTION]
> Once you run `require-osd-release squid`, you **cannot downgrade** to Reef.

```bash
# Check current required release
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release reef

# Set Squid requirement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release squid

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release squid
```

### Step 2.7: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should NOT include noout or norebalance
```

---

## Part 3: Post-Upgrade Validation

### Step 3.1: Health Check

```bash
# Full health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
# Should show: HEALTH_OK

# All PGs clean
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat
# Should show all active+clean

# Version confirmation
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 19.2.3 (...) squid (stable)
```

### Step 3.2: Test Storage Provisioning

```bash
# Test block storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-squid-rbd
  namespace: default
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-squid-rbd -n default
# Should show: Bound

kubectl delete pvc test-squid-rbd -n default

# Test CephFS
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-squid-cephfs
  namespace: default
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: ceph-filesystem
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-squid-cephfs -n default
# Should show: Bound

kubectl delete pvc test-squid-cephfs -n default
```

### Step 3.3: Check for Deprecation Warnings

```bash
# Look for deprecation messages in OSD logs
kubectl -n rook-ceph logs -l app=rook-ceph-osd --since=1h | grep -i deprecat

# Check config for deprecated settings
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump | grep -i deprec
```

### Step 3.4: Document Completion

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/post-squid-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/post-squid-versions.txt
```

---

## Troubleshooting

### Rook Rejects Upgrade with "Unsupported Version"

If Rook doesn't recognize Squid:

```yaml
# Temporary workaround in helmrelease.yaml
cephClusterSpec:
  cephVersion:
    allowUnsupported: true
```

After upgrade completes successfully, set back to `false`.

### OSDs Failing to Start

```bash
# Check OSD logs
kubectl -n rook-ceph logs -l ceph-osd-id=0 --tail=100

# Common causes:
# - BlueStore metadata issue
# - Permission problem
# - Configuration error
```

### PGs Stuck Degraded

```bash
# Find stuck PGs
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg dump | grep -v active+clean

# Query a specific PG
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg 1.2a query
```

### If Upgrade Fails Mid-Way

1. Restart the Rook operator:
   ```bash
   kubectl -n rook-ceph rollout restart deploy/rook-ceph-operator
   ```

2. Wait 15-20 minutes for recovery

3. Check CephCluster status:
   ```bash
   kubectl -n rook-ceph describe cephcluster
   ```

---

## Success Checklist

- [ ] All daemons show Ceph 19.2.x (Squid)
- [ ] `require_osd_release` set to `squid`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] Safety flags unset
- [ ] Block storage provisioning works
- [ ] CephFS provisioning works
- [ ] Object storage works (if used)
- [ ] No deprecation warnings in logs
- [ ] Backups retained

---

## Next Steps

After running Squid stably for 1-2 weeks:

- Monitor for any issues under normal workload
- Check for Rook v1.19+ release (required for Tentacle upgrade)
- Review the [Squid to Tentacle upgrade guide](../Ceph%20Upgrade%20-%20Squid%20to%20Tentacle/README.md) when ready

---

## Quick Reference

### Useful Commands

```bash
# Cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Daemon versions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# OSD tree
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# PG status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat

# Set/unset flags
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout

# Finalize upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release squid
```

### Version Matrix

| State | Rook Version | Ceph Version |
|-------|--------------|--------------|
| Before | v1.18.x | v18.2.7 (Reef) |
| After | v1.18.x | v19.2.3 (Squid) |

---

## Sources

- [Rook Ceph Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/ceph-upgrade/)
- [Rook Operator Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/rook-upgrade/)
- [Ceph Squid Release Notes](https://docs.ceph.com/en/latest/releases/squid/)
- [Quay.io Ceph Container Images](https://quay.io/repository/ceph/ceph?tab=tags)
- [Rook GitHub Releases](https://github.com/rook/rook/releases)

*Last updated: December 2025*

---

> [!NOTE]
> **GitOps Reminder:** All version changes should be committed to Git and deployed via Flux. Never use `kubectl apply` or `kubectl edit` for permanent changes.
