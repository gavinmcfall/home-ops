---
description: Cilium BGP CRD configurations for Kubernetes cluster
tags: ["CiliumBGPClusterConfig", "CiliumBGPPeerConfig", "CiliumBGPAdvertisement", "Cilium"]
audience: ["Humans"]
categories: ["How-To[100%]", "Kubernetes[90%]"]
---

# Cluster Changes for BGP Migration

This document covers all Kubernetes-side changes needed to enable BGP.

---

## Prerequisites

- [ ] Cilium v1.14+ (current: v1.18.3)
- [ ] `bgpControlPlane.enabled: true` in Cilium helm values (already configured)
- [ ] kubectl access to cluster

Verify BGP control plane is enabled:
```bash
kubectl get deployment -n kube-system cilium-operator -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -o 'bgp-control-plane-[a-z]*'
```

---

## Overview of Resources

| Resource | Purpose |
|----------|---------|
| CiliumBGPAdvertisement | What to advertise (LoadBalancer IPs) |
| CiliumBGPPeerConfig | How to peer (timers, families) |
| CiliumBGPClusterConfig | Who to peer with (UDM Pro) |
| CiliumLoadBalancerIPPool | IP range for services (unchanged) |

---

## File: `kubernetes/apps/kube-system/cilium/config/cilium-bgp.yaml`

Create this new file:

```yaml
---
# What to advertise via BGP
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: lb-services
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      # Advertise all LoadBalancer services unless explicitly excluded
      selector:
        matchExpressions:
          - key: io.cilium/bgp-announce
            operator: NotIn
            values: ["false"]
---
# BGP session parameters
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: udm-peer
spec:
  timers:
    # How long to wait before declaring peer dead
    holdTimeSeconds: 90
    # How often to send keepalive messages
    keepAliveTimeSeconds: 30
  # Allows graceful restart during Cilium upgrades
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 120
  # IPv4 unicast address family
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
---
# BGP peering configuration
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-cluster
spec:
  # Apply to all Linux nodes
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
    - name: "home-cluster"
      # Our cluster's ASN
      localASN: 65010
      peers:
        - name: "udm-pro"
          # UDM Pro's IP
          peerAddress: "10.90.254.1"
          # UDM Pro's ASN
          peerASN: 65001
          peerConfigRef:
            name: udm-peer
```

---

## Understanding the Configuration

### CiliumBGPAdvertisement

**Purpose**: Tells Cilium what to advertise via BGP.

```yaml
advertisements:
  - advertisementType: "Service"
    service:
      addresses:
        - LoadBalancerIP    # Advertise LoadBalancer IPs
```

**Selector logic**: All services are advertised unless they have label `io.cilium/bgp-announce: "false"`.

### CiliumBGPPeerConfig

**Purpose**: Defines BGP session behavior.

| Setting | Value | Why |
|---------|-------|-----|
| holdTimeSeconds | 90 | Detect peer failure within 90s |
| keepAliveTimeSeconds | 30 | Send keepalive every 30s (must be < holdTime/3) |
| gracefulRestart | enabled | Prevent route flaps during Cilium pod restarts |

### CiliumBGPClusterConfig

**Purpose**: Defines the BGP peering relationship.

| Setting | Value | Why |
|---------|-------|-----|
| localASN | 65010 | Our cluster's AS number |
| peerAddress | 10.90.254.1 | UDM Pro's IP |
| peerASN | 65001 | UDM Pro's AS number |

---

## Deployment Steps

### Step 1: Create the BGP configuration file

```bash
cat << 'EOF' > kubernetes/apps/kube-system/cilium/config/cilium-bgp.yaml
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: lb-services
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - key: io.cilium/bgp-announce
            operator: NotIn
            values: ["false"]
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: udm-peer
spec:
  timers:
    holdTimeSeconds: 90
    keepAliveTimeSeconds: 30
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 120
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-cluster
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
    - name: "home-cluster"
      localASN: 65010
      peers:
        - name: "udm-pro"
          peerAddress: "10.90.254.1"
          peerASN: 65001
          peerConfigRef:
            name: udm-peer
EOF
```

### Step 2: Update Kustomization

Add to `kubernetes/apps/kube-system/cilium/config/kustomization.yaml`:

```yaml
resources:
  - ./cilium-l2.yaml
  - ./cilium-bgp.yaml  # Add this line
```

### Step 3: Commit and Push

```bash
git add kubernetes/apps/kube-system/cilium/config/
git commit -m "feat(cilium): add BGP control plane configuration

Configure Cilium BGP peering with UDM Pro (ASN 65001)
to advertise LoadBalancer IPs via BGP instead of L2.

- CiliumBGPClusterConfig: peer all nodes with UDM
- CiliumBGPPeerConfig: 90s hold time, graceful restart
- CiliumBGPAdvertisement: advertise LoadBalancer IPs

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"

git push
```

### Step 4: Wait for Flux or Force Reconcile

```bash
# Force immediate reconcile
flux reconcile kustomization cilium-config -n flux-system --force

# Or wait for normal sync (up to 5 minutes)
```

---

## Verification

### Check CRDs are created

```bash
kubectl get ciliumbgpclusterconfig
kubectl get ciliumbgppeerconfig
kubectl get ciliumbgpadvertisement
```

### Check BGP node configs (created by operator)

```bash
kubectl get ciliumbgpnodeconfig
```

Each node should have a corresponding CiliumBGPNodeConfig.

### Check BGP peer status

```bash
cilium bgp peers
```

Expected output (once UDM is configured):
```
Node         Local AS   Peer AS   Peer Address    Session State   Uptime
stanton-01   65010      65001     10.90.254.1     established     5m
stanton-02   65010      65001     10.90.254.1     established     5m
stanton-03   65010      65001     10.90.254.1     established     5m
```

**Note**: Sessions will show `active` (not established) until UDM BGP is configured.

---

## Post-Migration Cleanup

After BGP is working, you can optionally:

### 1. Remove gateway nodeSelector pins

Edit `kubernetes/apps/network/envoy-gateway/app/internal/envoyproxy.yaml`:
```yaml
# Remove this section:
pod:
  nodeSelector:
    kubernetes.io/hostname: stanton-02
```

Same for `external/envoyproxy.yaml`.

### 2. Remove gateway-specific L2 policy

Delete `kubernetes/apps/network/envoy-gateway/app/cilium-l2-policy.yaml` and remove from kustomization.

### 3. Update catch-all L2 policy

Remove the gateway exclusion from `kubernetes/apps/kube-system/cilium/config/cilium-l2.yaml` if desired.

**Recommendation**: Keep L2 as fallback initially. Once BGP is proven stable, consider disabling L2 entirely.

---

## Troubleshooting

### BGP sessions stuck in "active" state

1. Check UDM has BGP configured (see [03-UDM-Changes.md](./03-UDM-Changes.md))
2. Verify no firewall blocking TCP 179:
   ```bash
   # From a node
   nc -zv 10.90.254.1 179
   ```

### No routes being advertised

1. Check CiliumBGPAdvertisement exists:
   ```bash
   kubectl get ciliumbgpadvertisement lb-services -o yaml
   ```
2. Check services have LoadBalancer IPs:
   ```bash
   kubectl get svc -A | grep LoadBalancer
   ```

### CiliumBGPNodeConfig not created

1. Check node labels:
   ```bash
   kubectl get nodes --show-labels | grep kubernetes.io/os
   ```
2. Check Cilium operator logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=cilium-operator --tail=50
   ```

---

## Next Steps

Proceed to [03-UDM-Changes.md](./03-UDM-Changes.md) to configure BGP on the UDM Pro.
