# Migrating from L2 to BGP: A Step-by-Step Guide

A beginner-friendly guide to migrating Kubernetes LoadBalancer services from Layer 2 (L2) announcements to BGP routing.

---

## What You'll Learn

By the end of this guide, you'll understand:
- What L2 and BGP mean and why they matter
- Why BGP is better for homelab Kubernetes clusters
- How to configure BGP on both your cluster and router
- How to verify everything is working

**Time required**: About 30-60 minutes

**Difficulty**: Intermediate (but we'll explain everything)

**Workflow**: This guide follows GitOps practices. You'll edit files in your repository and push to git - Flux (or ArgoCD) will apply the changes to your cluster automatically. No `kubectl apply` needed!

---

## Before You Begin

### What You Need

> [!WARNING]
> This guide assumes you are running a Unifi UDM Pro. If you are not, you will need to determine how to replicate the same steps on a different router.

- [ ] A Kubernetes cluster running Cilium (version 1.14 or newer)
- [ ] A UniFi Dream Machine Pro (UDM Pro) with firmware 4.1.13 or newer
- [ ] `kubectl` access to your cluster
- [ ] SSH access to your UDM Pro
- [ ] Basic familiarity with editing YAML files
- [ ] [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)

### Check Your Versions

**Check Cilium version:**
```bash
cilium version
```
You need version 1.14.0 or higher.

**Check UDM firmware:**
```bash
ssh root@YOUR_UDM_IP "ubnt-device-info firmware"
```
You need version 4.1.13 or higher (this added BGP support).

---

## Part 1: Understanding the Concepts

### What is a LoadBalancer Service?

When you create a Kubernetes service of type `LoadBalancer`, it gets an IP address that devices on your network can use to reach that service. For example:
- Your home dashboard might be at `10.99.8.201`
- Your media server might be at `10.99.8.202`

The question is: **How does traffic from your laptop find its way to the right Kubernetes node?**

### The Two Approaches

#### Approach 1: L2 Announcements (What You Probably Have Now)

**How it works:**
1. One Kubernetes node "claims" each LoadBalancer IP
2. When your laptop asks "where is 10.99.8.201?", that node responds "send it to me!"
3. The node receives the traffic and forwards it to the right pod

**The problem - "Hairpin Routing":**
```
Your laptop: "Where is 10.99.8.201?"
Node A: "I have it! Send traffic to me."
                    ↓
         Traffic goes to Node A
                    ↓
         But the actual app is on Node B!
                    ↓
         Node A tries to forward to Node B...
                    ↓
         Sometimes this fails! 😢
```

When a pod on the same node that "owns" the IP tries to reach that IP, traffic gets confused and fails. This is called "hairpin routing."

**Real example**: Your monitoring dashboard (Grafana) needs to talk to your login system (at 10.99.8.202). If both happen to be on the same node, the connection times out.

#### Approach 2: BGP (What We're Moving To)

**How it works:**
1. Each node tells your router: "I can handle traffic for these IPs"
2. Your router keeps a list of which node handles which IP
3. When traffic comes in, the router sends it directly to the right node

**Why it's better:**
```
Your laptop: sends traffic to 10.99.8.201
                    ↓
         Router checks its list:
         "10.99.8.201 → send to Node B"
                    ↓
         Traffic goes directly to Node B
                    ↓
         Works every time! 🎉
```

No more hairpin problems because the router makes all the routing decisions.

### Quick Glossary

| Term | Plain English |
|------|---------------|
| **BGP** | A way for routers to share information about which networks they can reach |
| **ASN** | A unique ID number for a network (like a phone area code) |
| **Peer** | Two devices that share BGP information with each other |
| **L2/Layer 2** | Network communication using MAC addresses (like ARP) |
| **L3/Layer 3** | Network communication using IP addresses (like routing) |
| **Hairpin** | When traffic has to "turn around" on the same device - often fails |

---

## Part 2: Planning Your Setup

### Choose Your IP Addresses

You'll need to decide on a few things:

#### 1. LoadBalancer IP Range

This is the range of IPs that Kubernetes will assign to your services.

**Recommendation**: Use a separate subnet/VLAN from your nodes to avoid conflicts.

| What | Example Value | Your Value |
|------|---------------|------------|
| LoadBalancer range | `10.99.8.0/24` | __________ |
| First usable IP | `10.99.8.1` | __________ |
| Last usable IP | `10.99.8.254` | __________ |

#### 2. ASN Numbers

These are just ID numbers. Pick any two different numbers from the private range (64512-65534).

| Device | Example ASN | Your Value |
|--------|-------------|------------|
| Your router (UDM) | `65001` | __________ |
| Your K8s cluster | `65010` | __________ |

#### 3. IP Addresses

| Device | Example IP | Your Value |
|--------|------------|------------|
| UDM Pro | `10.90.254.1` | __________ |
| Node 1 | `10.90.3.101` | __________ |
| Node 2 | `10.90.3.102` | __________ |
| Node 3 | `10.90.3.103` | __________ |

---

## Part 3: Configure Your Kubernetes Cluster

### Step 3.1: Verify BGP is Enabled in Cilium

First, check that Cilium has BGP support enabled:

```bash
kubectl get configmap -n kube-system cilium-config -o yaml | grep -i bgp
```

You should see `enable-bgp-control-plane: "true"`. If not, you'll need to enable it in your Cilium Helm values.

### Step 3.2: Create the BGP Configuration File

Create a new file called `networking.yaml`. This file tells Cilium:
- What IPs to advertise via BGP
- How to connect to your router
- What IP range to use for LoadBalancer services

```yaml
---
# Part 1: What to advertise
# This tells Cilium to announce all LoadBalancer IPs via BGP
apiVersion: cilium.io/v2
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
# Part 2: How to talk to the router
# This configures the BGP session settings
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: udm-peer
spec:
  timers:
    holdTimeSeconds: 90       # How long to wait before assuming router is dead
    keepAliveTimeSeconds: 30  # How often to send "I'm still here" messages
  gracefulRestart:
    enabled: true             # Don't drop connections during Cilium restarts
    restartTimeSeconds: 120
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp

---
# Part 3: Who to peer with
# This tells each node to connect to your UDM
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-cluster
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux  # Apply to all Linux nodes
  bgpInstances:
    - name: "home-cluster"
      localASN: 65010          # YOUR cluster's ASN - change if needed
      peers:
        - name: "udm-pro"
          peerAddress: "10.90.254.1"  # YOUR UDM's IP - change this!
          peerASN: 65001              # YOUR UDM's ASN - change if needed
          peerConfigRef:
            name: udm-peer

---
# Part 4: IP pool for LoadBalancer services
# This defines what IPs Kubernetes can assign to services
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: lb-pool
spec:
  allowFirstLastIPs: "No"  # Don't use .0 or .255
  blocks:
    - cidr: "10.99.8.0/24"  # YOUR LoadBalancer range - change this!
```

### Step 3.3: Add to Your Repository

Place the file in your Cilium app directory:
```
kubernetes/apps/kube-system/cilium/app/networking.yaml
```

Add it to your kustomization if needed:
```yaml
# kubernetes/apps/kube-system/cilium/app/kustomization.yaml
resources:
  - helmrelease.yaml
  - networking.yaml   # Add this line
```

### Step 3.4: Commit and Push

```bash
git add kubernetes/apps/kube-system/cilium/
git commit -m "feat(cilium): add BGP configuration for LoadBalancer IPs"
git push
```

### Step 3.5: Wait for Flux to Reconcile

Flux will automatically apply your changes. You can watch the progress:

```bash
# Watch Flux apply the changes
flux get kustomizations --watch

# Or force an immediate reconcile
flux reconcile kustomization cilium --with-source
```

### Step 3.6: Verify the Resources Were Created

Check each resource was created:

```bash
echo "=== BGP Advertisement ==="
kubectl get ciliumbgpadvertisement

echo "=== BGP Peer Config ==="
kubectl get ciliumbgppeerconfig

echo "=== BGP Cluster Config ==="
kubectl get ciliumbgpclusterconfig

echo "=== LoadBalancer IP Pool ==="
kubectl get ciliumloadbalancerippool
```

You should see one of each resource listed.

### Step 3.7: Check BGP Status (It Won't Work Yet!)

```bash
cilium bgp peers
```

You'll probably see the sessions in "active" state (not "established"). That's expected - we haven't configured the router yet!

```
Node         Local AS   Peer AS   Peer Address    Session State   Uptime
node-1       65010      65001     10.90.254.1     active          -
node-2       65010      65001     10.90.254.1     active          -
node-3       65010      65001     10.90.254.1     active          -
```

---

## Part 4: Configure Your UDM Pro

Now we need to tell your router to accept BGP connections from your Kubernetes nodes.

### Step 4.1: Create the Router Configuration File

Create a file called `k8s-bgp.conf` on your local machine:

```
router bgp 65001
 no bgp ebgp-requires-policy
 neighbor k8s peer-group
 neighbor k8s remote-as 65010
 neighbor 10.90.3.101 peer-group k8s
 neighbor 10.90.3.102 peer-group k8s
 neighbor 10.90.3.103 peer-group k8s
 !
 address-family ipv4 unicast
  neighbor k8s activate
  neighbor k8s soft-reconfiguration inbound
  neighbor k8s prefix-list k8s-services in
 exit-address-family
!
ip prefix-list k8s-services seq 10 permit 10.99.8.0/24 le 32
```

**What each part means:**

| Line | What It Does |
|------|--------------|
| `router bgp 65001` | Start BGP with ASN 65001 (your router's ID) |
| `neighbor k8s peer-group` | Create a group called "k8s" for all nodes |
| `neighbor k8s remote-as 65010` | Nodes use ASN 65010 |
| `neighbor 10.90.3.10X peer-group k8s` | Add each node to the group |
| `prefix-list k8s-services...` | Only accept routes in your LB range |

**Important**: Update the IP addresses to match YOUR nodes!

### Step 4.2: Upload to UDM via Web UI

1. Open your UniFi Network console in a browser
2. Go to **Settings** → **Routing** → **BGP**
3. Click **Add New** or **Create New**
4. Give it a name like `kubernetes-cluster`
5. Upload your `k8s-bgp.conf` file
6. Click **Apply**

### Step 4.3: Verify BGP is Running on UDM

SSH into your UDM and check:

```bash
ssh root@YOUR_UDM_IP
```

Then run:

```bash
vtysh -c "show ip bgp summary"
```

You should see something like:

```
IPv4 Unicast Summary:
BGP router identifier 10.90.254.1, local AS number 65001

Neighbor        V    AS MsgRcvd MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
10.90.3.101     4 65010      50      50        0    0    0 00:05:00            2
10.90.3.102     4 65010      50      50        0    0    0 00:05:00            2
10.90.3.103     4 65010      50      50        0    0    0 00:05:00            2
```

**What to look for:**
- `State/PfxRcd` should show a number (routes received), NOT "Active" or "Connect"
- `Up/Down` should show a time, indicating the session is established

---

## Part 5: Verify Everything Works

### Step 5.1: Check BGP Sessions from Kubernetes

Back on your machine with kubectl access:

```bash
cilium bgp peers
```

Now you should see "established" instead of "active":

```
Node         Local AS   Peer AS   Peer Address    Session State   Uptime
node-1       65010      65001     10.90.254.1     established     5m
node-2       65010      65001     10.90.254.1     established     5m
node-3       65010      65001     10.90.254.1     established     5m
```

**✅ Checkpoint**: All sessions show "established"? Great! Move to the next step.

### Step 5.2: Check Routes on UDM

SSH to your UDM and check what routes it learned:

```bash
vtysh -c "show ip route bgp"
```

You should see your LoadBalancer IPs:

```
B>* 10.99.8.201/32 [20/0] via 10.90.3.102, br0
B>* 10.99.8.202/32 [20/0] via 10.90.3.101, br0
```

**What this means:**
- `B>*` = BGP route, best route, installed in routing table
- `10.99.8.201/32` = The LoadBalancer IP
- `via 10.90.3.102` = Send traffic to this node

**✅ Checkpoint**: You see routes with `B>*`? Perfect!

### Step 5.3: Test Connectivity

The real test - can you reach your services?

**From your laptop/desktop:**
```bash
# Replace with one of your actual LoadBalancer IPs
curl -k https://10.99.8.202 --connect-timeout 5
```

You should get a response (might be an error page, but that's fine - it connected!).

**From inside the cluster (the hairpin test):**
```bash
# This creates a temporary pod and tests connectivity
kubectl run test-bgp --rm -i --restart=Never --image=busybox \
  -- nc -zv -w 5 10.99.8.202 443
```

You should see:
```
10.99.8.202 (10.99.8.202:443) open
```

**✅ Checkpoint**: Both tests succeed? BGP is working!

---

## Part 6: Clean Up (Optional)

If you had L2 announcements configured before, you can now remove them.

### Remove L2-Related Resources

```bash
# Check if you have any L2 policies
kubectl get ciliuml2announcementpolicy

# If you do, delete them
kubectl delete ciliuml2announcementpolicy --all
```

### Remove Node Pinning Workarounds

If you had pods pinned to specific nodes to work around hairpin issues, you can remove those `nodeSelector` constraints now.

---

## Troubleshooting

### Problem: Sessions Stuck in "Active"

**Symptoms**: `cilium bgp peers` shows "active" instead of "established"

**Check 1**: Can your nodes reach the UDM on port 179?
```bash
# From a node (or a debug pod)
nc -zv 10.90.254.1 179
```

If this fails, check:
- Firewall rules on UDM
- Network connectivity between nodes and UDM

**Check 2**: Is BGP enabled on the UDM?
```bash
ssh root@YOUR_UDM_IP "cat /etc/frr/daemons | grep bgpd"
```

Should show `bgpd=yes`.

**Check 3**: Do the ASN numbers match?
- Cluster config says UDM is ASN 65001
- UDM config says cluster is ASN 65010
- Make sure these match what you configured!

### Problem: No Routes Showing on UDM

**Symptoms**: BGP sessions are established but `show ip route bgp` is empty

**Check 1**: Do you have LoadBalancer services?
```bash
kubectl get svc -A | grep LoadBalancer
```

If no services have LoadBalancer IPs, there's nothing to advertise.

**Check 2**: Is the IP pool configured?
```bash
kubectl get ciliumloadbalancerippool
```

**Check 3**: Check what Cilium is advertising:
```bash
cilium bgp routes advertised ipv4 unicast
```

### Problem: Traffic Not Reaching Services

**Symptoms**: BGP looks good but `curl` times out

**Check 1**: Is the route installed on UDM?
```bash
ssh root@YOUR_UDM_IP "vtysh -c 'show ip route 10.99.8.201'"
```

**Check 2**: Is the pod running?
```bash
kubectl get pods -A -o wide | grep YOUR_APP
```

**Check 3**: Check the service:
```bash
kubectl get svc -A | grep YOUR_SERVICE_IP
```

---

## Quick Reference

### Commands You'll Use Often

| Task | Command |
|------|---------|
| Check BGP peers | `cilium bgp peers` |
| Check advertised routes | `cilium bgp routes advertised ipv4 unicast` |
| Check UDM BGP summary | `ssh root@UDM "vtysh -c 'show ip bgp summary'"` |
| Check UDM routes | `ssh root@UDM "vtysh -c 'show ip route bgp'"` |
| List LoadBalancer services | `kubectl get svc -A \| grep LoadBalancer` |

### Your Configuration Values

Fill this in for future reference:

| Setting | Value |
|---------|-------|
| UDM IP | _____________ |
| UDM ASN | _____________ |
| Cluster ASN | _____________ |
| LoadBalancer CIDR | _____________ |
| Node 1 IP | _____________ |
| Node 2 IP | _____________ |
| Node 3 IP | _____________ |

---

## What's Next?

Now that BGP is working:

1. **Add more services**: Any new LoadBalancer service will automatically get a BGP route
2. **Monitor BGP**: Set up alerts for BGP session failures
3. **Learn about Gateway API**: See the [Gateway API Routing Guide](../gateway-api-routing/README.md) to expose your services via HTTP/HTTPS

> [!WARNING]
> **DSR Hairpin Limitation**: If you're using Cilium's DSR (Direct Server Return) mode, be aware that BGP doesn't solve all hairpin scenarios. When a pod tries to reach a LoadBalancer VIP and the backend is on the *same node*, traffic can fail. This is a known Cilium limitation ([GitHub #39198](https://github.com/cilium/cilium/issues/39198)). The workaround is CoreDNS rewriting to return ClusterIP for pod-to-service traffic. See the [Dual-Homing Access Patterns Guide](../Dual-Homing%20Access%20Patterns/README.md) for more details on internal traffic routing.

---

## Further Reading

- [Cilium BGP Documentation](https://docs.cilium.io/en/stable/network/bgp-control-plane/)
- [What is BGP? (Cloudflare)](https://www.cloudflare.com/learning/security/glossary/what-is-bgp/)
- [UniFi BGP Setup](https://help.ui.com/hc/en-us/articles/16271338193559)
