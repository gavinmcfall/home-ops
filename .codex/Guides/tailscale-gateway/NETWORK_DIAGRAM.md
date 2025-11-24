# Network Architecture Diagram - Post Tailscale Gateway Migration

**Document Version:** 1.0
**Last Updated:** 2025-11-24
**Reflects:** Three-Gateway Architecture (External, Internal, Tailscale)

---

## Complete Network Architecture

**Network Flow: Users → Entry Points → Infrastructure → Authentication → Services**

![Network Architecture Diagram](eraser.png)

*Rendered with [Eraser.io](https://eraser.io) | [View Mermaid Source](MERMAID_SOURCE.md)*

---

## Traffic Flow Detailed Breakdown

### 1. Public Internet Access (via Cloudflare Tunnel)

```mermaid
sequenceDiagram
    participant User as Public User
    participant CF as Cloudflare Edge
    participant CFD as Cloudflared Pod
    participant ExtGW as External Gateway<br/>(10.90.3.201)
    participant Route as HTTPRoute
    participant Svc as Service (App)

    User->>CF: 1. HTTPS Request<br/>public.example.com
    CF->>CFD: 2. Tunnel (QUIC/HTTP2)<br/>Encrypted
    CFD->>ExtGW: 3. Forward to Gateway<br/>Based on config
    ExtGW->>Route: 4. Match hostname + path
    Route->>Svc: 5. Route to backend
    Svc-->>Route: 6. Response
    Route-->>ExtGW: 7. Return
    ExtGW-->>CFD: 8. Return
    CFD-->>CF: 9. Tunnel response
    CF-->>User: 10. HTTPS Response
```

### 2. Internal LAN Access

```mermaid
sequenceDiagram
    participant User as Local User<br/>(LAN)
    participant DNS as k8s-gateway<br/>(10.90.3.200)
    participant IntGW as Internal Gateway<br/>(10.90.3.202)
    participant Route as HTTPRoute
    participant Svc as Service (App)

    User->>DNS: 1. DNS Query<br/>grafana.domain.com
    DNS-->>User: 2. A Record<br/>10.90.3.202
    User->>IntGW: 3. HTTPS Request<br/>grafana.domain.com
    IntGW->>Route: 4. Match parentRef: internal
    Route->>Svc: 5. Route to grafana:80
    Svc-->>Route: 6. Response
    Route-->>IntGW: 7. Return
    IntGW-->>User: 8. HTTPS Response
```

### 3. Tailscale VPN Access (NEW)

```mermaid
sequenceDiagram
    participant User as Remote User<br/>(Tailscale Client)
    participant TSDNS as Tailscale MagicDNS<br/>(Split DNS)
    participant K8sDNS as k8s-gateway<br/>(10.90.3.200)
    participant TSGW as Tailscale Gateway<br/>(gateway-envoy.ts.net)
    participant Route as HTTPRoute
    participant Svc as Service (App)

    User->>TSDNS: 1. DNS Query<br/>grafana.domain.com
    TSDNS->>K8sDNS: 2. Forward query<br/>(Split DNS config)
    K8sDNS-->>TSDNS: 3. A Record<br/>10.90.3.202
    TSDNS-->>User: 4. DNS Response
    User->>TSGW: 5. HTTPS Request<br/>via Tailscale Mesh
    TSGW->>Route: 6. Match parentRef: tailscale
    Route->>Svc: 7. Route to backend
    Svc-->>Route: 8. Response
    Route-->>TSGW: 9. Return
    TSGW-->>User: 10. HTTPS Response<br/>via Tailscale
```

### 4. DNS Automation Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as Git Repository
    participant Flux as Flux CD
    participant K8s as Kubernetes API
    participant HTTPRoute as HTTPRoute Resource
    participant ExtDNS as external-dns
    participant K8sGW as k8s-gateway

    Dev->>Git: 1. Commit HTTPRoute
    Git->>Flux: 2. Flux pulls changes
    Flux->>K8s: 3. Apply HTTPRoute
    K8s->>HTTPRoute: 4. Create resource
    HTTPRoute->>K8sGW: 5. k8s-gateway watches HTTPRoute
    K8sGW->>K8sGW: 6. Create A record<br/>service.domain.com → 10.90.3.202
    ExtDNS->>HTTPRoute: 7. external-dns watches
    ExtDNS->>K8sGW: 8. (Optional) Create/Update<br/>DNS records
```

---

## Component IP Address Map

| Component | IP Address | Purpose | Load Balancer |
|-----------|-----------|---------|---------------|
| **k8s-gateway** | `10.90.3.200` | Internal DNS for `${SECRET_DOMAIN}` | Cilium IPAM |
| **External Gateway** | `10.90.3.201` | Public internet traffic (via Cloudflare) | Cilium IPAM |
| **Internal Gateway** | `10.90.3.202` | Local network traffic | Cilium IPAM |
| **Tailscale Gateway** | `gateway-envoy.tail<xxxx>.ts.net` | Remote VPN traffic | Tailscale |
| **CoreDNS** | `10.96.0.10` (ClusterIP) | Cluster-internal DNS | N/A (ClusterIP) |

---

## Gateway Comparison Matrix

| Feature | External Gateway | Internal Gateway | Tailscale Gateway |
|---------|-----------------|------------------|-------------------|
| **Purpose** | Public internet access | Local network access | Remote VPN access |
| **IP Address** | 10.90.3.201 | 10.90.3.202 | gateway-envoy.ts.net |
| **Load Balancer** | Cilium | Cilium | Tailscale |
| **DNS Target** | external.${SECRET_DOMAIN} | internal.${SECRET_DOMAIN} | gateway-envoy.tail<>.ts.net |
| **TLS Termination** | Yes (cert-manager) | Yes (cert-manager) | Yes (Tailscale or cert-manager) |
| **Access Control** | Public | LAN only | Tailscale auth required |
| **Typical Users** | Anonymous internet | Home devices | Authorized remote users |
| **Example Route** | CloudFlare Tunnel → Gateway | Direct connection | Tailscale Mesh → Gateway |

---

## HTTPRoute Multi-Gateway Pattern

### Single Gateway (Old Pattern)
```yaml
# Only accessible via one gateway
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
spec:
  parentRefs:
    - name: internal      # Only LAN access
  hostnames:
    - grafana.domain.com
  rules:
    - backendRefs:
        - name: grafana
          port: 80
```

### Multi-Gateway (New Pattern)
```yaml
# Accessible via multiple gateways
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
spec:
  parentRefs:
    - name: internal      # LAN access
      namespace: network
    - name: tailscale     # Tailscale VPN access
      namespace: network
  hostnames:
    - grafana.domain.com
  rules:
    - backendRefs:
        - name: grafana
          port: 80
```

**Result:**
- Same service accessible from **two different networks**
- Single configuration, multiple entry points
- Consistent routing rules across gateways

---

## Network Policy Considerations

### Current State
- **Cilium NetworkPolicies** control pod-to-pod communication
- **Gateway policies** (ClientTrafficPolicy, BackendTrafficPolicy) control HTTP-level behavior
- **Tailscale ACLs** control who can access the Tailscale network

### Security Layers

```mermaid
graph LR
    subgraph SecurityLayers["Security Layers (Defense in Depth)"]
        L1["Layer 1:<br/>Tailscale ACLs<br/>(VPN Access Control)"]
        L2["Layer 2:<br/>Gateway API<br/>(Route Matching)"]
        L3["Layer 3:<br/>Cilium NetworkPolicy<br/>(L3/L4 Filtering)"]
        L4["Layer 4:<br/>OAuth2-Proxy<br/>(Authentication)"]
        L5["Layer 5:<br/>Application Auth<br/>(App-level RBAC)"]
    end

    L1 --> L2
    L2 --> L3
    L3 --> L4
    L4 --> L5

    style L1 fill:#ffdddd,color:#000
    style L2 fill:#ffe6cc,color:#000
    style L3 fill:#ffffcc,color:#000
    style L4 fill:#ddffdd,color:#000
    style L5 fill:#cce6ff,color:#000
```

---

## DNS Resolution Hierarchy

```mermaid
graph TD
    subgraph Client["Client DNS Query: grafana.domain.com"]
        Query["DNS Query"]
    end

    subgraph Resolution["Resolution Path"]
        Query --> CheckLocation{Where is<br/>client located?}

        CheckLocation -->|"Internet"| InternetDNS["Public DNS<br/>(Cloudflare, Google)"]
        CheckLocation -->|"LAN"| RouterDNS["Home Router<br/>DNS"]
        CheckLocation -->|"Tailscale VPN"| MagicDNS["Tailscale MagicDNS"]

        InternetDNS -->|"A Record<br/>(Optional)"| CloudflareDNS["Cloudflare DNS<br/>(external-dns)"]
        CloudflareDNS --> CloudflareTunnel["Routes to<br/>Cloudflare Tunnel"]

        RouterDNS -->|"Forwards to"| K8sGW["k8s-gateway<br/>10.90.3.200"]

        MagicDNS -->|"Split DNS<br/>*.domain.com"| K8sGW
        MagicDNS -->|"Other domains"| TailscaleCoreDNS["Tailscale<br/>Core DNS"]

        K8sGW -->|"Watches HTTPRoutes<br/>Returns"| InternalIP["10.90.3.202<br/>(Internal Gateway)"]
    end

    style Query fill:#e6e6ff,color:#000
    style K8sGW fill:#cce6ff,color:#000
    style MagicDNS fill:#ddddff,color:#000
    style InternalIP fill:#ddffdd,color:#000
```

---

## Service Discovery Flow

### How k8s-gateway Discovers Services

```mermaid
flowchart TD
    Start["k8s-gateway Pod<br/>Starts"] --> Watch["Watch Kubernetes API"]

    Watch --> Resources{What resources<br/>to watch?}

    Resources --> Ingress["Ingress Resources<br/>(Legacy)"]
    Resources --> Services["Service Resources<br/>(type: LoadBalancer)"]
    Resources --> HTTPRoutes["HTTPRoute Resources<br/>(Gateway API)"]

    Ingress --> ExtractHost1["Extract .spec.rules[].host"]
    Services --> ExtractHost2["Extract .status.loadBalancer.ingress[].ip"]
    HTTPRoutes --> ExtractHost3["Extract .spec.hostnames[]"]

    ExtractHost1 --> CreateRecord["Create DNS A Record"]
    ExtractHost2 --> CreateRecord
    ExtractHost3 --> CreateRecord

    CreateRecord --> Serve["Serve DNS Queries<br/>on UDP/TCP 53"]

    Serve --> Update{Resource<br/>changed?}
    Update -->|Yes| Watch
    Update -->|No| Serve

    style Start fill:#ddffdd,color:#000
    style Watch fill:#cce6ff,color:#000
    style CreateRecord fill:#ffe6cc,color:#000
    style Serve fill:#ffdddd,color:#000
```

---

## Load Balancer Integration

### Cilium vs Tailscale LoadBalancer

```mermaid
graph TB
    subgraph Services["Kubernetes Services (type: LoadBalancer)"]
        ExtSvc["external-gateway-envoy<br/>LoadBalancerClass: (default)"]
        IntSvc["internal-gateway-envoy<br/>LoadBalancerClass: (default)"]
        TSSvc["tailscale-gateway-envoy<br/>LoadBalancerClass: tailscale"]
        K8sGWSvc["k8s-gateway<br/>LoadBalancerClass: (default)"]
    end

    subgraph CiliumLB["Cilium LoadBalancer"]
        CiliumIPAM["Cilium IPAM<br/>Pool: 10.90.3.200-210"]
        CiliumAssign["Assign IP from Pool"]
    end

    subgraph TailscaleLB["Tailscale LoadBalancer"]
        TSOperator["Tailscale Operator<br/>Watches Services"]
        TSDevice["Create Tailscale Device<br/>(gateway-envoy)"]
        TSAddress["Assign .ts.net Address"]
    end

    ExtSvc -->|"Requests IP"| CiliumIPAM
    IntSvc -->|"Requests IP"| CiliumIPAM
    K8sGWSvc -->|"Requests IP"| CiliumIPAM

    CiliumIPAM --> CiliumAssign
    CiliumAssign -->|"10.90.3.201"| ExtSvc
    CiliumAssign -->|"10.90.3.202"| IntSvc
    CiliumAssign -->|"10.90.3.200"| K8sGWSvc

    TSSvc -->|"loadBalancerClass: tailscale"| TSOperator
    TSOperator --> TSDevice
    TSDevice --> TSAddress
    TSAddress -->|"gateway-envoy.tail<>.ts.net"| TSSvc

    style CiliumIPAM fill:#cce6ff,color:#000
    style TSOperator fill:#ddddff,color:#000
    style ExtSvc fill:#ffe6cc,color:#000
    style IntSvc fill:#ffe6cc,color:#000
    style TSSvc fill:#ffdddd,color:#000
```

---

## Monitoring & Observability

### Metrics Collection Flow

```mermaid
graph LR
    subgraph Gateways["Envoy Gateway Pods"]
        ExtEnvoy["External<br/>Envoy Pods"]
        IntEnvoy["Internal<br/>Envoy Pods"]
        TSEnvoy["Tailscale<br/>Envoy Pods"]
    end

    subgraph Monitoring["Observability Stack"]
        SM["ServiceMonitor<br/>(Prometheus Operator)"]
        Prom["Prometheus<br/>(Scrape Targets)"]
        Grafana["Grafana<br/>(Visualization)"]
    end

    ExtEnvoy -->|"Expose /stats/prometheus<br/>Port 19001"| SM
    IntEnvoy -->|"Expose /stats/prometheus<br/>Port 19001"| SM
    TSEnvoy -->|"Expose /stats/prometheus<br/>Port 19001"| SM

    SM --> Prom
    Prom --> Grafana

    style ExtEnvoy fill:#ffe6cc,color:#000
    style IntEnvoy fill:#ffe6cc,color:#000
    style TSEnvoy fill:#ffdddd,color:#000
    style Prom fill:#cce6ff,color:#000
    style Grafana fill:#ddffdd,color:#000
```

### Key Metrics to Monitor

**Gateway Health:**
- `envoy_server_live` - Gateway is alive
- `envoy_cluster_membership_healthy` - Backend health
- `envoy_http_downstream_rq_total` - Total requests per gateway

**Traffic Patterns:**
- `envoy_http_downstream_rq_time_bucket` - Request latency
- `envoy_http_downstream_cx_total` - Active connections
- `envoy_http_downstream_rq_xx` - Response codes (2xx, 4xx, 5xx)

**Resource Usage:**
- `container_memory_working_set_bytes` - Memory usage
- `container_cpu_usage_seconds_total` - CPU usage
- `kube_horizontalpodautoscaler_status_current_replicas` - HPA scaling

---

## Architecture Benefits

### Before Migration (Ingress + Gateway API)
```
✗ Two different APIs (Ingress for Tailscale, Gateway for internal/external)
✗ Duplicate configuration per service
✗ No unified observability
✗ Difficult to apply consistent policies
```

### After Migration (Gateway API Only)
```
✓ Single API (Gateway API) for all traffic types
✓ Multi-gateway HTTPRoutes (one config, multiple entry points)
✓ Unified metrics across all gateways
✓ Consistent policies (ClientTrafficPolicy, BackendTrafficPolicy)
✓ Centralized TLS management via cert-manager
✓ Better scalability with HPA per gateway
```

---

## Future Enhancements

### Potential Additions
1. **OAuth2-Proxy Integration**
   - Add authentication layer for sensitive services
   - Protect HTTPRoutes with OIDC/OAuth2

2. **Rate Limiting**
   - Apply RateLimitPolicy to gateways
   - Protect against abuse/DDoS

3. **Request Mirroring**
   - Mirror production traffic to staging
   - Test new versions safely

4. **Traffic Splitting**
   - Canary deployments via HTTPRoute weight
   - Blue/green deployments

5. **Custom Metrics**
   - Application-level metrics via EnvoyFilter
   - Custom dashboards per service

---

## Troubleshooting Quick Reference

### Gateway Not Ready
```bash
kubectl get gateway -n network
kubectl describe gateway <name> -n network
kubectl logs -n network -l control-plane=envoy-gateway
```

### HTTPRoute Not Routing
```bash
kubectl describe httproute <name> -n <namespace>
kubectl get gateway -n network -o yaml | grep -A10 listeners
```

### DNS Not Resolving
```bash
dig @10.90.3.200 service.domain.com
kubectl logs -n network -l app.kubernetes.io/name=k8s-gateway
```

### Tailscale Gateway No Address
```bash
kubectl get svc -n network | grep tailscale
kubectl logs -n network -l app.kubernetes.io/name=tailscale-operator
# Check Tailscale admin: https://login.tailscale.com/admin/machines
```

---

## Related Documentation

- [Migration Guide](./README.md) - Step-by-step migration instructions
- [Homelab Architecture](../Homelab/ARCHITECTURE.md) - Overall cluster design
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/) - Upstream specification
- [Cilium Docs](https://docs.cilium.io/) - CNI and LoadBalancer IPAM
- [Tailscale Kubernetes Docs](https://tailscale.com/kb/1185/kubernetes) - VPN integration

---

