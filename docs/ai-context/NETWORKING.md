---
description: Network architecture covering traffic flows, DNS, gateways, and authentication
tags: ["Cilium", "EnvoyGateway", "GatewayAPI", "DNS", "OIDC", "Cloudflare", "Tailscale", "SplitHorizon"]
audience: ["LLMs", "Humans"]
categories: ["Architecture[100%]", "Networking[100%]"]
---

# Networking Architecture

## Network Overview

![claude_network_overview](./images/claude_network_overview.png)

---

## IP Address Map

### Cluster LoadBalancer IPs (Cilium LB-IPAM)

| IP | Service | Purpose |
|----|---------|---------|
| 10.90.3.201 | external gateway | Public traffic ingress (via Cloudflare) |
| 10.90.3.202 | internal gateway | Private traffic ingress (LAN direct) |

### Node IPs

| IP | Hostname | Purpose |
|----|----------|---------|
| 10.90.3.101 | stanton-01 | Control plane node |
| 10.90.3.102 | stanton-02 | Control plane node |
| 10.90.3.103 | stanton-03 | Control plane node |

### Infrastructure IPs

| IP | Device | Purpose |
|----|--------|---------|
| 10.90.254.1 | UDM Pro | Router/DNS/Firewall |

---

## UDM Pro Manual DNS Records

These A records are manually configured in the UDM Pro:

| Record | IP | Purpose |
|--------|----|---------|
| `internal.${SECRET_DOMAIN}` | 10.90.3.202 | Points to internal gateway |
| `stanton-01.internal` | 10.90.3.101 | Node 1 direct access |
| `stanton-02.internal` | 10.90.3.102 | Node 2 direct access |
| `stanton-03.internal` | 10.90.3.103 | Node 3 direct access |

---

## Split-Horizon DNS

### Capsule: SplitHorizonDNS

**Invariant**: Same hostname resolves to different IPs based on client location. LAN clients get internal gateway IP; internet clients get Cloudflare IP. This eliminates hairpin NAT.

**How It Works**:

![claude_network_split_horizon_dns](./images/claude_network_split_horizon_dns.png)

**Components**:

| Component | Creates Records In | What It Watches |
|-----------|-------------------|-----------------|
| external-dns | Cloudflare | HTTPRoutes with `external-dns.alpha.kubernetes.io/target` annotation |
| external-dns-unifi | UDM Pro | ALL HTTPRoutes (no annotation filter) |

**Why This Avoids Hairpin NAT**:
- Without split-horizon: LAN client → Cloudflare → tunnel → cluster (hairpin)
- With split-horizon: LAN client → UDM DNS → internal gateway → cluster (direct)

---

## App Exposure Patterns

### Pattern 1: External Only (Internet Access)

Apps with only `external-dns.alpha.kubernetes.io/target` annotation.

**Example**: bentopdf (pdf.${SECRET_DOMAIN})

```yaml
route:
  app:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    parentRefs:
      - name: external
        namespace: network
```

**LAN Access Path**:
```
LAN Client → UDM DNS (no record) → Cloudflare DNS → Cloudflare edge →
cloudflared tunnel → external gateway (10.90.3.201) → App
```

### Pattern 2: Internal Only (LAN Access)

Apps with only `internal-dns.alpha.kubernetes.io/target` annotation.

**Example**: `unifi.${SECRET_DOMAIN}`, `truenas.${SECRET_DOMAIN}`

```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network
```

**LAN Access Path**:
```
LAN Client → UDM DNS → 10.90.3.202 → internal gateway → App
```

**Internet Access**: Not available (no Cloudflare record)

### Pattern 3: Dual-Homed (Both Internal and External)

Apps with BOTH annotations. Same hostname, different paths based on client location.

**Example**: pocket-id (id.${SECRET_DOMAIN})

```yaml
route:
  external:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - id.${SECRET_DOMAIN}
    parentRefs:
      - name: external
        namespace: network
  internal:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - id.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network
```

**Traffic Paths**:

| Client Location | DNS Response | Gateway | Path |
|-----------------|--------------|---------|------|
| Internet | Cloudflare IP | external (10.90.3.201) | Via tunnel |
| LAN | 10.90.3.202 | internal (10.90.3.202) | Direct |

---

## OIDC Authentication

### Capsule: EnvoyOIDC

**Invariant**: Envoy Gateway SecurityPolicy intercepts requests at the gateway, redirects to Pocket-ID for authentication, and only forwards authenticated requests to backends. Apps without native OIDC support get authentication for free.

### OIDC Flow

![claude_network_envoy_pocket-id_oidc](./images/claude_network_envoy_pocket-id_oidc.png)

### Example: bentopdf OIDC Protection

bentopdf has no native authentication. Envoy Gateway adds OIDC in front of it.

**Required Resources**:

1. **Backend** - Points to Pocket-ID service:
```yaml
# kubernetes/apps/home/bentopdf/app/backend.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: bentopdf-oidc-provider
spec:
  endpoints:
    - fqdn:
        hostname: pocket-id.security.svc.cluster.local
        port: 1411
```

2. **SecurityPolicy** - Configures OIDC for the HTTPRoute:
```yaml
# kubernetes/apps/home/bentopdf/app/securitypolicy.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: bentopdf-oidc
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: bentopdf
  oidc:
    provider:
      backendRefs:
        - group: gateway.envoyproxy.io
          kind: Backend
          name: bentopdf-oidc-provider
          port: 1411
      issuer: "https://id.${SECRET_DOMAIN}"
      authorizationEndpoint: "https://id.${SECRET_DOMAIN}/authorize"
      tokenEndpoint: "https://id.${SECRET_DOMAIN}/api/oidc/token"
    clientIDRef:
      name: "bentopdf-oidc"
    clientSecret:
      name: "bentopdf-oidc"
    redirectURL: "https://pdf.${SECRET_DOMAIN}/oauth2/callback"
    scopes: ["openid", "profile", "email"]
```

3. **ExternalSecret** - Provides client credentials from Pocket-ID
4. **ReferenceGrant** - Allows SecurityPolicy to reference Pocket-ID service cross-namespace

**Traffic Flow with OIDC**:

![claude_network_cxternal_app_without_oidc_support](./images/claude_network_external_app_without_oidc_support.png)

---

## Cilium CNI Features

### Capsule: CiliumNetworking

**Invariant**: Cilium replaces kube-proxy with eBPF, provides LoadBalancer IPs via L2 announcements, and enables socket-level load balancing for optimal performance.

### Key Features Enabled

| Feature | Config | Purpose |
|---------|--------|---------|
| **kubeProxyReplacement** | `true` | eBPF-based service routing, replaces iptables |
| **socketLB** | `enabled: true` | Socket-level LB bypasses network stack for local traffic |
| **l2announcements** | `enabled: true` | ARP announcements for LoadBalancer IPs |
| **LB-IPAM** | Pool: `10.90.3.0/16` | Automatic IP allocation for LoadBalancer services |
| **bandwidthManager** | `enabled: true, bbr: true` | TCP BBR congestion control |
| **bpf.masquerade** | `true` | eBPF-based SNAT for pod egress |

### Socket-Level Load Balancing

**What it does**: When a pod connects to a ClusterIP service, Cilium intercepts at the socket level and connects directly to the backend pod, bypassing the full network stack.

**Benefits**:
- Lower latency (no NAT/conntrack overhead)
- Better performance for service mesh patterns
- Reduced CPU usage

### L2 Announcements and LB-IPAM

```yaml
# kubernetes/apps/kube-system/cilium/config/cilium-l2.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
spec:
  loadBalancerIPs: true
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
---
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: l2-pool
spec:
  allowFirstLastIPs: "Yes"
  blocks:
    - cidr: "10.90.3.0/16"
```

**How IPs are assigned**:
1. Service created with `type: LoadBalancer`
2. Annotation `io.cilium/lb-ipam-ips: "10.90.3.XXX"` requests specific IP
3. Cilium assigns IP from pool, announces via ARP
4. Traffic to that IP routes to service

---

## DNS Architecture

### DNS Components

| Component | IP | Role |
|-----------|-----|------|
| CoreDNS | 10.96.0.10 | Cluster DNS, forwards non-cluster queries to upstream (UDM) |
| external-dns | N/A | Watches HTTPRoutes with external annotation, creates CNAME in Cloudflare |
| external-dns-unifi | N/A | Watches ALL HTTPRoutes, creates A records in UDM |
| Cloudflare DNS | N/A | Public authoritative DNS, returns Cloudflare edge IPs (proxied) |
| UDM Pro DNS | 10.90.254.1 | Local DNS resolver for LAN, pods, and Tailscale clients |

### DNS Record Creation Flow

When an app is deployed, DNS records are created automatically:

- **external-dns-unifi** watches ALL HTTPRoutes and creates A records in UDM pointing to the internal gateway (10.90.3.202)
- **external-dns** watches HTTPRoutes with `external-dns.alpha.kubernetes.io/target` annotation and creates CNAMEs in Cloudflare

### DNS Resolution by Client Location

#### Internet Client → External App

```
1. Client queries: app.${SECRET_DOMAIN}
2. Cloudflare DNS responds: Cloudflare edge IP (proxied)
3. Client connects to Cloudflare edge
4. Cloudflare routes via tunnel to cluster
```

#### LAN Client → Any App

```
1. Client queries: app.${SECRET_DOMAIN}
2. UDM DNS responds: 10.90.3.202 (internal gateway)
   └── Record created by external-dns-unifi
3. Client connects directly to internal gateway
4. No hairpin, no tunnel traversal
```

#### Pod → App in Cluster

```
1. Pod queries: app.${SECRET_DOMAIN}
2. CoreDNS forwards to /etc/resolv.conf (UDM: 10.90.254.1)
3. UDM DNS responds: 10.90.3.202 (internal gateway)
4. Pod connects to gateway → service
```

#### Tailscale Client → Internal App

```
1. Client queries: app.${SECRET_DOMAIN}
2. Tailscale Split DNS forwards to UDM (10.90.254.1)
3. UDM DNS responds: 10.90.3.202 (internal gateway)
4. Client connects via WireGuard mesh to internal gateway
```

### CoreDNS Configuration

```yaml
# kubernetes/apps/kube-system/coredns/app/helm-values.yaml
servers:
  - zones:
      - zone: .
        scheme: dns://
        use_tcp: true
    port: 53
    plugins:
      - name: kubernetes
        parameters: cluster.local in-addr.arpa ip6.arpa
      - name: forward
        parameters: . /etc/resolv.conf  # Forwards to UDM (10.90.254.1)
      - name: cache
        parameters: 30
```

This simplified configuration forwards all non-cluster DNS queries to the upstream resolver (UDM), which has authoritative records for all cluster apps created by external-dns-unifi.

---

## Traffic Flow Summary

### External Traffic (Internet → App)

![claude_network_external_traffic_internet-to-app](./images/claude_network_external_traffic_internet-to-app.png)

1. User requests `app.${SECRET_DOMAIN}`
2. Cloudflare DNS returns Cloudflare edge IP
3. Cloudflare terminates TLS, applies WAF rules
4. Traffic tunneled via QUIC to cloudflared pod
5. cloudflared forwards to external gateway (10.90.3.201)
6. Gateway terminates TLS, routes via HTTPRoute

### Internal Traffic (LAN → App)

![claude_network_external_traffic_lan-to-app](./images/claude_network_external_traffic_lan-to-app.png)

1. User requests `app.${SECRET_DOMAIN}`
2. UDM DNS returns 10.90.3.202 (if internal route exists)
3. Direct HTTPS to internal gateway
4. Gateway terminates TLS, routes via HTTPRoute

---

## Gateway Configuration

### External Gateway

```yaml
# kubernetes/apps/network/envoy-gateway/app/external/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external
spec:
  gatewayClassName: envoy-external
  addresses:
    - value: "10.90.3.201"
  infrastructure:
    annotations:
      io.cilium/lb-ipam-ips: "10.90.3.201"
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: envoy-gateway-${SECRET_DOMAIN/./-}-tls
```

### Internal Gateway

```yaml
# kubernetes/apps/network/envoy-gateway/app/internal/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: internal
spec:
  gatewayClassName: envoy-internal
  addresses:
    - value: "10.90.3.202"
  infrastructure:
    annotations:
      lbipam.cilium.io/ips: "10.90.3.202"
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
```

---

## External Services

Non-cluster services (TrueNAS, UDM, printers) are exposed via headless Service + Endpoints:

```yaml
# Service (no selector)
apiVersion: v1
kind: Service
metadata:
  name: unifi
spec:
  type: ClusterIP
  ports:
    - name: https
      port: 443

# Endpoints (manual IP)
apiVersion: v1
kind: Endpoints
metadata:
  name: unifi
subsets:
  - addresses:
      - ip: "${SECRET_UNIFI_IP}"
    ports:
      - name: https
        port: 443

# HTTPRoute (internal only)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: unifi
  annotations:
    internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: internal
      namespace: network
  hostnames:
    - unifi.${SECRET_DOMAIN}
```

**External Services Deployed**:
- `truenas.${SECRET_DOMAIN}` → TrueNAS web UI
- `unifi.${SECRET_DOMAIN}` → UDM Pro controller
- `voron.${SECRET_DOMAIN}` → 3D printer

---

## Troubleshooting

### Check Gateway Status

```bash
kubectl get gateways -n network
kubectl get httproutes -A
kubectl logs -n network -l app.kubernetes.io/name=envoy-gateway
```

### Check DNS Resolution

```bash
# From internet perspective
dig app.${SECRET_DOMAIN} @1.1.1.1

# From cluster (should return gateway IP)
kubectl run -it --rm debug --image=alpine -- nslookup app.${SECRET_DOMAIN} 10.90.3.200

# Check what external-dns created
kubectl logs -n network -l app.kubernetes.io/name=external-dns
kubectl logs -n network -l app.kubernetes.io/name=external-dns-unifi
```

### Check Cilium LB-IPAM

```bash
kubectl get ciliumloadbalancerippool
kubectl get services -A -o wide | grep LoadBalancer
cilium status
```

### Check Cloudflare Tunnel

```bash
kubectl logs -n network -l app.kubernetes.io/name=cloudflared
kubectl get pods -n network -l app.kubernetes.io/name=cloudflared
```

---

## Evidence

| Claim | Source | Namespace | Confidence |
|-------|--------|-----------|------------|
| External gateway at 10.90.3.201 | [`envoy-gateway/app/external/gateway.yaml:19`](../../kubernetes/apps/network/envoy-gateway/app/external/gateway.yaml#L19) | network | Verified |
| Internal gateway at 10.90.3.202 | [`envoy-gateway/app/internal/gateway.yaml:19`](../../kubernetes/apps/network/envoy-gateway/app/internal/gateway.yaml#L19) | network | Verified |
| Cilium LB-IPAM pool 10.90.3.0/16 | [`cilium/config/cilium-l2.yaml:24`](../../kubernetes/apps/kube-system/cilium/config/cilium-l2.yaml#L24) | kube-system | Verified |
| Cilium socketLB enabled | [`cilium/app/helm-values.yaml:42`](../../kubernetes/apps/kube-system/cilium/app/helm-values.yaml#L42) | kube-system | Verified |
| external-dns filters by annotation | [`external-dns/app/helmrelease.yaml:40`](../../kubernetes/apps/network/external-dns/app/helmrelease.yaml#L40) | network | Verified |
| external-dns-unifi creates records for all routes | [`external-dns-unifi/app/helmrelease.yaml`](../../kubernetes/apps/network/external-dns-unifi/app/helmrelease.yaml) | network | Verified |
| CoreDNS forwards to upstream (UDM) | [`coredns/app/helm-values.yaml`](../../kubernetes/apps/kube-system/coredns/app/helm-values.yaml) | kube-system | Verified |
| bentopdf OIDC via SecurityPolicy | [`bentopdf/app/securitypolicy.yaml`](../../kubernetes/apps/home/bentopdf/app/securitypolicy.yaml) | home | Verified |
| Pocket-ID dual-homed (both gateways) | [`pocket-id/app/helmrelease.yaml:90-108`](../../kubernetes/apps/security/pocket-id/app/helmrelease.yaml#L90) | security | Verified |

