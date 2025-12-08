---
description: Migration guide for transitioning Kubernetes LoadBalancer IP advertisement from Cilium L2 to BGP
tags: ["BGP", "L2Announcements", "Cilium", "LoadBalancer", "UDM"]
audience: ["Humans"]
categories: ["How-To[100%]", "Networking[90%]"]
---

# L2 to BGP Migration Guide

This guide documents the migration from Cilium L2 Announcements to BGP Control Plane for LoadBalancer IP advertisement.

## Why Migrate?

### Capsule: L2HairpinLimitation

**Invariant**: Pods on the node holding the L2 lease cannot reach LoadBalancer IPs when the backend runs elsewhere.

**Example**:
- Grafana runs on stanton-03
- stanton-03 holds L2 lease for 10.90.3.202
- Envoy gateway pod runs on stanton-02
- Grafana's OIDC token request to 10.90.3.202 times out

**Depth**:
- Current workaround: Pin gateway pods to same node as L2 announcements (single point of failure)
- BGP eliminates this by routing through UDM Pro instead of L2/ARP

---

## Current State

| Component | Value |
|-----------|-------|
| Cilium Version | v1.18.3 |
| UDM Pro Firmware | 4.4.6 (BGP capable) |
| UDM Pro IP | 10.90.254.1 |
| LB IP Pool | 10.90.3.0/24 |
| External Gateway | 10.90.3.201 |
| Internal Gateway | 10.90.3.202 |

### Kubernetes Nodes

| Hostname | IP |
|----------|-----|
| stanton-01 | 10.90.3.101 |
| stanton-02 | 10.90.3.102 |
| stanton-03 | 10.90.3.103 |

---

## Migration Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        BEFORE (L2)                              │
├─────────────────────────────────────────────────────────────────┤
│  Client → ARP → Node holding lease → Forward to backend node    │
│                                                                 │
│  Problem: Hairpin routing fails when client is on lease node    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        AFTER (BGP)                              │
├─────────────────────────────────────────────────────────────────┤
│  Client → UDM Pro → Route to correct node → Backend pod         │
│                                                                 │
│  Benefit: UDM knows which node has the backend, no hairpin      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Guide Structure

| Document | Purpose |
|----------|---------|
| [01-Glossary.md](./01-Glossary.md) | Networking terms explained simply |
| [02-Cluster-Changes.md](./02-Cluster-Changes.md) | Cilium BGP CRDs to deploy |
| [03-UDM-Changes.md](./03-UDM-Changes.md) | FRR config for UDM Pro |
| [04-Test-Plan.md](./04-Test-Plan.md) | Verification steps |
| [05-Rollback.md](./05-Rollback.md) | How to revert if needed |

---

## Quick Reference: ASN Assignment

| Entity | ASN | Role |
|--------|-----|------|
| UDM Pro | 65001 | Upstream router |
| All K8s Nodes | 65010 | Cluster |

Using eBGP (different ASNs) for simplicity - no route reflector needed.

---

## Prerequisites Checklist

- [ ] UDM Pro running UniFi OS 4.1.13+ (current: 4.4.6)
- [ ] Cilium `bgpControlPlane.enabled: true` (already configured)
- [ ] SSH access to UDM Pro (`ssh unifi`)
- [ ] kubectl access to cluster

---

## Impact Assessment

### What Changes

| Traffic Type | Before | After |
|--------------|--------|-------|
| Pod → LB IP | L2/ARP (hairpin issues) | Routed via UDM |
| External → LB IP | L2/ARP | Routed via UDM |

### What Stays the Same

- All client devices (phones, laptops, etc.) - no config changes
- DNS resolution
- DHCP
- VLANs
- Firewall rules
- Application configurations

---

## Execution Order

1. **Read** [01-Glossary.md](./01-Glossary.md) to understand terms
2. **Deploy** cluster changes per [02-Cluster-Changes.md](./02-Cluster-Changes.md)
3. **Configure** UDM per [03-UDM-Changes.md](./03-UDM-Changes.md)
4. **Verify** using [04-Test-Plan.md](./04-Test-Plan.md)
5. **If issues** follow [05-Rollback.md](./05-Rollback.md)

---

## Success Criteria

After migration:
- `cilium bgp peers` shows established sessions to 10.90.254.1
- Pods on any node can reach gateway LB IPs
- No nodeSelector pins required on gateway pods
- Gateway pods can schedule on any node

---

## References

- [Cilium BGP Control Plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/)
- [Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/)
- [UniFi BGP Documentation](https://help.ui.com/hc/en-us/articles/16271338193559-UniFi-Border-Gateway-Protocol-BGP)
