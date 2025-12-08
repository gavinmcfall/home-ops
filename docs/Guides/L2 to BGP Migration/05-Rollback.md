---
description: Rollback procedures if BGP migration fails
tags: ["Rollback", "L2", "BGP", "Recovery"]
audience: ["Humans"]
categories: ["How-To[100%]", "Recovery[90%]"]
---

# Rollback Procedures

If BGP migration fails, use these procedures to restore L2 announcements.

---

## Rollback Strategy

BGP and L2 can coexist. The rollback is safe because:

1. **L2 is still configured** - We didn't remove it
2. **Gateway nodeSelectors are in place** - Pods stay colocated with L2 leases
3. **Removing BGP CRDs** - Simply stops BGP advertisement

---

## Quick Rollback (< 5 minutes)

### Step 1: Remove BGP CRDs

```bash
kubectl delete ciliumbgpclusterconfig bgp-cluster
kubectl delete ciliumbgppeerconfig udm-peer
kubectl delete ciliumbgpadvertisement lb-services
```

### Step 2: Disable BGP on UDM

1. Open UniFi Network UI
2. Go to **Settings** → **Routing** → **BGP**
3. Delete the `kubernetes-cluster` entry

### Step 3: Verify L2 Takes Over

```bash
# Check L2 leases exist
kubectl get lease -n kube-system | grep cilium-l2

# Check gateway services have IPs
kubectl get svc -n network -l app.kubernetes.io/managed-by=envoy-gateway
```

### Step 4: Test Connectivity

```bash
# From any node
kubectl run rollback-test --rm -i --restart=Never --image=busybox \
  -- nc -zv -w 5 10.90.3.202 443
```

---

## Detailed Rollback

### If BGP CRDs Won't Delete

Force removal:
```bash
kubectl delete ciliumbgpclusterconfig bgp-cluster --force --grace-period=0
kubectl delete ciliumbgppeerconfig udm-peer --force --grace-period=0
kubectl delete ciliumbgpadvertisement lb-services --force --grace-period=0
```

### If UDM BGP Won't Disable via UI

SSH and manually disable:
```bash
ssh unifi

# Stop BGP daemon
sudo systemctl stop frr

# Or edit daemons file
sudo sed -i 's/bgpd=yes/bgpd=no/' /etc/frr/daemons
sudo systemctl restart frr
```

### If L2 Leases Are Wrong

Force lease re-election:
```bash
# Delete specific lease to trigger re-election
kubectl delete lease -n kube-system cilium-l2announce-network-envoy-internal
kubectl delete lease -n kube-system cilium-l2announce-network-envoy-external
```

The lease will be recreated, hopefully on the correct node (per nodeSelector).

---

## Revert Git Changes

If you committed the BGP CRD files:

```bash
# Revert the commit
git log --oneline -5  # Find the BGP commit hash
git revert <commit-hash>
git push

# Or remove the file and commit
rm kubernetes/apps/kube-system/cilium/config/cilium-bgp.yaml
# Remove from kustomization.yaml
git add -A
git commit -m "rollback: remove BGP configuration"
git push
```

---

## Verify Rollback Success

### L2 Announcements Active

```bash
kubectl get lease -n kube-system | grep cilium-l2
```

Expected: Leases exist with a holder identity.

### Gateway Pods on Correct Node

```bash
kubectl get pods -n network -l app.kubernetes.io/name=envoy -o wide
```

Expected: Pods on stanton-02 (per nodeSelector).

### L2 Lease on Same Node

```bash
kubectl get lease -n kube-system cilium-l2announce-network-envoy-internal \
  -o jsonpath='{.spec.holderIdentity}'
```

Expected: `stanton-02`

### Connectivity Works

```bash
# Test from the same node as gateway
kubectl run test-same --rm -i --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"stanton-02"}}}' \
  --image=busybox -- nc -zv -w 5 10.90.3.202 443
```

Expected: Connection succeeds.

---

## Common Rollback Issues

### Issue: Traffic Still Going via BGP

**Cause**: UDM still has BGP routes in routing table.

**Fix**:
```bash
ssh unifi "vtysh -c 'clear ip bgp * soft'"
```

Or wait for routes to age out (hold time: 90 seconds).

### Issue: L2 Lease on Wrong Node

**Cause**: nodeSelector not matching.

**Fix**: Verify nodeSelector in `cilium-l2-policy.yaml`:
```yaml
nodeSelector:
  matchLabels:
    kubernetes.io/hostname: stanton-02
```

### Issue: Pods Still Scheduling Elsewhere

**Cause**: Gateway EnvoyProxy nodeSelector removed.

**Fix**: Restore nodeSelector in:
- `kubernetes/apps/network/envoy-gateway/app/internal/envoyproxy.yaml`
- `kubernetes/apps/network/envoy-gateway/app/external/envoyproxy.yaml`

```yaml
spec:
  provider:
    kubernetes:
      envoyDeployment:
        pod:
          nodeSelector:
            kubernetes.io/hostname: stanton-02
```

---

## Timeline

| Action | Duration |
|--------|----------|
| Delete BGP CRDs | < 1 minute |
| Disable BGP on UDM | < 1 minute |
| L2 re-establishes | < 30 seconds |
| Verify connectivity | < 2 minutes |

**Total rollback time**: < 5 minutes

---

## Post-Rollback

After rollback, the cluster is back to the pre-migration state:

- L2 announcements handle LoadBalancer IPs
- Gateway pods pinned to stanton-02
- L2 leases held by stanton-02
- Hairpin workaround in place

To attempt migration again:
1. Diagnose what went wrong
2. Fix configuration issues
3. Start from [02-Cluster-Changes.md](./02-Cluster-Changes.md)

---

## Getting Help

If rollback fails:

1. **Check Cilium status**:
   ```bash
   cilium status
   kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
   ```

2. **Restart Cilium agents** (last resort):
   ```bash
   kubectl rollout restart daemonset/cilium -n kube-system
   ```

3. **Check UDM routing**:
   ```bash
   ssh unifi "ip route show"
   ```
