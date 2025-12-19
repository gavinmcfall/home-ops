# Cilium Configuration Changelog

## 2024-12: BGP Migration

Migration from L2 announcements to BGP for LoadBalancer IP advertisement.

## Summary of Changes

### Structure Changes

- **Removed**: `config/` folder (separate Kustomization)
- **Added**: `app/networking.yaml` (BGP + LB pool CRDs consolidated)
- **Removed**: `cilium-config` Kustomization from `ks.yaml`

### L2 to BGP Migration

| Before | After |
|--------|-------|
| CiliumL2AnnouncementPolicy | CiliumBGPAdvertisement |
| L2 ARP-based announcements | BGP route advertisements |
| Hairpin routing issues | Proper routing via UDM |
| Gateway pods pinned to stanton-02 | Pods can schedule anywhere |

### Helm Values Changes

| Setting | Before | After | Why |
|---------|--------|-------|-----|
| `l2announcements.enabled` | `true` | **removed** | No longer using L2 |
| `loadBalancer.mode` | `snat` | `dsr` | Direct Server Return - better performance, preserves client IP |
| `bpf.datapathMode` | (default) | `netkit` | Modern eBPF datapath, better performance |
| `enableIPv4BIGTCP` | (default) | `true` | Allows larger TCP segments, improves throughput |
| `pmtuDiscovery.enabled` | (default) | `true` | Auto-discovers optimal MTU |

### Envoy Gateway Changes

- **Removed**: `cilium-l2-policy.yaml` (L2 policy for gateway services)
- **Removed**: `nodeSelector` pins from both `internal/envoyproxy.yaml` and `external/envoyproxy.yaml`
- Gateway pods can now schedule on any node (BGP handles routing)

#### Why We Had These Workarounds

**The Problem: Hairpin Routing with L2 Announcements**

With L2 announcements, one node "owns" a LoadBalancer IP via ARP. When a pod on that same node tried to reach the LoadBalancer IP (e.g., Grafana → OIDC endpoint at 10.90.3.202), the traffic would:

1. Leave the pod toward the LoadBalancer IP
2. Hit the node's network stack
3. Get "hairpinned" back because the node owns that IP
4. Fail because the traffic path breaks

**The Workaround:**

1. **nodeSelector on EnvoyProxy**: Pin gateway pods to stanton-02
2. **CiliumL2AnnouncementPolicy**: Force the L2 lease for gateway services to stanton-02
3. This ensured the gateway pods and their L2 announcements were always colocated

**Why BGP Fixes This:**

With BGP, the UDM Pro learns routes to LoadBalancer IPs and handles routing at L3. Traffic flow becomes:

1. Pod sends packet to LoadBalancer IP
2. Packet goes to default gateway (UDM Pro)
3. UDM routes to the correct node based on BGP advertisements
4. No hairpin - traffic always goes through the router

Since the router handles routing decisions (not ARP), pods on any node can reach any LoadBalancer IP regardless of where the backend runs. Gateway pods can now schedule anywhere.

---

## Helm Values Explained

### `loadBalancer.mode: dsr` (Direct Server Return)

With SNAT, return traffic goes: Pod → Node → Client
With DSR, return traffic goes: Pod → Client (directly)

Benefits:
- Lower latency (fewer hops)
- Preserves original client IP
- Reduces load on ingress node

### `bpf.datapathMode: netkit`

Modern eBPF-based datapath that replaces the legacy veth-based approach.

Benefits:
- Better performance for pod-to-pod traffic
- Lower CPU overhead
- Required for some advanced features

### `enableIPv4BIGTCP: true`

Allows TCP segments larger than 64KB (up to 4GB with GSO/GRO).

Benefits:
- Higher throughput for large transfers
- Reduced CPU overhead (fewer packets to process)

### `pmtuDiscovery.enabled: true`

Path MTU Discovery automatically finds the optimal packet size for each route.

Benefits:
- Avoids fragmentation
- Better performance across different network paths

---

## Differences from Kashalls' Setup

| Setting | Ours | Kashalls | Reason |
|---------|------|----------|--------|
| `devices` | `bond0` | (not set) | We use bonded NICs |
| `cluster.name` | `home-kubernetes` | `main` | Different naming |
| `ipv4NativeRoutingCIDR` | `10.69.0.0/16` | `172.30.0.0/16` | Different pod CIDR |
| BGP timers | Explicit (90s/30s) | Defaults | More predictable failover |
| Graceful restart | Enabled | Not set | Smoother Cilium upgrades |
| ASNs | 65010/65001 | 64514/64513 | Different private ASN choices |

---

## BGP Configuration Details

### Our Setup

```
Cluster ASN: 65010
UDM Pro ASN: 65001
Peer Address: 10.90.254.1
LB Pool: 10.99.8.0/24 (Services VLAN)
```

### CRDs Created

1. **CiliumBGPAdvertisement** (`lb-services`)
   - Advertises LoadBalancer IPs via BGP
   - All services advertised unless labeled `io.cilium/bgp-announce: "false"`

2. **CiliumBGPPeerConfig** (`udm-peer`)
   - Hold time: 90s (peer failure detection)
   - Keepalive: 30s
   - Graceful restart enabled (120s)

3. **CiliumBGPClusterConfig** (`bgp-cluster`)
   - All Linux nodes peer with UDM
   - Single BGP instance per node

4. **CiliumLoadBalancerIPPool** (`lb-pool`)
   - IP range: 10.99.8.0/24 (Services VLAN, DHCP disabled)
   - First/last IPs excluded
