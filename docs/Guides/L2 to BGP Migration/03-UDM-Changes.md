---
description: FRR BGP configuration for UniFi UDM Pro
tags: ["UDM", "FRR", "BGP", "UniFi"]
audience: ["Humans"]
categories: ["How-To[100%]", "Networking[90%]"]
---

# UDM Pro BGP Configuration

This document covers configuring BGP on the UniFi UDM Pro to peer with the Kubernetes cluster.

---

## Prerequisites

- [ ] UDM Pro running UniFi OS 4.1.13+ (current: 4.4.6)
- [ ] Admin access to UniFi Network UI
- [ ] SSH access to UDM (`ssh unifi`)

### Verify UniFi OS Version

```bash
ssh unifi "ubnt-device-info firmware"
```

Expected: `4.1.13` or higher (current: 4.4.6)

---

## Current State

Check if BGP is currently enabled:

```bash
ssh unifi "cat /etc/frr/daemons | grep bgpd"
```

Current output:
```
bgpd=no
```

After configuration, this will be `bgpd=yes`.

---

## FRR Configuration File

Create a file named `k8s-bgp.conf` with the following content:

```
frr version 8.4
frr defaults datacenter
hostname UDM-Pro
log syslog informational
!
router bgp 65001
  bgp router-id 10.90.254.1
  no bgp ebgp-requires-policy
  !
  ! Kubernetes cluster nodes
  neighbor k8s peer-group
  neighbor k8s remote-as 65010
  neighbor k8s description Kubernetes Cluster Nodes
  neighbor k8s ebgp-multihop 2
  !
  neighbor 10.90.3.101 peer-group k8s
  neighbor 10.90.3.102 peer-group k8s
  neighbor 10.90.3.103 peer-group k8s
  !
  address-family ipv4 unicast
    neighbor k8s soft-reconfiguration inbound
    neighbor k8s route-map K8S-IN in
    neighbor k8s route-map DENY-ALL out
  exit-address-family
!
! Accept routes from Kubernetes LB pool only
ip prefix-list K8S-LB-POOL seq 10 permit 10.90.3.0/24 le 32
!
! Accept routes matching our LB pool
route-map K8S-IN permit 10
  match ip address prefix-list K8S-LB-POOL
!
! Deny all other inbound routes
route-map K8S-IN deny 20
!
! Don't advertise anything to Kubernetes
route-map DENY-ALL deny 10
!
```

---

## Understanding the Configuration

### Router Section

```
router bgp 65001
  bgp router-id 10.90.254.1
```

| Setting | Value | Why |
|---------|-------|-----|
| ASN | 65001 | UDM's AS number (private range) |
| router-id | 10.90.254.1 | UDM's own IP |

### Peer Group

```
neighbor k8s peer-group
neighbor k8s remote-as 65010
```

All three nodes share the same configuration via peer group `k8s`.

### Prefix List

```
ip prefix-list K8S-LB-POOL seq 10 permit 10.90.3.0/24 le 32
```

Only accept routes within the LoadBalancer IP range. The `le 32` allows individual /32 routes (single IPs).

### Route Maps

| Route Map | Direction | Purpose |
|-----------|-----------|---------|
| K8S-IN | Inbound | Accept only LB pool routes from K8s |
| DENY-ALL | Outbound | Don't advertise anything to K8s |

**Why DENY-ALL outbound?** The cluster doesn't need to learn routes from the UDM - it only needs to advertise its LoadBalancer IPs.

---

## Upload via UniFi UI

### Step 1: Access Settings

1. Open UniFi Network UI
2. Navigate to **Settings** → **Routing** → **BGP**

### Step 2: Create BGP Entry

1. Click **Add New**
2. Name: `kubernetes-cluster`
3. Upload the `k8s-bgp.conf` file
4. Click **Apply**

### Step 3: Verify Upload

The UI should show the BGP configuration is active.

---

## Verify via CLI

### Check BGP Daemon Status

```bash
ssh unifi "cat /etc/frr/daemons | grep bgpd"
```

Expected:
```
bgpd=yes
```

### Check BGP Summary

```bash
ssh unifi "vtysh -c 'show ip bgp summary'"
```

Expected output (once cluster CRDs are applied):
```
IPv4 Unicast Summary:
BGP router identifier 10.90.254.1, local AS number 65001
Neighbor        V   AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
10.90.3.101     4  65010    100       100        0    0    0 00:05:00            2
10.90.3.102     4  65010    100       100        0    0    0 00:05:00            2
10.90.3.103     4  65010    100       100        0    0    0 00:05:00            2
```

**State/PfxRcd** should show a number (routes received), not `Active` or `Connect`.

### Check Received Routes

```bash
ssh unifi "vtysh -c 'show ip bgp'"
```

Expected:
```
   Network          Next Hop            Metric LocPrf Weight Path
*> 10.90.3.201/32   10.90.3.102              0             0 65010 i
*> 10.90.3.202/32   10.90.3.102              0             0 65010 i
```

### Check Routing Table

```bash
ssh unifi "vtysh -c 'show ip route bgp'"
```

Expected:
```
B>* 10.90.3.201/32 [20/0] via 10.90.3.102, br0, 00:05:00
B>* 10.90.3.202/32 [20/0] via 10.90.3.102, br0, 00:05:00
```

The `B>*` indicates BGP-learned routes that are installed in the routing table.

---

## Troubleshooting

### Sessions Stuck in "Active" or "Connect"

1. **Check TCP 179 connectivity**:
   ```bash
   # From a K8s node
   nc -zv 10.90.254.1 179
   ```

2. **Check UDM firewall**:
   BGP uses TCP 179. Ensure no firewall rules blocking it between nodes and UDM.

3. **Check ASN mismatch**:
   ```bash
   ssh unifi "vtysh -c 'show ip bgp neighbor 10.90.3.101'"
   ```
   Look for ASN negotiation issues.

### No Routes Received

1. **Check cluster-side BGP**:
   ```bash
   cilium bgp peers
   cilium bgp routes
   ```

2. **Check prefix-list match**:
   Ensure advertised routes are within 10.90.3.0/24.

### Routes Not in Routing Table

1. **Check route-map**:
   ```bash
   ssh unifi "vtysh -c 'show route-map K8S-IN'"
   ```

2. **Check prefix-list**:
   ```bash
   ssh unifi "vtysh -c 'show ip prefix-list K8S-LB-POOL'"
   ```

---

## Useful Commands Reference

| Command | Purpose |
|---------|---------|
| `vtysh -c 'show ip bgp summary'` | BGP peer status |
| `vtysh -c 'show ip bgp'` | All BGP routes |
| `vtysh -c 'show ip bgp neighbor X.X.X.X advertised-routes'` | Routes we send to peer |
| `vtysh -c 'show ip bgp neighbor X.X.X.X received-routes'` | Routes peer sends us |
| `vtysh -c 'show ip route bgp'` | BGP routes in routing table |
| `vtysh -c 'show running-config'` | Current FRR config |

---

## Removing BGP Configuration

If you need to remove BGP:

1. Go to **Settings** → **Routing** → **BGP**
2. Delete the `kubernetes-cluster` entry
3. BGP daemon will be disabled

---

## Next Steps

Proceed to [04-Test-Plan.md](./04-Test-Plan.md) to verify the migration is working.
