# Ceph Upgrade Guide: Reef → Squid → Tentacle

A comprehensive step-by-step guide for upgrading Ceph in a Rook-managed Kubernetes cluster from Reef (v18) through Squid (v19) to Tentacle (v20).

---

## What You'll Learn

By the end of this guide, you will understand:

- ✅ Why Ceph upgrades must follow a specific path
- ✅ How to safely back up your Ceph cluster state
- ✅ The step-by-step process for each upgrade phase
- ✅ What breaking changes to watch for
- ✅ How to verify a successful upgrade
- ✅ What to do if something goes wrong

---

## Understanding Ceph Upgrades

### Why This Matters

Ceph is your cluster's storage brain. It manages all persistent data for your applications - databases, media files, backups, everything. A botched upgrade could mean **data loss**.

The good news: Rook makes Ceph upgrades safer by handling the rolling update process automatically. But you still need to understand what's happening.

### The Upgrade Path

Ceph versions follow a specific upgrade path. You **cannot skip versions**:

```
Reef (v18.2.x) → Squid (v19.2.x) → Tentacle (v20.2.x)
```

> [!IMPORTANT]
> **No Downgrade Path.** Once you upgrade Ceph, you cannot go back to an older version. The only recovery option is restoring from backups (which means data loss for anything created after the backup).

### Version Naming

Ceph releases are named alphabetically after sea creatures:

| Release | Version | Status | End of Life |
|---------|---------|--------|-------------|
| **Reef** | v18.2.x | Current (your cluster) | August 2025 |
| **Squid** | v19.2.x | Stable | September 2026 |
| **Tentacle** | v20.2.x | Latest | ~2027 |

### Two-Part Upgrade: Rook + Ceph

Every upgrade has two components:
1. **Rook Operator** - The Kubernetes controller that manages Ceph
2. **Ceph Daemons** - The actual storage software (MON, OSD, MGR, MDS, RGW)

> [!TIP]
> Always upgrade Rook first, then Ceph. Newer Rook versions have better support for newer Ceph versions.

---

## Your Current Configuration

Based on your repository, here's your current state:

| Component | Current Version | File Location |
|-----------|-----------------|---------------|
| Rook Operator | v1.18.8 | `kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml` |
| Rook Cluster Chart | v1.18.6 | `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml` |
| Ceph | v18.2.7 (Reef) | `cephClusterSpec.cephVersion.image` |
| Nodes | stanton-01, stanton-02, stanton-03 | Control plane nodes |
| OSDs | 3 (one per node) | Samsung NVMe 1.9TB each |
| Storage Types | Block (RBD), Filesystem (CephFS), Object (RGW) | All enabled |

### Your Custom Configuration

```yaml
configOverride: |
  [global]
  bdev_enable_discard = true        # SSD TRIM support
  bdev_async_discard = true         # Async TRIM for performance
  osd_class_update_on_start = false # Prevents automatic CRUSH updates
  bluestore_min_alloc_size = 4096   # 4K allocation for NVMe
  # ... other NVMe optimizations
```

> [!NOTE]
> Your configuration is compatible with both Squid and Tentacle. The `osd_class_update_on_start` setting may show deprecation warnings in future versions - monitor logs after upgrade.

---

## Prerequisites

### Pre-Flight Checklist

Before starting ANY upgrade, verify all of these:

- [ ] Cluster health is `HEALTH_OK` (not HEALTH_WARN or HEALTH_ERR)
- [ ] All PGs (Placement Groups) are `active+clean`
- [ ] All OSDs are `up` and `in`
- [ ] No ongoing recovery or rebalancing operations
- [ ] All backups completed successfully
- [ ] You have 2-3 hours of uninterrupted time
- [ ] You understand that upgrades cannot be reversed

### Tools You'll Need

```bash
# Access to your cluster
export KUBECONFIG=~/home-ops/kubeconfig

# Quick alias for Ceph commands (optional but helpful)
alias ceph="kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph"
```

---

## Part 1: Pre-Upgrade Backup

> [!CAUTION]
> **Do not skip this section.** These backups are your only recovery option if something goes catastrophically wrong.

### Step 1.1: Create Backup Directory

```bash
# Create dated backup directory
BACKUP_DIR=~/backups/ceph/migration-$(date +%Y%m%d)
mkdir -p $BACKUP_DIR
echo "Backups will be stored in: $BACKUP_DIR"
```

### Step 1.2: Backup Ceph State

```bash
# Cluster status snapshot
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/ceph-status.txt

# OSD layout (critical for recovery)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree > $BACKUP_DIR/osd-tree.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd df tree > $BACKUP_DIR/osd-df.txt

# Pool configuration
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls detail > $BACKUP_DIR/pools.txt

# CRUSH map (storage topology)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd crush dump > $BACKUP_DIR/crush-map.json

# Configuration dump
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump > $BACKUP_DIR/config-dump.txt

# All daemon versions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/versions.txt
```

### Step 1.3: Backup Kubernetes Resources

```bash
# CephCluster CR
kubectl -n rook-ceph get cephcluster -o yaml > $BACKUP_DIR/cephcluster.yaml

# All Ceph CRDs
for crd in $(kubectl get crd | grep ceph.rook.io | awk '{print $1}'); do
  kubectl get $crd -A -o yaml > $BACKUP_DIR/crd-$crd.yaml
done

# Rook operator
kubectl -n rook-ceph get deploy rook-ceph-operator -o yaml > $BACKUP_DIR/rook-operator.yaml

# Running pods
kubectl get pods -n rook-ceph -o wide > $BACKUP_DIR/pods.txt

# All PVCs using Ceph
kubectl get pvc -A | grep -E "ceph-block|ceph-filesystem" > $BACKUP_DIR/pvcs.txt
```

### Step 1.4: Backup Git Configuration

```bash
# Copy your Flux manifests
cp -r ~/home-ops/kubernetes/apps/rook-ceph $BACKUP_DIR/flux-manifests/
```

**Checkpoint:** Verify your backup directory has all the files:

```bash
ls -la $BACKUP_DIR
# Should see: ceph-status.txt, osd-tree.txt, cephcluster.yaml, etc.
```

---

## Part 2: Health Verification

### Step 2.1: Check Cluster Health

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```

**Expected output:**
```
HEALTH_OK
```

> [!WARNING]
> If you see `HEALTH_WARN` or `HEALTH_ERR`, **stop here**. Resolve the issues before upgrading. Common issues:
> - `too few PGs per OSD` - Usually safe to proceed, but investigate
> - `OSDs are down` - Fix before proceeding
> - `PGs degraded` - Wait for recovery to complete

### Step 2.2: Verify All PGs Are Clean

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat
```

**Expected output:**
```
169 pgs: 169 active+clean
```

All PGs must show `active+clean`. Any other state (degraded, recovering, undersized) means **wait** for recovery to complete.

### Step 2.3: Check OSD Status

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
```

**Expected:** All OSDs should show `up` in the status column. Example:
```
ID  CLASS  WEIGHT   TYPE NAME           STATUS  REWEIGHT
-1         5.46    root default
-3         1.82        host stanton-01
 0   nvme  1.82            osd.0          up     1.00000
...
```

### Step 2.4: Confirm No Active Operations

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
```

Look for the `io:` section. There should be **no ongoing recovery**:
- No "recovering" messages
- No "backfilling" messages
- No "degraded" objects

**Checkpoint:** All health checks pass before proceeding.

---

## Part 3: Phase 1 - Reef to Squid

This phase upgrades Ceph from v18.2.7 (Reef) to v19.2.3 (Squid).

### Understanding Squid Breaking Changes

Before upgrading, understand what's changing:

| Change | Impact on Your Cluster |
|--------|----------------------|
| RGW timestamps truncated to seconds | Object storage timestamps may appear to move backwards briefly. No action needed. |
| CephFS `fs rename` requires offline | You're not renaming filesystems, so no impact. |
| OSD shard defaults changed (HDD only) | No impact - you're using NVMe SSDs. |
| iSCSI bug (Issue #68215) | You don't use iSCSI - no impact. |

> [!NOTE]
> Your configuration is fully compatible with Squid. No changes needed to your `configOverride`.

### Step 3.1: Set Safety Flags

These flags prevent OSDs from being marked "out" during the rolling restart:

```bash
# Prevent OSD out marking during upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout

# Prevent unnecessary data movement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance

# Verify flags are set
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should include: noout,norebalance
```

> [!TIP]
> These flags are critical. Without them, Ceph might start moving data around when daemons restart, which slows down the upgrade and adds risk.

### Step 3.2: Update Rook Cluster Chart (if needed)

Check if a newer chart version is available that better supports Squid:

```bash
# Check current cluster chart version
grep "version:" ~/home-ops/kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml
```

If you're on v1.18.6 and a newer v1.18.x is available, update it first.

### Step 3.3: Update Ceph Image to Squid

Edit your cluster HelmRelease:

**File:** `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

Find and change:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.7  # OLD
```

To:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3  # NEW - Squid
    allowUnsupported: false  # Keep false - Squid is supported
```

### Step 3.4: Commit and Deploy via GitOps

```bash
cd ~/home-ops

# Stage the change
git add kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml

# Commit with clear message
git commit -m "feat(rook-ceph): upgrade Ceph from Reef v18.2.7 to Squid v19.2.3

Breaking changes reviewed - no impact on current configuration.
Safety flags set before upgrade.

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"

# Push to trigger Flux reconciliation
git push
```

### Step 3.5: Monitor the Upgrade

Rook upgrades daemons in this order:
1. **MON** (monitors) - maintains cluster state
2. **MGR** (managers) - handles metrics and modules
3. **OSD** (object storage daemons) - actual data storage
4. **MDS** (metadata server) - CephFS metadata
5. **RGW** (RADOS gateway) - S3-compatible object storage

Watch the upgrade progress:

```bash
# Watch pods restart one by one
kubectl -n rook-ceph get pods -w

# In another terminal, watch Ceph status
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s'

# Check daemon versions (run periodically)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
```

> [!WARNING]
> During the upgrade you may see:
> - `HEALTH_WARN` - Normal during daemon restarts
> - Brief PG degradation - Normal, will recover
> - "1 mgr modules have recently crashed" - Usually transient
>
> **Only worry if:** Status stays in `HEALTH_ERR` for more than 10 minutes, or OSDs fail to start.

**Expected upgrade time:** 30-60 minutes for a 3-node cluster.

### Step 3.6: Verify Squid Upgrade Complete

```bash
# All daemons should report Squid
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
    ...
}
```

All components must show the Squid version. If any show Reef, wait for them to upgrade.

### Step 3.7: Finalize Squid Upgrade

This step tells Ceph that all OSDs are now Squid-capable, enabling Squid-specific features:

```bash
# Check current required release
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Will show: require_osd_release reef

# Upgrade the requirement
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release squid

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release squid
```

> [!CAUTION]
> Once you run `require-osd-release squid`, you **cannot downgrade** to Reef. Only run this after verifying all daemons are on Squid.

### Step 3.8: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep flags
# Should NOT include noout or norebalance
```

### Step 3.9: Post-Squid Health Check

```bash
# Full health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
# Should be: HEALTH_OK

# All PGs clean
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat
# Should show all active+clean

# Test storage provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-squid-pvc
  namespace: default
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

# Wait a moment, then verify
kubectl get pvc test-squid-pvc -n default
# Should show: Bound

# Cleanup
kubectl delete pvc test-squid-pvc -n default
```

### Step 3.10: Document Squid Completion

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/post-squid-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/post-squid-versions.txt
```

**Checkpoint:** Phase 1 complete. Your cluster is now running Ceph Squid v19.2.3.

---

## Part 4: Stabilization Period

> [!IMPORTANT]
> **Wait at least 1-2 weeks** between Squid and Tentacle upgrades. This gives you time to:
> - Catch any subtle issues that only appear under load
> - Monitor logs for deprecation warnings
> - Verify all applications work correctly

### What to Monitor During Stabilization

```bash
# Check health daily
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Watch for deprecation warnings
kubectl -n rook-ceph logs -l app=rook-ceph-osd --since=24h | grep -i deprecat

# Check for crash reports
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph crash ls
```

### Signs You're Ready for Phase 2

- [ ] Cluster has been stable for 1+ weeks
- [ ] No unexpected health warnings
- [ ] All applications function correctly
- [ ] No crash reports related to the upgrade
- [ ] You've reviewed Tentacle release notes (below)

---

## Part 5: Phase 2 - Squid to Tentacle

This phase upgrades from Squid (v19.2.3) to Tentacle (v20.2.0).

> [!WARNING]
> **Tentacle was released November 18, 2025.** As a new major release, consider waiting for community feedback and patch releases (v20.2.1, v20.2.2) before upgrading production clusters.

### Understanding Tentacle Breaking Changes

| Change | Impact on Your Cluster | Action Required |
|--------|----------------------|-----------------|
| RGW tenant-level IAM deprecated | If using S3 with IAM policies | Review User Account migration |
| `restful` and `zabbix` mgr modules removed | Only if you used these modules | None - you don't use them |
| Erasure coding default changed to ISA-L | Only affects **new** pools | None - existing pools unchanged |
| `osd_repair_during_recovery` removed | Only if you explicitly set this | None - not in your config |
| CephFS `max_mds` requires confirmation when unhealthy | Safety improvement | None - normal operation |

### Step 5.1: Pre-Tentacle Verification

```bash
# Verify Squid is healthy and finalized
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Must show: require_osd_release squid

# Fresh backup before Tentacle
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/pre-tentacle-status.txt
kubectl -n rook-ceph get cephcluster -o yaml > $BACKUP_DIR/pre-tentacle-cephcluster.yaml
```

### Step 5.2: Set Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance
```

### Step 5.3: Check Rook Tentacle Support

Verify your Rook version supports Tentacle:

```bash
# Current Rook version
kubectl -n rook-ceph get deploy rook-ceph-operator -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Rook v1.18.x supports Tentacle. If you need to upgrade Rook first, update the OCIRepository:

**File:** `kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml`

Check [Rook releases](https://github.com/rook/rook/releases) for the latest v1.18.x or v1.19.x version.

### Step 5.4: Update Ceph Image to Tentacle

**File:** `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

Change:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3  # Squid
    allowUnsupported: false
```

To:
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v20.2.0  # Tentacle
    allowUnsupported: false  # Try false first; Rook v1.18+ should support Tentacle
```

> [!NOTE]
> If Rook rejects the upgrade with "unsupported version", temporarily set `allowUnsupported: true`. This overrides Rook's version check.

### Step 5.5: Deploy via GitOps

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

### Step 5.6: Monitor the Upgrade

```bash
# Watch pods
kubectl -n rook-ceph get pods -w

# Watch Ceph status
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s'

# Check versions as upgrade progresses
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
```

### Step 5.7: Finalize Tentacle Upgrade

After all daemons show Tentacle:

```bash
# Verify all daemons upgraded
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions
# All should show: ceph version 20.2.0 (...) tentacle (stable)

# Set required OSD release
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release tentacle

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release tentacle
```

### Step 5.8: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance
```

### Step 5.9: Post-Tentacle Validation

```bash
# Health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Version confirmation
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 20.2.0 (...) tentacle (stable)

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
kubectl delete pvc test-tentacle-cephfs -n default
```

### Step 5.10: Document Tentacle Completion

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > $BACKUP_DIR/post-tentacle-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > $BACKUP_DIR/post-tentacle-versions.txt
```

**Checkpoint:** Phase 2 complete. Your cluster is now running Ceph Tentacle v20.2.0.

---

## Part 6: Post-Upgrade Tasks

### Check for Deprecation Warnings

```bash
# Look for deprecation messages in OSD logs
kubectl -n rook-ceph logs -l app=rook-ceph-osd --since=1h | grep -i deprecat

# Check your configOverride settings
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump | grep -i deprec
```

If `osd_class_update_on_start` shows deprecation warnings, consider removing it from your configOverride.

### Performance Baseline

Run a quick benchmark to establish your new baseline:

```bash
# Write test
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  rados bench -p ceph-blockpool 30 write --no-cleanup

# Sequential read
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  rados bench -p ceph-blockpool 30 seq

# Random read
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  rados bench -p ceph-blockpool 30 rand

# Cleanup benchmark objects
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  rados cleanup -p ceph-blockpool
```

### Update Toolbox Image

The Ceph toolbox isn't automatically upgraded. Update it to match:

```bash
# Check current toolbox image
kubectl -n rook-ceph get deploy rook-ceph-tools -o jsonpath='{.spec.template.spec.containers[0].image}'

# If it's still on an old version, Rook should have updated it
# If not, you may need to restart the toolbox
kubectl -n rook-ceph rollout restart deploy/rook-ceph-tools
```

---

## Troubleshooting

### Upgrade Stuck on MON/MGR

**Symptoms:** MON or MGR pods keep restarting

```bash
# Check MON logs
kubectl -n rook-ceph logs -l app=rook-ceph-mon --tail=100

# Check quorum status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mon stat

# If a MON is stuck, the operator will eventually handle it
# Give it 10-15 minutes before manual intervention
```

### OSDs Failing to Start

**Symptoms:** OSD pods in CrashLoopBackOff

```bash
# Check OSD logs for the failing OSD
kubectl -n rook-ceph logs -l ceph-osd-id=0 --tail=100

# Common causes:
# - BlueStore metadata issue: may need fsck
# - Permission problem: check device ownership
# - Configuration error: review configOverride
```

### PGs Stuck Degraded

**Symptoms:** PGs not recovering after upgrade

```bash
# Find stuck PGs
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg dump | grep -v active+clean

# Query a specific stuck PG
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg 1.2a query

# Usually just needs time - if stuck for >30 min, investigate further
```

### "allowUnsupported must be true" Error

**Symptoms:** Operator refuses to upgrade

```bash
# Temporary workaround - set allowUnsupported
# Edit: kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml

cephClusterSpec:
  cephVersion:
    allowUnsupported: true  # Set temporarily
```

After upgrade completes and is verified stable, set back to `false`.

---

## Emergency Recovery

> [!CAUTION]
> These are last-resort options. They may result in data loss.

### If Upgrade Fails Mid-Way

1. **First try:** Restart the Rook operator
   ```bash
   kubectl -n rook-ceph rollout restart deploy/rook-ceph-operator
   ```

2. **Wait and observe:** Give Rook 15-20 minutes to recover

3. **Check CephCluster status:**
   ```bash
   kubectl -n rook-ceph describe cephcluster
   ```

### If Cluster is Unrecoverable

1. **Contact community:**
   - Rook Slack: https://slack.rook.io
   - Ceph Users: ceph-users@ceph.io

2. **Last resort - restore from backup:**
   - This requires cluster recreation
   - You will lose data created after your backup
   - Only do this if all other options exhausted

---

## Success Checklist

### After Phase 1 (Squid)

- [ ] All daemons show Ceph 19.2.3
- [ ] `require_osd_release` set to `squid`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] Safety flags unset
- [ ] Storage provisioning works

### After Phase 2 (Tentacle)

- [ ] All daemons show Ceph 20.2.0
- [ ] `require_osd_release` set to `tentacle`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] Safety flags unset
- [ ] Block storage works
- [ ] CephFS works (if used)
- [ ] Object storage works (if used)

### Final Documentation

- [ ] Backups retained for 30 days minimum
- [ ] Performance baseline documented
- [ ] Any issues and resolutions documented
- [ ] HelmRelease in git reflects final state

---

## Quick Reference

### Useful Commands

```bash
# Cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# All daemon versions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# OSD tree
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# PG status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat

# Set/unset flags
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout

# Finalize upgrade
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release <version>

# Force Flux reconciliation
flux reconcile kustomization cluster-apps-rook-ceph-cluster -n flux-system --with-source
```

### File Locations

| File | Purpose |
|------|---------|
| `kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml` | Rook operator version |
| `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml` | Ceph version and cluster config |

### Version Matrix

| Upgrade | Rook Version | Ceph Version |
|---------|--------------|--------------|
| Starting point | v1.18.8 | v18.2.7 (Reef) |
| After Phase 1 | v1.18.8+ | v19.2.3 (Squid) |
| After Phase 2 | v1.18.8+ | v20.2.0 (Tentacle) |

---

## Sources

This guide was compiled from official documentation:

- [Rook Ceph Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/ceph-upgrade/)
- [Rook Operator Upgrade Guide](https://rook.io/docs/rook/latest-release/Upgrade/rook-upgrade/)
- [Ceph Squid Release Notes](https://docs.ceph.com/en/latest/releases/squid/)
- [Ceph Tentacle Release Notes](https://docs.ceph.com/en/latest/releases/tentacle/)
- [Ceph v19.2.0 Announcement](https://ceph.io/en/news/blog/2024/v19-2-0-squid-released/)
- [Ceph v20.2.0 Announcement](https://ceph.io/en/news/blog/2025/v20-2-0-tentacle-released/)
- [Rook GitHub Releases](https://github.com/rook/rook/releases)
- [Proxmox Reef to Squid Guide](https://pve.proxmox.com/wiki/Ceph_Reef_to_Squid)

---

> [!NOTE]
> **GitOps Reminder:** All version changes should be committed to Git and deployed via Flux. Never use `kubectl apply` or `kubectl edit` for permanent changes.
