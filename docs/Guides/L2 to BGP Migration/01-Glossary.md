---
description: Plain-language explanations of networking terms used in the L2 to BGP migration
tags: ["BGP", "L2", "ARP", "ASN", "eBGP", "FRR", "LoadBalancer"]
audience: ["Humans"]
categories: ["Reference[100%]", "Networking[100%]"]
---

# Networking Glossary

Terms explained in the context of this homelab, not academic definitions.

---

## Layer 2 (L2) Concepts

### ARP (Address Resolution Protocol)

**What it does**: Maps IP addresses to MAC addresses on the local network.

**In this context**: When a device wants to reach 10.90.3.202, it broadcasts "who has this IP?" The node holding the L2 lease responds with its MAC address, saying "send traffic to me."

**Analogy**: Shouting in a room "who is John?" and John raises his hand.

---

### L2 Announcement

**What it does**: Cilium claims ownership of a LoadBalancer IP by responding to ARP requests.

**In this context**: One Kubernetes node "claims" each LoadBalancer IP. All traffic for that IP goes to that node, which then forwards to the actual backend pod.

**The problem**: If the backend pod is on a different node than the one claiming the IP, traffic has to hop between nodes. If a pod on the claiming node tries to reach the IP, it gets confused (hairpin routing failure).

---

### Hairpin Routing

**What it does**: Traffic that needs to "turn around" and go back out the same interface it came in.

**In this context**: Pod on stanton-03 → tries to reach 10.90.3.202 → stanton-03 owns that IP via L2 → but backend is on stanton-02 → traffic fails because Cilium can't route it back out.

**Analogy**: You're in a building, trying to call someone in the same building, but the phone system routes your call outside to the phone company and back in. The phone company doesn't know how to route it back.

---

### L2 Lease

**What it does**: Kubernetes Lease object that tracks which node currently "owns" a LoadBalancer IP for L2 announcements.

**In this context**: `kubectl get lease -n kube-system cilium-l2announce-network-envoy-internal` shows which node responds to ARP for that IP.

---

## Layer 3 (L3) / BGP Concepts

### BGP (Border Gateway Protocol)

**What it does**: Protocol for routers to share routing information. "I can reach network X, send traffic for X to me."

**In this context**: Each Kubernetes node tells the UDM Pro "I can reach 10.90.3.201" or "I can reach 10.90.3.202." The UDM learns the routes and sends traffic directly to the correct node.

**Why it solves the hairpin problem**: The UDM Pro handles all routing decisions. Pods don't need to go through L2/ARP - they just send packets to the UDM, which routes them correctly.

**Analogy**: Instead of shouting "who is John?" in a room, you check a directory that tells you exactly which desk John sits at.

---

### ASN (Autonomous System Number)

**What it does**: A unique identifier for a group of networks under common administrative control.

**In this context**:
- UDM Pro: ASN 65001
- All K8s nodes: ASN 65010

Private ASN range is 64512-65534. We use two different ASNs (eBGP) so routing is simpler.

**Analogy**: Like area codes in phone numbers. Each "area" (AS) has its own number.

---

### eBGP vs iBGP

**eBGP (External BGP)**: BGP between different ASNs. Simpler - each neighbor is clearly "outside."

**iBGP (Internal BGP)**: BGP within the same ASN. Requires route reflectors or full mesh.

**In this context**: We use eBGP (UDM is ASN 65001, cluster is ASN 65010) because it's simpler for this topology.

---

### BGP Peer / Neighbor

**What it does**: Two routers that exchange BGP information with each other.

**In this context**: The UDM Pro peers with each of the three Kubernetes nodes. Each node tells the UDM which LoadBalancer IPs it can reach.

---

### Route Advertisement

**What it does**: A BGP speaker announces "I can reach network X."

**In this context**: When a LoadBalancer service gets IP 10.90.3.201, the node running the backend pod advertises "send 10.90.3.201/32 to me" to the UDM.

---

### FRR (FRRouting)

**What it does**: Open-source routing software suite that handles BGP, OSPF, and other protocols.

**In this context**: The UDM Pro uses FRR internally. You configure BGP by uploading an FRR config file.

---

### Router ID

**What it does**: Unique identifier for a BGP router, typically an IP address.

**In this context**:
- UDM Pro router ID: 10.90.254.1 (its own IP)
- K8s nodes use their node IPs (10.90.3.101, etc.)

---

## Cilium-Specific Terms

### CiliumBGPClusterConfig

**What it does**: Defines which nodes participate in BGP and what peers they connect to.

**In this context**: Tells all nodes with `kubernetes.io/os: linux` to peer with the UDM at 10.90.254.1.

---

### CiliumBGPPeerConfig

**What it does**: Defines BGP session parameters (timers, authentication, address families).

**In this context**: Sets hold time to 90 seconds, keepalive to 30 seconds, enables graceful restart.

---

### CiliumBGPAdvertisement

**What it does**: Defines what gets advertised via BGP (pod CIDRs, service IPs, etc.).

**In this context**: Advertises LoadBalancer IPs so the UDM knows how to reach them.

---

### CiliumLoadBalancerIPPool

**What it does**: Pool of IPs that Cilium assigns to LoadBalancer services.

**In this context**: 10.90.3.0/24 - services get IPs from this range.

---

## UDM-Specific Terms

### UniFi OS

**What it does**: Operating system running on UDM Pro.

**In this context**: Version 4.1.13+ supports native BGP via FRR. Current version: 4.4.6.

---

### vtysh

**What it does**: CLI tool to interact with FRR routing daemons.

**In this context**: SSH to UDM and run `vtysh -c "show ip bgp"` to see BGP routes.

---

## Quick Reference Table

| Term | One-liner |
|------|-----------|
| ARP | "Who has this IP?" broadcast on local network |
| L2 Announcement | Cilium responds to ARP for LoadBalancer IPs |
| Hairpin | Traffic loops back to same node, fails |
| BGP | Routers share "I can reach network X" info |
| ASN | Unique ID for a group of networks |
| eBGP | BGP between different ASNs |
| Peer | Two BGP routers exchanging routes |
| FRR | Routing software on UDM Pro |
| Advertisement | "Send traffic for X to me" message |

---

## Visual: L2 vs BGP Traffic Flow

```
L2 ANNOUNCEMENT FLOW:
┌─────────┐     ARP: "Who has 10.90.3.202?"     ┌─────────────┐
│  Client │ ──────────────────────────────────► │ stanton-03  │
└─────────┘                                     │ (L2 lease)  │
                                                └──────┬──────┘
                                                       │ Forward
                                                       ▼
                                                ┌─────────────┐
                                                │ stanton-02  │
                                                │ (backend)   │
                                                └─────────────┘

Problem: If client IS stanton-03, it can't reach the backend.


BGP FLOW:
┌─────────┐                                     ┌─────────────┐
│  Client │ ───────────────────────────────────►│   UDM Pro   │
└─────────┘                                     │  (router)   │
                                                └──────┬──────┘
                                                       │ Route lookup:
                                                       │ 10.90.3.202 → stanton-02
                                                       ▼
                                                ┌─────────────┐
                                                │ stanton-02  │
                                                │ (backend)   │
                                                └─────────────┘

Solution: UDM always knows where to send traffic.
```
