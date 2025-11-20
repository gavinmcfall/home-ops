# Ceph Migration Guide: Reef (18.x) → Squid (19.x) → Tentacle (20.x)

## Current State (Baseline)

**Documented on:** 2025-11-20

### Cluster Information
- **Rook Operator Version:** v1.18.7 (`ghcr.io/rook/ceph:v1.18.7`)
- **Ceph Version:** v18.2.7 Reef (stable)
- **Cluster ID:** `3b3d504b-96b4-4102-9ce3-c91b6bc2948d`
- **Cluster Health:** `HEALTH_OK` ✅
- **Namespace:** `rook-ceph`

### Infrastructure
- **3 Control Plane Nodes:** stanton-01, stanton-02, stanton-03
- **OSD Configuration:** 3 OSDs (1 per node)
- **Storage Devices:** Samsung MZQL21T9HCJR-00A07 NVMe (1.9TB each)
  - stanton-01: `nvme-SAMSUNG_MZQL21T9HCJR-00A07_S64GNN0X204442`
  - stanton-02: `nvme-SAMSUNG_MZQL21T9HCJR-00A07_S64GNN0WB06544`
  - stanton-03: `nvme-SAMSUNG_MZQL21T9HCJR-00A07_S64GNN0X204434`

### Storage Pools
- **12 pools, 169 PGs** (all active+clean)
- **Data Usage:** 262 GiB used / 5.2 TiB available
- **Objects:** 47.38k objects, 87 GiB

### Services Running
- **MON:** 3 daemons (quorum: a, b, c)
- **MGR:** 1 active + 1 standby
- **MDS:** 1 active + 1 hot standby
- **RGW:** 2 daemons (S3-compatible object storage)

### Custom Configurations
```yaml
configOverride: |
  [global]
  bdev_enable_discard = true
  bdev_async_discard = true
  osd_class_update_on_start = false  # ⚠️ Monitor this setting
  bluestore_prefer_deferred_size = 0
  bluestore_deferred_batch_ops = 16
  bluestore_deferred_batch_ops_per_txn = 32
  bluestore_min_alloc_size = 4096
  bluestore_compression_algorithm = none
  bdev_flock_retry = 3
```

### Storage Classes
- **Block Storage (RBD):** `${CLUSTER_STORAGE_BLOCK}` (default, 3-way replication)
  - Compression: aggressive/zstd
  - Mount options: discard
- **Filesystem (CephFS):** `${CLUSTER_STORAGE_FILESYSTEM}` (3-way replication)
- **Object Storage (RGW):** `${CLUSTER_STORAGE_BUCKET}` (EC 2+1)

---

## ⚠️ CRITICAL PRE-UPGRADE REQUIREMENTS

### 1. Backup Everything

```bash
# Set kubeconfig
export KUBECONFIG=~/home-ops/kubeconfig

# Backup CephCluster CR
kubectl -n rook-ceph get cephcluster -o yaml > ~/backups/ceph/cephcluster-$(date +%Y%m%d).yaml

# Backup all Rook CRDs
kubectl get crd | grep ceph.rook.io | awk '{print $1}' | xargs -I {} kubectl get {} -A -o yaml > ~/backups/ceph/all-ceph-crds-$(date +%Y%m%d).yaml

# Backup operator deployment
kubectl -n rook-ceph get deploy rook-ceph-operator -o yaml > ~/backups/ceph/rook-operator-$(date +%Y%m%d).yaml

# Backup Flux HelmReleases
cp -r ~/home-ops/kubernetes/apps/rook-ceph ~/backups/ceph/rook-ceph-flux-$(date +%Y%m%d)/

# Backup Ceph configuration
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config dump > ~/backups/ceph/ceph-config-$(date +%Y%m%d).txt

# Backup critical data snapshots (if possible)
# Document PVC usage: kubectl get pvc -A -o wide > ~/backups/ceph/pvc-list-$(date +%Y%m%d).txt
```

### 2. Pre-Upgrade Health Checks

```bash
# Comprehensive health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Verify all PGs are active+clean
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat

# Check OSD status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd stat
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# Verify no ongoing operations
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s

# Check for any warnings
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Verify MGR modules
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mgr module ls

# Check current Ceph version on all daemons
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# Verify no scrubbing/deep-scrubbing is in progress
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg dump | grep -i scrub
```

### 3. Document Current State

```bash
# Create migration log directory
mkdir -p ~/backups/ceph/migration-$(date +%Y%m%d)

# Capture full cluster state
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > ~/backups/ceph/migration-$(date +%Y%m%d)/pre-upgrade-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd df tree > ~/backups/ceph/migration-$(date +%Y%m%d)/pre-upgrade-osd-df.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph df > ~/backups/ceph/migration-$(date +%Y%m%d)/pre-upgrade-df.txt
kubectl get pods -n rook-ceph -o wide > ~/backups/ceph/migration-$(date +%Y%m%d)/pre-upgrade-pods.txt
```

### 4. Pre-Flight Checklist

- [ ] Cluster health is `HEALTH_OK`
- [ ] All PGs are `active+clean` (no degraded/misplaced/recovering)
- [ ] No OSDs are down or out
- [ ] No ongoing recovery operations
- [ ] All backups completed successfully
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified
- [ ] Rollback plan reviewed
- [ ] **CRITICAL:** No production workloads will be significantly impacted during upgrade

---

## PHASE 1: Reef 18.2.7 → Squid 19.2.x

### Upgrade Path Overview

**Target Versions:**
- Rook Operator: v1.18.x → Latest v1.18.x or v1.19.x
- Ceph Image: `quay.io/ceph/ceph:v18.2.7` → `quay.io/ceph/ceph:v19.2.3` (or latest Squid patch)

**Estimated Duration:** 45-90 minutes
**Risk Level:** Medium

### Breaking Changes & New Features in Squid

#### 1. Configuration Changes

**REMOVED:**
- `mon_cluster_log_file_level` (replaced by `mon_cluster_log_level`)
- `mon_cluster_log_to_syslog_level` (replaced by `mon_cluster_log_level`)

**ACTION REQUIRED:** Your custom config doesn't use these, so no change needed.

#### 2. osd_class_update_on_start

Your current config has `osd_class_update_on_start = false`. This setting is compatible with Squid, but monitor for deprecation warnings in logs.

#### 3. CephFS Changes

- **Breaking:** `ceph fs rename` now requires filesystem to be offline and `refuse_client_session` set
- **Breaking:** `mds_client_delegate_inos_pct` defaults to 0 (disables async dirops in kernel client)

**IMPACT:** You have 1 CephFS filesystem. No rename planned, so no immediate action needed.

#### 4. RGW (Object Storage) Changes

- **Feature:** New notification_v2 zone feature for S3 bucket notifications (opt-in after upgrade)
- **Change:** LastModified timestamps truncated to seconds (may move backwards during upgrade)

**IMPACT:** You have 2 RGW daemons. Timestamps may change, but functionality preserved.

#### 5. Known Issues

**⚠️ iSCSI WARNING:** If using iSCSI, review [Tracker Issue #68215](https://tracker.ceph.com/issues/68215) before upgrading to 19.2.0.

**IMPACT:** You're not using iSCSI based on your config.

### Step-by-Step Upgrade Process

#### Step 1: Set noout Flag (Optional but Recommended)

This prevents OSDs from being marked out during upgrade restarts.

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance
```

#### Step 2: Verify Rook Operator Health

```bash
kubectl -n rook-ceph get pods -l app=rook-ceph-operator
kubectl -n rook-ceph logs -l app=rook-ceph-operator --tail=100
```

Ensure operator is healthy before proceeding.

#### Step 3: Update Rook Operator (if needed)

Check if a newer Rook v1.18.x or v1.19.x is available with better Squid support:

```bash
# Check current version
kubectl -n rook-ceph get deploy rook-ceph-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# If upgrading Rook operator, edit the OCIRepository
# File: /home/gavin/home-ops/kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml
# Change: ref.tag: v1.18.7 → v1.19.x (check latest release)
```

**IMPORTANT:** Upgrade Rook operator BEFORE Ceph version. Commit and reconcile:

```bash
cd ~/home-ops
git add kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml
git commit -m "chore(rook-ceph): Upgrade operator to v1.19.x for Squid support"
git push

# Wait for Flux to reconcile (or force reconcile)
flux reconcile source git home-kubernetes -n flux-system
flux reconcile kustomization cluster-apps-rook-ceph -n flux-system --with-source

# Monitor operator upgrade
kubectl -n rook-ceph get pods -w
```

Wait for operator pod to be Running and Ready.

#### Step 4: Update Ceph Image Version

Edit the cluster HelmRelease:

**File:** `/home/gavin/home-ops/kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

**Change:**
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.7
    allowUnsupported: false
```

**To:**
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3  # Or latest Squid patch version
    allowUnsupported: false  # Try false first; set to true if Rook complains
```

**Commit and push:**

```bash
cd ~/home-ops
git add kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml
git commit -m "feat(rook-ceph): Upgrade Ceph from Reef 18.2.7 to Squid 19.2.3

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

#### Step 5: Reconcile Cluster HelmRelease

```bash
# Force Flux to reconcile the cluster
flux reconcile kustomization cluster-apps-rook-ceph-cluster -n flux-system --with-source

# Watch the upgrade process
kubectl -n rook-ceph get pods -w
```

#### Step 6: Monitor Upgrade Progress

Rook will upgrade in this order:
1. **MON** (monitors) - one at a time
2. **MGR** (managers) - one at a time
3. **OSD** (object storage daemons) - one at a time
4. **MDS** (metadata servers) - if using CephFS
5. **RGW** (RADOS gateways) - if using object storage

**Monitor upgrade:**

```bash
# Watch Ceph status during upgrade
watch -n 5 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status'

# Check versions of all daemons
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# Monitor operator logs for any issues
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f

# Check for upgrade errors
kubectl -n rook-ceph get cephcluster -o jsonpath='{.items[0].status.phase}'
kubectl -n rook-ceph get cephcluster -o jsonpath='{.items[0].status.message}'
```

**Expected behavior:**
- Pods will restart one by one (rolling restart)
- Cluster may show `HEALTH_WARN` temporarily during upgrades
- PGs may show as `degraded` or `peering` briefly

**⏱️ Estimated time:** 30-60 minutes depending on cluster size.

#### Step 7: Verify Upgrade Completion

```bash
# Confirm all daemons are running Squid 19.2.3
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# Should show something like:
# "ceph version 19.2.3 (...) squid (stable)"

# Verify cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Should be HEALTH_OK (or HEALTH_WARN with explanations)
```

#### Step 8: Finalize Upgrade

Once all daemons are upgraded, finalize the upgrade by setting the required OSD release flag:

```bash
# Check current require_osd_release
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require

# If it shows "require_osd_release reef", upgrade it:
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release squid

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release squid
```

#### Step 9: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance
```

#### Step 10: Post-Upgrade Validation

```bash
# Full health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Verify all PGs are active+clean
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat

# Check OSD status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# Test storage provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-squid-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${CLUSTER_STORAGE_BLOCK}
  resources:
    requests:
      storage: 1Gi
EOF

# Verify PVC bound
kubectl get pvc test-squid-pvc -n default

# Cleanup
kubectl delete pvc test-squid-pvc -n default
```

#### Step 11: Document Squid Upgrade

```bash
# Capture post-upgrade state
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > ~/backups/ceph/migration-$(date +%Y%m%d)/post-squid-upgrade-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > ~/backups/ceph/migration-$(date +%Y%m%d)/post-squid-versions.txt
```

### Phase 1 Rollback Procedure

**⚠️ WARNING:** Ceph does NOT support downgrading. If the upgrade fails:

1. **If upgrade is stuck/failed mid-way:**
   ```bash
   # Check operator logs
   kubectl -n rook-ceph logs -l app=rook-ceph-operator --tail=200

   # Check CephCluster status
   kubectl -n rook-ceph describe cephcluster

   # If necessary, restart operator
   kubectl -n rook-ceph rollout restart deploy/rook-ceph-operator
   ```

2. **If Ceph cluster is in HEALTH_ERR:**
   ```bash
   # Get detailed error
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

   # Common issues:
   # - OSDs failing to start: Check OSD logs
   # - MONs in quorum issues: Check MON logs
   # - PGs stuck: Wait for recovery or investigate specific PG
   ```

3. **Last resort - restore from backup:**
   - Reinstall Rook/Ceph from backups
   - This will require cluster recreation (⚠️ DATA LOSS RISK)

---

## PHASE 2: Squid 19.2.x → Tentacle 20.2.x

### Upgrade Path Overview

**Target Versions:**
- Rook Operator: v1.19.x or v1.20.x (when available)
- Ceph Image: `quay.io/ceph/ceph:v19.2.3` → `quay.io/ceph/ceph:v20.2.0` (or latest Tentacle)

**Estimated Duration:** 45-90 minutes
**Risk Level:** Medium-High (newer release, less battle-tested)

**⚠️ IMPORTANT:** Tentacle (v20) was released Nov 18, 2025. Rook support may be experimental. Check for:
- Latest Rook version with Tentacle support
- Community feedback on Tentacle stability
- Consider waiting 1-2 months for patch releases if not urgent

### Breaking Changes & New Features in Tentacle

#### 1. RGW S3 Bucket Notifications

**Change:** New data layout for Topic metadata (notification_v2)
- Not enabled by default on upgrade
- Must manually enable after all RGWs upgraded

**ACTION REQUIRED (if using S3 notifications):**
```bash
# After upgrade, enable notification_v2 zone feature
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin zone modify --rgw-zone=default --enable-feature=notification_v2
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin period update --commit
```

#### 2. RGW LastModified Timestamps

**Change:** Timestamps truncated to seconds (AWS S3 compatibility)
**IMPACT:** Timestamps may move backwards during upgrade. Applications relying on precise timestamps should be tested.

#### 3. User Account Feature (IAM)

**Deprecation:** Tenant-level IAM functionality deprecated in favor of User Account feature
**IMPACT:** If using RGW with IAM policies, review migration path to User Accounts

#### 4. CephFS Changes

**Change:** Modifying `max_mds` when cluster unhealthy requires `--yes-i-really-mean-it` flag
**IMPACT:** Safety improvement; no immediate action needed

### Prerequisites for Tentacle Upgrade

#### 1. Verify Rook Operator Version

Tentacle requires Rook v1.19+ (or v1.20+ when available). Check GitHub releases:

```bash
# Check for latest Rook release with Tentacle support
# Visit: https://github.com/rook/rook/releases

# Look for release notes mentioning "Tentacle support"
```

#### 2. Check allowUnsupported Flag

Early Tentacle support may require:

```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v20.2.0
    allowUnsupported: true  # ⚠️ May be required initially
```

### Step-by-Step Upgrade Process

#### Step 1: Pre-Upgrade Validation

```bash
# Ensure Squid is healthy
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Verify all daemons are on Squid 19.2.x
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# Ensure require_osd_release is set to squid
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release

# Backup before Tentacle upgrade
kubectl -n rook-ceph get cephcluster -o yaml > ~/backups/ceph/cephcluster-pre-tentacle-$(date +%Y%m%d).yaml
```

#### Step 2: Set Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set norebalance
```

#### Step 3: Update Rook Operator (if needed)

```bash
# Check for Rook version with Tentacle support
# Edit: /home/gavin/home-ops/kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml
# Change ref.tag to latest version (e.g., v1.20.x)

cd ~/home-ops
git add kubernetes/apps/rook-ceph/rook-ceph/app/ocirepository.yaml
git commit -m "chore(rook-ceph): Upgrade operator to v1.20.x for Tentacle support"
git push

flux reconcile kustomization cluster-apps-rook-ceph -n flux-system --with-source

# Wait for operator upgrade
kubectl -n rook-ceph get pods -w
```

#### Step 4: Update Ceph Image to Tentacle

**File:** `/home/gavin/home-ops/kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`

**Change:**
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.3
    allowUnsupported: false
```

**To:**
```yaml
cephClusterSpec:
  cephVersion:
    image: quay.io/ceph/ceph:v20.2.0  # Or latest Tentacle patch
    allowUnsupported: true  # Set to true if Rook requires it for Tentacle
```

**Commit and push:**

```bash
cd ~/home-ops
git add kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml
git commit -m "feat(rook-ceph): Upgrade Ceph from Squid 19.2.3 to Tentacle 20.2.0

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

#### Step 5: Reconcile and Monitor

```bash
flux reconcile kustomization cluster-apps-rook-ceph-cluster -n flux-system --with-source

# Monitor upgrade progress
watch -n 5 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status'

# Check daemon versions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions

# Watch operator logs
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f
```

**⏱️ Estimated time:** 30-60 minutes

#### Step 6: Finalize Tentacle Upgrade

```bash
# Set require_osd_release to tentacle
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd require-osd-release tentacle

# Verify
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep require_osd_release
# Should show: require_osd_release tentacle
```

#### Step 7: Enable notification_v2 (if using RGW)

```bash
# Check current zone features
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin zone get --rgw-zone=default

# Enable notification_v2
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin zone modify --rgw-zone=default --enable-feature=notification_v2
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin period update --commit

# Restart RGW pods (Flux will handle this automatically)
```

#### Step 8: Unset Safety Flags

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance
```

#### Step 9: Post-Upgrade Validation

```bash
# Comprehensive health check
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Verify Tentacle version
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph version
# Should show: ceph version 20.2.0 (...) tentacle (stable)

# Test storage provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-tentacle-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${CLUSTER_STORAGE_BLOCK}
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-tentacle-pvc -n default
kubectl delete pvc test-tentacle-pvc -n default

# Test CephFS (if using)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${CLUSTER_STORAGE_FILESYSTEM}
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-cephfs-pvc -n default
kubectl delete pvc test-cephfs-pvc -n default
```

#### Step 10: Document Tentacle Upgrade

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status > ~/backups/ceph/migration-$(date +%Y%m%d)/post-tentacle-upgrade-status.txt
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph versions > ~/backups/ceph/migration-$(date +%Y%m%d)/post-tentacle-versions.txt
```

---

## Post-Migration Validation & Performance Testing

### 1. Comprehensive Health Checks

```bash
# Cluster health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail

# Storage usage
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph df

# OSD performance
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd perf

# Pool statistics
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool stats

# Check for any stuck operations
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -w
```

### 2. Application Testing

```bash
# List all PVCs using Ceph storage
kubectl get pvc -A | grep -E "${CLUSTER_STORAGE_BLOCK}|${CLUSTER_STORAGE_FILESYSTEM}"

# Verify existing workloads are healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# Test database workloads (if applicable)
# Test file uploads/downloads (if using RGW)
```

### 3. Performance Baseline

```bash
# Run benchmarks to compare with pre-upgrade performance
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rados bench -p ceph-blockpool 30 write --no-cleanup
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rados bench -p ceph-blockpool 30 seq
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rados bench -p ceph-blockpool 30 rand
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rados cleanup -p ceph-blockpool
```

### 4. Monitor for Issues

```bash
# Check Ceph logs for warnings
kubectl -n rook-ceph logs -l app=rook-ceph-mon --tail=100
kubectl -n rook-ceph logs -l app=rook-ceph-osd --tail=100
kubectl -n rook-ceph logs -l app=rook-ceph-mgr --tail=100

# Monitor Prometheus alerts (if configured)
# Check Ceph dashboard (if exposed)
```

---

## Configuration Review & Optimization

### Review Custom Configurations

Your current `configOverride` settings:

```yaml
[global]
bdev_enable_discard = true          # ✅ Still valid in Tentacle
bdev_async_discard = true           # ✅ Still valid in Tentacle
osd_class_update_on_start = false   # ⚠️ Monitor deprecation warnings
bluestore_prefer_deferred_size = 0  # ✅ Still valid in Tentacle
bluestore_deferred_batch_ops = 16   # ✅ Still valid in Tentacle
bluestore_deferred_batch_ops_per_txn = 32  # ✅ Still valid in Tentacle
bluestore_min_alloc_size = 4096     # ✅ Still valid in Tentacle
bluestore_compression_algorithm = none  # ✅ Still valid in Tentacle
bdev_flock_retry = 3                # ✅ Still valid in Tentacle
```

**Post-upgrade actions:**

1. Check for deprecation warnings:
   ```bash
   kubectl -n rook-ceph logs -l app=rook-ceph-osd | grep -i deprecat
   ```

2. If `osd_class_update_on_start` is deprecated, remove it and allow default behavior.

3. Review new Tentacle features that might benefit your cluster:
   - New compression algorithms
   - Enhanced telemetry options
   - Improved auto-tuning

---

## Troubleshooting Guide

### Issue: Upgrade Stuck on MON/MGR

**Symptoms:** MON or MGR pods keep restarting during upgrade

**Solution:**
```bash
# Check MON logs
kubectl -n rook-ceph logs -l app=rook-ceph-mon --tail=200

# Common issue: Quorum lost
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mon stat

# If necessary, remove and re-add problematic MON (advanced)
```

### Issue: OSDs Failing to Start

**Symptoms:** OSD pods in CrashLoopBackOff after upgrade

**Solution:**
```bash
# Check OSD logs
kubectl -n rook-ceph logs -l app=rook-ceph-osd --tail=200

# Common causes:
# - BlueStore metadata incompatibility
# - Device permissions
# - Configuration errors

# Check OSD details
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd metadata <osd-id>
```

### Issue: PGs Stuck in Degraded/Undersized

**Symptoms:** PGs not recovering after upgrade

**Solution:**
```bash
# Identify stuck PGs
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg dump | grep -v active+clean

# Query specific PG
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg <pg-id> query

# Force PG recovery (use with caution)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg repair <pg-id>
```

### Issue: RGW Not Starting After Upgrade

**Symptoms:** RGW pods failing to start

**Solution:**
```bash
# Check RGW logs
kubectl -n rook-ceph logs -l app=rook-ceph-rgw --tail=200

# Common issue: Zone configuration
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin zone get

# Reset zone if needed (advanced)
```

### Issue: allowUnsupported Error

**Symptoms:** Operator refuses to upgrade: "allowUnsupported must be set to true"

**Solution:**
```bash
# Edit CephCluster and set allowUnsupported: true
# File: /home/gavin/home-ops/kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml

cephClusterSpec:
  cephVersion:
    allowUnsupported: true
```

---

## Emergency Rollback Procedures

### ⚠️ CRITICAL WARNING

**Ceph does NOT support version downgrades.** Once upgraded, you cannot revert to an older Ceph version without:
- Complete cluster reinstallation
- Data loss (unless fully backed up externally)

### If Upgrade Fails Mid-Way

**Option 1: Complete the Upgrade**
```bash
# Force upgrade to continue
kubectl -n rook-ceph rollout restart deploy/rook-ceph-operator

# Monitor and troubleshoot specific failures
kubectl -n rook-ceph describe cephcluster
```

**Option 2: Restore from Backup (Data Loss Risk)**
1. Delete CephCluster CR
2. Remove all Ceph data from OSDs (destructive!)
3. Reinstall Ceph at previous version
4. Restore data from external backups

**Option 3: Contact Rook/Ceph Community**
- Rook Slack: https://rook.io/slack
- Ceph Mailing List: ceph-users@ceph.io
- GitHub Issues: https://github.com/rook/rook/issues

---

## Monitoring & Alerts

### Key Metrics to Watch

1. **Cluster Health:** Must remain HEALTH_OK or HEALTH_WARN (with explanations)
2. **OSD Status:** All OSDs up and in
3. **PG Status:** All PGs active+clean
4. **Storage Utilization:** Should not spike unexpectedly
5. **I/O Performance:** Should match pre-upgrade baselines

### Recommended Monitoring Commands

```bash
# Continuous health monitoring
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail'

# PG status
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph pg stat'

# OSD status
watch -n 10 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree'
```

---

## Success Criteria

### Phase 1 Complete (Squid)
- [ ] All daemons running Ceph 19.2.x
- [ ] `require_osd_release` set to `squid`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] Storage provisioning tests pass
- [ ] No errors in operator logs

### Phase 2 Complete (Tentacle)
- [ ] All daemons running Ceph 20.2.x
- [ ] `require_osd_release` set to `tentacle`
- [ ] Cluster health: `HEALTH_OK`
- [ ] All PGs: `active+clean`
- [ ] RGW notification_v2 enabled (if applicable)
- [ ] Storage provisioning tests pass
- [ ] Application workloads verified

### Final Validation
- [ ] Performance benchmarks match pre-upgrade baselines
- [ ] No warnings in Ceph logs
- [ ] All backups retained for 30 days
- [ ] Documentation updated with new versions

---

## Timeline & Planning

### Recommended Schedule

**Week 1: Pre-Upgrade**
- Review this guide thoroughly
- Create all backups
- Test backup restoration (optional but recommended)
- Schedule maintenance window

**Week 2: Phase 1 (Reef → Squid)**
- Execute Phase 1 during maintenance window
- Monitor for 48 hours post-upgrade
- Document any issues

**Week 3-4: Stabilization**
- Monitor Squid performance
- Review community feedback on Squid stability
- Plan Phase 2

**Week 5: Phase 2 (Squid → Tentacle)**
- ⚠️ **WAIT for community validation of Tentacle (v20)**
- Check for patch releases (20.2.1, 20.2.2, etc.)
- Execute Phase 2 during maintenance window
- Monitor for 1 week post-upgrade

### Maintenance Window Requirements

- **Duration:** 2-3 hours per phase (with buffer)
- **Impact:** Brief storage interruptions during daemon restarts
- **Risk:** Medium (higher for Tentacle due to newness)
- **Rollback:** None (upgrades are one-way)

---

## Additional Resources

### Documentation
- **Rook Ceph Upgrades:** https://rook.io/docs/rook/latest/Upgrade/ceph-upgrade/
- **Ceph Squid Release Notes:** https://docs.ceph.com/en/latest/releases/squid/
- **Ceph Tentacle Release Notes:** https://ceph.io/en/news/blog/2025/v20-2-0-tentacle-released/
- **Rook GitHub Releases:** https://github.com/rook/rook/releases

### Community Support
- **Rook Slack:** https://rook.io/slack (#general, #ceph)
- **Ceph Users List:** ceph-users@ceph.io
- **Reddit:** r/ceph

### Your Cluster-Specific Commands

```bash
# Kubeconfig
export KUBECONFIG=~/home-ops/kubeconfig

# Flux reconciliation
flux reconcile source git home-kubernetes -n flux-system
flux reconcile kustomization cluster-apps-rook-ceph -n flux-system --with-source
flux reconcile kustomization cluster-apps-rook-ceph-cluster -n flux-system --with-source

# Ceph toolbox
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- <command>

# Operator logs
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f
```

---

## Migration Log Template

Document each step:

```
# Ceph Upgrade Log

## Phase 1: Reef → Squid
- Start Time: ___________
- Operator Version: v1.18.7 → v1.19.x
- Ceph Version: v18.2.7 → v19.2.3
- Pre-Upgrade Health: HEALTH_OK
- Issues Encountered: ___________
- Resolution: ___________
- End Time: ___________
- Post-Upgrade Health: ___________

## Phase 2: Squid → Tentacle
- Start Time: ___________
- Operator Version: v1.19.x → v1.20.x
- Ceph Version: v19.2.3 → v20.2.0
- Pre-Upgrade Health: ___________
- Issues Encountered: ___________
- Resolution: ___________
- End Time: ___________
- Post-Upgrade Health: ___________
```

---

## Final Notes

1. **Test in Non-Production First:** If you have a staging environment, test this upgrade path there first.

2. **Tentacle is New (Nov 2025):** Consider waiting 1-2 months for community validation and patch releases unless you need specific Tentacle features.

3. **No Downgrade Path:** Once you upgrade, you cannot go back. Ensure backups are solid.

4. **Monitor Community:** Check Rook GitHub issues and Slack for Tentacle-related issues before Phase 2.

5. **Your Config is Clean:** Your current Rook/Ceph setup is well-configured. Most settings will carry forward without changes.

6. **osd_class_update_on_start:** This setting may be deprecated in future releases. Monitor logs post-upgrade.

---

**Good luck with the migration! This HAS to go smoothly, and with proper preparation, it will.** 🚀
