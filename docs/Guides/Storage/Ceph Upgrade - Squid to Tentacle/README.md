# Ceph Upgrade Guide: Squid → Tentacle

A step-by-step guide for upgrading Ceph in a Rook-managed Kubernetes cluster from Squid (v19) to Tentacle (v20).

---

## Prerequisites

> [!CAUTION]
> **Rook v1.19+ Required.** Tentacle is only supported by Rook v1.19 or later.
> Check the [Rook releases](https://github.com/rook/rook/releases) page to confirm v1.19 is available before proceeding.

### Before You Begin

- [ ] Rook operator is v1.19 or later
- [ ] Ceph is running Squid v19.2.x
- [ ] `require_osd_release` is set to `squid`
- [ ] Cluster health is `HEALTH_OK`
- [ ] All PGs are `active+clean`
- [ ] All OSDs are `up` and `in`
- [ ] You've completed the [Reef to Squid upgrade](../Ceph%20Upgrade%20-%20Reef%20to%20Squid/README.md) first

### Verify Your Starting Point

```bash
# Check Rook version - must be v1.19+
kubectl -n rook-ceph get deploy rook-ceph-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Ceph version - must be Squid
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 19.2.x (...) squid (stable)

# Check OSD release requirement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release squid

# Verify cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
# Should show: HEALTH_OK
```

---

## Understanding Tentacle

### What's New in Tentacle (v20.2.x)

Ceph Tentacle was released November 18, 2025. Key features include:

- NVMe-oF target support (experimental)
- Performance improvements for BlueStore
- Enhanced RGW functionality
- Improved CephFS stability

### Breaking Changes

| Change | Impact | Action Required |
|--------|--------|-----------------|
| RGW tenant-level IAM deprecated | If using S3 with IAM policies | Review User Account migration |
| `restful` mgr module removed | Only if you used REST API | None - use dashboard API instead |
| `zabbix` mgr module removed | Only if you used Zabbix integration | Configure external monitoring |
| Erasure coding default changed to ISA-L | Only affects **new** pools | None - existing pools unchanged |
| `osd_repair_during_recovery` option removed | Only if explicitly set | Remove from config if present |
| CephFS `max_mds` requires confirmation when unhealthy | Safety improvement | None - normal operation |

### Version Compatibility

| Component | Required Version |
|-----------|------------------|
| Rook Operator | v1.19+ |
| Ceph (current) | Squid v19.2.x |
| Ceph (target) | Tentacle v20.2.x |

---

## Part 1: Pre-Upgrade Backup

> [!CAUTION]
> **Do not skip backups.** These are your only recovery option if something goes wrong.

### Step 1.1: Create Backup Directory

```bash
BACKUP_DIR=~/backups/ceph/squid-to-tentacle-$(date +%Y%m%d)
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

## Part 2: Upgrade Rook to v1.19+ (if needed)

> [!IMPORTANT]
> Skip this section if you're already on Rook v1.19+.

### Step 2.1: Update Rook Operator

**File:** `kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml`

Update the tag to v1.19.x (check [releases](https://github.com/rook/rook/releases) for latest):

```yaml
spec:
  ref:
    tag: v1.19.0  # Update to latest v1.19.x
```

### Step 2.2: Update Helm Chart

**File:** `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

```yaml
spec:
  chart:
    spec:
      version: v1.19.0  # Match operator version
```

### Step 2.3: Deploy Rook Update

```bash
git add kubernetes/apps/rook-ceph/
git commit -m "feat(rook-ceph): upgrade Rook operator to v1.19.x

Required for Ceph Tentacle support.

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"

git push
```

### Step 2.4: Verify Rook Upgrade

```bash
# Wait for operator to restart
kubectl -n rook-ceph rollout status deploy/rook-ceph-operator

# Verify version
kubectl -n rook-ceph get deploy rook-ceph-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# Verify cluster health after Rook upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```

---

## Part 3: Upgrade Ceph to Tentacle

### Step 3.1: Set Safety Flags

```bash
# Prevent OSD out marking during upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout

# Prevent unnecessary data movement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance

# Verify flags are set
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should include: noout,norebalance
```

### Step 3.2: Update Ceph Image

**File:** `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

Change:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3-20250717  # Squid
    allowUnsupported: false
```

To:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v20.2.0-20251104  # Tentacle
    allowUnsupported: false
```

> [!NOTE]
> Check [Quay.io](https://quay.io/repository/ceph/ceph?tab=tags) for the latest v20.2.x build tag.

### Step 3.3: Deploy via GitOps

```bash
cd ~/home-ops

git add kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml
git commit -m "feat(rook-ceph): upgrade Ceph from Squid v19.2.3 to Tentacle v20.2.0

Breaking changes reviewed:
- restful/zabbix modules removed (not used)
- IAM tenant deprecation (not using tenant IAM)
- EC default changed (existing pools unaffected)

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"

git push
```

### Step 3.4: Monitor the Upgrade

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

### Step 3.5: Verify All Daemons Upgraded

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
```

**Expected output:**
```json
{
    "mon": {
        "ceph version 20.2.0 (...) tentacle (stable)": 3
    },
    "mgr": {
        "ceph version 20.2.0 (...) tentacle (stable)": 2
    },
    "osd": {
        "ceph version 20.2.0 (...) tentacle (stable)": 3
    },
    "mds": {
        "ceph version 20.2.0 (...) tentacle (stable)": 2
    },
    "rgw": {
        "ceph version 20.2.0 (...) tentacle (stable)": 2
    }
}
```

All components must show Tentacle. If any show Squid, wait for them to upgrade.

### Step 3.6: Finalize Tentacle Upgrade

> [!CAUTION]
> Once you run `require-osd-release tentacle`, you **cannot downgrade** to Squid.

```bash
# Check current required release
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release squid

# Set Tentacle requirement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release tentacle

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release tentacle
```

### Step 3.7: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should NOT include noout or norebalance
```

---

## Part 4: Post-Upgrade Validation

### Step 4.1: Health Check

```bash
# Full health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
# Should show: HEALTH_OK

# All PGs clean
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat
# Should show all active+clean

# Version confirmation
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 20.2.0 (...) tentacle (stable)
```

### Step 4.2: Test Storage Provisioning

```bash
# Test block storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-tentacle-rbd
  namespace: default
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-tentacle-rbd -n default
# Should show: Bound

kubectl delete pvc test-tentacle-rbd -n default

# Test CephFS
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-tentacle-cephfs
  namespace: default
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: ceph-filesystem
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-tentacle-cephfs -n default
# Should show: Bound

kubectl delete pvc test-tentacle-cephfs -n default
```

### Step 4.3: Check for Deprecation Warnings

```bash
# Look for deprecation messages in OSD logs
kubectl -n rook-ceph logs -l app=rook-ceph-osd --since=1h | grep -i deprecat

# Check config for deprecated settings
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump | grep -i deprec
```

### Step 4.4: Document Completion

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/post-tentacle-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/post-tentacle-versions.txt
```

---

## Troubleshooting

### Rook Rejects Upgrade with "Unsupported Version"

If Rook doesn't recognize Tentacle:

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

- [ ] All daemons show Ceph 20.2.x (Tentacle)
- [ ] `require_osd_release` set to `tentacle`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] Safety flags unset
- [ ] Block storage provisioning works
- [ ] CephFS provisioning works
- [ ] Object storage works (if used)
- [ ] No deprecation warnings in logs
- [ ] Backups retained

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
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release tentacle
```

### Version Matrix

| State | Rook Version | Ceph Version |
|-------|--------------|--------------|
| Before | v1.18.x | v19.2.3 (Squid) |
| After | v1.19+ | v20.2.0 (Tentacle) |

---

## Sources

- [Rook Ceph Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/ceph-upgrade/)
- [Rook Operator Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/rook-upgrade/)
- [Ceph Tentacle Release Notes](https://docs.ceph.com/en/latest/releases/tentacle/)
- [Quay.io Ceph Container Images](https://quay.io/repository/ceph/ceph?tab=tags)
- [Rook GitHub Releases](https://github.com/rook/rook/releases)
- [Rook Roadmap](https://github.com/rook/rook/blob/master/ROADMAP.md)

*Last updated: December 2025*

---

> [!NOTE]
> **GitOps Reminder:** All version changes should be committed to Git and deployed via Flux. Never use `kubectl apply` or `kubectl edit` for permanent changes.
