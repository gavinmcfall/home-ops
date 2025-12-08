---
description: Verification steps for L2 to BGP migration
tags: ["Testing", "BGP", "Verification", "Connectivity"]
audience: ["Humans"]
categories: ["How-To[100%]", "Testing[90%]"]
---

# Test Plan for BGP Migration

Systematic verification that BGP is working correctly.

---

## Test Phases

| Phase | What | When |
|-------|------|------|
| Phase 1 | BGP Session Establishment | After UDM config |
| Phase 2 | Route Advertisement | After cluster CRDs |
| Phase 3 | Traffic Routing | After both sides configured |
| Phase 4 | Hairpin Resolution | Final validation |

---

## Phase 1: BGP Session Establishment

### Test 1.1: Cilium BGP Peers

**Command**:
```bash
cilium bgp peers
```

**Expected**:
```
Node         Local AS   Peer AS   Peer Address    Session State   Uptime
stanton-01   65010      65001     10.90.254.1     established     5m
stanton-02   65010      65001     10.90.254.1     established     5m
stanton-03   65010      65001     10.90.254.1     established     5m
```

**Pass criteria**: All three nodes show `established` state.

**If failing**: Check [03-UDM-Changes.md](./03-UDM-Changes.md) troubleshooting section.

---

### Test 1.2: UDM BGP Summary

**Command**:
```bash
ssh unifi "vtysh -c 'show ip bgp summary'"
```

**Expected**:
```
Neighbor        V   AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
10.90.3.101     4  65010    100       100        0    0    0 00:05:00            2
10.90.3.102     4  65010    100       100        0    0    0 00:05:00            2
10.90.3.103     4  65010    100       100        0    0    0 00:05:00            2
```

**Pass criteria**:
- All three neighbors showing
- `State/PfxRcd` shows a number (not `Active` or `Connect`)

---

## Phase 2: Route Advertisement

### Test 2.1: Cilium Advertised Routes

**Command**:
```bash
cilium bgp routes advertised ipv4 unicast
```

**Expected**: LoadBalancer IPs listed (10.90.3.201, 10.90.3.202).

---

### Test 2.2: UDM Received Routes

**Command**:
```bash
ssh unifi "vtysh -c 'show ip bgp'"
```

**Expected**:
```
   Network          Next Hop            Metric LocPrf Weight Path
*> 10.90.3.201/32   10.90.3.X              0             0 65010 i
*> 10.90.3.202/32   10.90.3.X              0             0 65010 i
```

**Pass criteria**: Both gateway IPs visible with valid next-hop.

---

### Test 2.3: UDM Routing Table

**Command**:
```bash
ssh unifi "vtysh -c 'show ip route bgp'"
```

**Expected**:
```
B>* 10.90.3.201/32 [20/0] via 10.90.3.X, br0
B>* 10.90.3.202/32 [20/0] via 10.90.3.X, br0
```

**Pass criteria**: Routes marked `B>*` (BGP, best, installed).

---

## Phase 3: Traffic Routing

### Test 3.1: External Connectivity

From your workstation (not on a K8s node):

**Command**:
```bash
curl -k -I https://10.90.3.202 --connect-timeout 5
```

**Expected**: HTTP response (may be 404, that's OK - connection succeeded).

**Pass criteria**: Response within 5 seconds, no timeout.

---

### Test 3.2: Pod Connectivity (Same Node as Gateway)

Find which node the gateway pod is on:
```bash
kubectl get pods -n network -l app.kubernetes.io/name=envoy -o wide
```

Create test pod on that same node:
```bash
NODE=$(kubectl get pods -n network -l app.kubernetes.io/name=envoy -o jsonpath='{.items[0].spec.nodeName}')
kubectl run bgp-test --rm -i --restart=Never \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$NODE\"}}}" \
  --image=busybox -- nc -zv -w 5 10.90.3.202 443
```

**Expected**:
```
10.90.3.202 (10.90.3.202:443) open
```

**Pass criteria**: Connection succeeds (this tests local routing).

---

### Test 3.3: Pod Connectivity (Different Node from Gateway)

Create test pod on a node that does NOT have the gateway pod:
```bash
# Find a different node
GATEWAY_NODE=$(kubectl get pods -n network -l app.kubernetes.io/name=envoy -o jsonpath='{.items[0].spec.nodeName}')
OTHER_NODE=$(kubectl get nodes -o name | grep -v "$GATEWAY_NODE" | head -1 | cut -d/ -f2)

kubectl run bgp-test-other --rm -i --restart=Never \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$OTHER_NODE\"}}}" \
  --image=busybox -- nc -zv -w 5 10.90.3.202 443
```

**Expected**:
```
10.90.3.202 (10.90.3.202:443) open
```

**Pass criteria**: Connection succeeds (this tests cross-node routing).

---

## Phase 4: Hairpin Resolution

This is the key test - the reason for migrating to BGP.

### Test 4.1: Pod on Any Node Can Reach Gateway

Run from each node:
```bash
for node in stanton-01 stanton-02 stanton-03; do
  echo "Testing from $node:"
  kubectl run hairpin-test-$node --rm -i --restart=Never \
    --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node\"}}}" \
    --image=busybox -- nc -zv -w 5 10.90.3.202 443 2>&1
done
```

**Expected**: All three succeed.

**Pass criteria**: No timeouts from any node.

---

### Test 4.2: Grafana OIDC Login

**Command**:
1. Open browser to `https://grafana.${SECRET_DOMAIN}`
2. Click "Sign in with Pocket ID"
3. Complete authentication

**Pass criteria**: Login succeeds without timeout errors.

**If failing**: Check Grafana logs:
```bash
kubectl logs -n observability deploy/grafana -c grafana --tail=20 | grep -i oidc
```

---

## Quick Verification Script

Run all tests at once:

```bash
#!/bin/bash
echo "=== Phase 1: BGP Sessions ==="
cilium bgp peers

echo ""
echo "=== Phase 2: Routes on UDM ==="
ssh unifi "vtysh -c 'show ip route bgp'"

echo ""
echo "=== Phase 3: Connectivity from each node ==="
for node in stanton-01 stanton-02 stanton-03; do
  echo -n "$node -> 10.90.3.202:443: "
  kubectl run test-$node --rm -i --restart=Never --quiet \
    --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node\"}}}" \
    --image=busybox -- nc -zv -w 5 10.90.3.202 443 2>&1 | grep -E "(open|timeout)"
done

echo ""
echo "=== Done ==="
```

---

## Success Criteria Summary

| Test | Result |
|------|--------|
| All BGP sessions established | [ ] |
| Routes visible on UDM | [ ] |
| External connectivity works | [ ] |
| Pod connectivity from gateway node | [ ] |
| Pod connectivity from other nodes | [ ] |
| Grafana OIDC login works | [ ] |

**All boxes checked = Migration successful**

---

## If Tests Fail

Proceed to [05-Rollback.md](./05-Rollback.md) for rollback procedures.
