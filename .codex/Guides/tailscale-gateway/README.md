# Migrating from Tailscale Ingress to Gateway API with BYOD (Bring Your Own Device)

**Documented on:** 2025-11-24

## Overview

This guide describes migrating Tailscale-exposed services from Kubernetes Ingress to the Gateway API using Envoy Gateway with Tailscale's BYOD (Bring Your Own Device) LoadBalancer integration. This enables services to be accessed over Tailscale VPN while maintaining internal network access.

### Problem Statement

**Current Architecture:**
- Services use `ingressClassName: tailscale` to expose services over Tailscale VPN
- Gateway API is used for external (`10.90.3.201`) and internal (`10.90.3.202`) traffic via Envoy Gateway
- Tailscale Ingress and Gateway API cannot coexist cleanly for the same service

**Goal:**
- Migrate from Tailscale Ingress to Gateway API HTTPRoutes
- Maintain both internal LAN and remote Tailscale access
- Use unified Gateway API architecture across all traffic types

**References:**
- [Tailscale BYOD Gateway API](https://tailscale.com/kb/1620/kubernetes-operator-byod-gateway-api)
- [Tailscale BYOD Troubleshooting](https://tailscale.com/kb/1621/kubernetes-operator-byod-gateway-api-troubleshooting)
- [Tailscale Kubernetes Integration](https://tailscale.com/kb/1185/kubernetes)

---

## Current State (Baseline)

### Existing Gateway Infrastructure

**Location:** `kubernetes/apps/network/envoy-gateway/app/`

**Gateway 1: External** (`external/gateway.yaml`)
- **IP:** `10.90.3.201`
- **Purpose:** Public internet traffic
- **DNS:** `external.${SECRET_DOMAIN}`
- **Listeners:** HTTP (80), HTTPS (443)
- **Load Balancer:** Cilium IPAM

**Gateway 2: Internal** (`internal/gateway.yaml`)
- **IP:** `10.90.3.202`
- **Purpose:** Internal LAN traffic
- **DNS:** `internal.${SECRET_DOMAIN}`
- **Listeners:** HTTP (80), HTTPS (443)
- **Load Balancer:** Cilium IPAM

### Tailscale Operator Configuration

**Location:** `kubernetes/apps/network/tailscale/operator/app/helmrelease.yaml`

**Version:** `1.90.8`
**Configuration:**
```yaml
operatorConfig:
  logging: "debug"
apiServerProxyConfig:
  mode: "true"
```

**Purpose:** Kubernetes API server remote access only (not general service exposure)

### Services Using Tailscale Ingress

**Evidence:**
```bash
# Found via: rg -n "ingressClassName.*tailscale" kubernetes/apps --files-with-matches
```

| Service | Location | Current Config |
|---------|----------|----------------|
| **Grafana** | `kubernetes/apps/observability/grafana/app/tailscale-ingress.yaml` | Standalone Ingress resource |
| **Paperless** | `kubernetes/apps/home/paperless/app/helmrelease.yaml:127-135` | Helm chart `ingress.tailscale` block |
| **Paperless-AI** | `kubernetes/apps/home/paperless/paperless-ai/helmrelease.yaml:66-74` | Helm chart `ingress.tailscale` block |
| **Filebrowser** | `kubernetes/apps/home/filebrowser/app/helmrelease.yaml:89-97` | Helm chart `ingress.tailscale` block |
| **Homepage** | `kubernetes/apps/home/homepage/app/helmrelease.yaml:69-77` | Helm chart `ingress.tailscale` block |
| **Teslamate** | `kubernetes/apps/home-automation/teslamate/app/helmrelease.yaml:77-85` | Helm chart `ingress.tailscale` block |

**Current Behavior:**
- Each service gets a unique Tailscale hostname (e.g., `grafana`, `paperless`, `homepage`)
- Services accessible via Tailscale MagicDNS
- TLS provided automatically by Tailscale

---

## Architecture: Three-Gateway Design

### Gateway Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Gateway 1: envoy-external (10.90.3.201)                     │
│ Purpose: Public internet traffic                             │
│ Load Balancer: Cilium                                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Gateway 2: envoy-internal (10.90.3.202)                     │
│ Purpose: Internal LAN access                                 │
│ Load Balancer: Cilium                                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Gateway 3: envoy-tailscale (NEW)                            │
│ Purpose: Remote access via Tailscale VPN                     │
│ Load Balancer: Tailscale (NOT Cilium)                        │
│ Hostname: gateway-envoy.${TAILNET_NAME}.ts.net              │
└─────────────────────────────────────────────────────────────┘
```

### Traffic Flow

**Local Access (Internal Network):**
```
User (LAN) → envoy-internal (10.90.3.202) → HTTPRoute → Service
```

**Remote Access (Tailscale VPN):**
```
User (Tailscale) → envoy-tailscale → HTTPRoute → Service
```

**Multi-Gateway HTTPRoute Example:**
```yaml
spec:
  parentRefs:
    - name: internal      # Accessible from LAN
    - name: tailscale     # Accessible via Tailscale
  hostnames:
    - grafana.${SECRET_DOMAIN}
```

---

## Prerequisites

### 1. Tailscale Configuration

**Required Tailscale Settings:**

1. **OAuth Client** (Already configured in 1Password)
   - Client ID: `TAILSCALE_OATH_CLIENT_ID`
   - Client Secret: `TAILSCALE_OAUTH_CLIENT_SECRET`
   - Tags: `k8s-operator`

2. **ACL Tags** (Already configured in Tailscale admin)
   ```json
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"]
   }
   ```

3. **Split DNS** (NEW - Required for BYOD)
   - **Action:** Configure MagicDNS to forward `${SECRET_DOMAIN}` queries to internal DNS
   - **Location:** Tailscale Admin Console → DNS → Nameservers
   - **Add:** Custom nameserver for `*.${SECRET_DOMAIN}` → `10.90.3.x` (your CoreDNS/k8s-gateway)

4. **ExternalDNS** (Already running)
   - **Verify:** `kubectl get pods -n network -l app.kubernetes.io/name=external-dns`
   - **Purpose:** Automatically creates DNS A records for Gateway resources

### 2. Certificate Management

**Current TLS Strategy:**
- External/Internal gateways use cert-manager with `${SECRET_DOMAIN}` wildcard certificate
- **Location:** `kubernetes/apps/network/envoy-gateway/app/certificate.yaml`

**Tailscale Gateway Option 1: Reuse Existing Certificate**
```yaml
tls:
  certificateRefs:
    - name: envoy-gateway-${SECRET_DOMAIN/./-}-tls
```

**Tailscale Gateway Option 2: Let Tailscale Handle TLS** (Simpler)
- Tailscale provides automatic TLS for `.ts.net` domains
- No cert-manager configuration needed
- Recommended approach for initial migration

### 3. Verification Commands

```bash
# Verify Tailscale operator is running
kubectl get pods -n network -l app.kubernetes.io/name=tailscale-operator

# Verify ExternalDNS
kubectl get pods -n network -l app.kubernetes.io/name=external-dns

# Verify Envoy Gateway controller
kubectl get pods -n network -l control-plane=envoy-gateway

# Check existing Gateways
kubectl get gateway -n network
```

---

## Phase 1: Deploy Tailscale Gateway Infrastructure

### Step 1: Create Tailscale Gateway Directory

```bash
mkdir -p ~/home-ops/kubernetes/apps/network/envoy-gateway/app/tailscale
cd ~/home-ops/kubernetes/apps/network/envoy-gateway/app/tailscale
```

### Step 2: Create GatewayClass

**File:** `gatewayclass.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/gatewayclass_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-tailscale
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: envoy-tailscale
    namespace: network
```

### Step 3: Create EnvoyProxy Configuration

**File:** `envoyproxy.yaml`

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/envoyproxy/gateway/refs/heads/main/charts/gateway-helm/crds/generated/gateway.envoyproxy.io_envoyproxies.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy-tailscale
spec:
  telemetry:
    metrics:
      prometheus: {}
  shutdown:
    drainTimeout: 300s
  logging:
    level:
      default: info
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        container:
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
      envoyHpa:
        minReplicas: 1
        maxReplicas: 3
        metrics:
          - type: Resource
            resource:
              name: cpu
              target:
                type: Utilization
                averageUtilization: 60
        behavior:
          scaleUp:
            stabilizationWindowSeconds: 300
          scaleDown:
            stabilizationWindowSeconds: 300
      envoyService:
        type: LoadBalancer
        loadBalancerClass: tailscale
        annotations:
          tailscale.com/hostname: gateway-envoy
          # Optional: Expose to public internet via Tailscale Funnel
          # tailscale.com/funnel: "true"
```

### Step 4: Create Gateway Resource

**File:** `gateway.yaml`

**Option A: Using Tailscale TLS (Recommended for initial migration)**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/gateway_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tailscale
  labels:
    external-dns.home.arpa/enabled: "true"
  annotations:
    gatus.home-operations.com/endpoint: |-
      client:
        dns-resolver: tcp://1.1.1.1:53
      group: tailscale
      guarded: true
      ui:
        hide-hostname: true
        hide-url: true
spec:
  gatewayClassName: envoy-tailscale
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        kinds:
          - kind: HTTPRoute
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        kinds:
          - kind: HTTPRoute
        namespaces:
          from: All
      tls:
        mode: Passthrough  # Let Tailscale handle TLS termination
```

**Option B: Using cert-manager TLS** (Advanced)

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tailscale
  labels:
    external-dns.home.arpa/enabled: "true"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
spec:
  gatewayClassName: envoy-tailscale
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        kinds:
          - kind: HTTPRoute
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: envoy-gateway-${SECRET_DOMAIN/./-}-tls
```

### Step 5: Create Kustomization

**File:** `kustomization.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./gatewayclass.yaml
  - ./envoyproxy.yaml
  - ./gateway.yaml
```

### Step 6: Update Parent Kustomization

**File:** `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml`

Add to `resources:`:
```yaml
resources:
  # ... existing resources ...
  - ./tailscale
```

### Step 7: Commit and Deploy

```bash
cd ~/home-ops

# Stage all new files
git add kubernetes/apps/network/envoy-gateway/app/tailscale/

# Commit changes
git commit -m "feat(envoy-gateway): Add Tailscale Gateway for BYOD support

- Create GatewayClass: envoy-tailscale
- Configure EnvoyProxy with Tailscale LoadBalancer
- Deploy Gateway with TLS passthrough
- Enable remote access via Tailscale VPN

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to repository
git push

# Force Flux reconciliation
flux reconcile source git home-kubernetes -n flux-system
flux reconcile kustomization cluster-apps-network -n flux-system --with-source
```

### Step 8: Verify Gateway Deployment

```bash
# Wait for Envoy Gateway controller to process new resources
sleep 30

# Check GatewayClass
kubectl get gatewayclass envoy-tailscale

# Check Gateway status
kubectl get gateway tailscale -n network

# Verify Envoy proxy deployment
kubectl get pods -n network -l gateway.envoyproxy.io/owning-gateway-name=tailscale

# Check LoadBalancer service (should have Tailscale address)
kubectl get svc -n network | grep tailscale

# Verify Tailscale device appeared in admin console
# Go to: https://login.tailscale.com/admin/machines
# Look for: gateway-envoy
```

**Expected Output:**
```
NAME       CLASS              ADDRESS                            READY   AGE
tailscale  envoy-tailscale    gateway-envoy.tail<xxxxx>.ts.net   True    5m
```

---

## Phase 2: Migrate Services to HTTPRoutes

### Migration Strategy

**Approach:** Gradual migration with rollback capability
1. Create HTTPRoute alongside existing Ingress
2. Test HTTPRoute access
3. Remove Ingress after validation
4. Repeat for each service

### Step 1: Pilot Migration - Grafana

**Current Configuration:**

**File:** `kubernetes/apps/observability/grafana/app/tailscale-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
spec:
  ingressClassName: tailscale
  rules:
    - host: grafana
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

**New Configuration:**

**File:** `kubernetes/apps/observability/grafana/app/httproute.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  annotations:
    external-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: internal      # Internal LAN access
      namespace: network
    - name: tailscale     # Remote Tailscale access
      namespace: network
  hostnames:
    - grafana.${SECRET_DOMAIN}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: grafana
          port: 80
```

**Update Kustomization:**

**File:** `kubernetes/apps/observability/grafana/app/kustomization.yaml`

Add `httproute.yaml` to resources:
```yaml
resources:
  # ... existing resources ...
  - ./httproute.yaml
  # Keep tailscale-ingress.yaml for now (remove after validation)
```

**Deploy and Test:**

```bash
cd ~/home-ops

# Stage changes
git add kubernetes/apps/observability/grafana/app/httproute.yaml
git add kubernetes/apps/observability/grafana/app/kustomization.yaml

# Commit
git commit -m "feat(grafana): Add HTTPRoute for internal + Tailscale access

- Create HTTPRoute with dual parent refs (internal, tailscale)
- Maintain existing Tailscale Ingress during testing
- Hostname: grafana.${SECRET_DOMAIN}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

git push

# Reconcile
flux reconcile kustomization cluster-apps-observability -n flux-system --with-source

# Verify HTTPRoute created
kubectl get httproute grafana -n observability

# Test access from Tailscale device
curl -I https://grafana.${SECRET_DOMAIN}
```

**Validation Checklist:**
- [ ] HTTPRoute shows `Accepted: True` status
- [ ] Service accessible from internal network: `https://grafana.${SECRET_DOMAIN}`
- [ ] Service accessible via Tailscale VPN: `https://grafana.${SECRET_DOMAIN}`
- [ ] TLS certificate valid
- [ ] Grafana dashboard loads correctly
- [ ] Authentication works

**Remove Tailscale Ingress (After Validation):**

```bash
# Remove old Ingress from kustomization
# Edit: kubernetes/apps/observability/grafana/app/kustomization.yaml
# Remove: - ./tailscale-ingress.yaml

# Delete the Ingress file
rm kubernetes/apps/observability/grafana/app/tailscale-ingress.yaml

git add -u
git commit -m "chore(grafana): Remove Tailscale Ingress after HTTPRoute migration

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

### Step 2: Migrate Helm Chart Ingress Configs

**Services:** Paperless, Paperless-AI, Filebrowser, Homepage, Teslamate

**Current Pattern (Example: Paperless):**

**File:** `kubernetes/apps/home/paperless/app/helmrelease.yaml:127-135`

```yaml
ingress:
  tailscale:
    enabled: true
    className: tailscale
    hosts:
      - host: &app "{{ .Release.Name }}"
        paths:
          - path: /
            pathType: Prefix
```

**Migration Steps:**

#### A. Create HTTPRoute for Paperless

**File:** `kubernetes/apps/home/paperless/app/httproute.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: paperless
  annotations:
    external-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: internal
      namespace: network
    - name: tailscale
      namespace: network
  hostnames:
    - paperless.${SECRET_DOMAIN}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: paperless
          port: 8000
```

#### B. Update HelmRelease

**File:** `kubernetes/apps/home/paperless/app/helmrelease.yaml`

**Change:**
```yaml
# Comment out or remove Tailscale ingress block
# ingress:
#   tailscale:
#     enabled: true
#     className: tailscale
```

#### C. Update Kustomization

**File:** `kubernetes/apps/home/paperless/app/kustomization.yaml`

Add:
```yaml
resources:
  # ... existing ...
  - ./httproute.yaml
```

#### D. Deploy and Validate

```bash
cd ~/home-ops

git add kubernetes/apps/home/paperless/app/
git commit -m "feat(paperless): Migrate from Tailscale Ingress to HTTPRoute

- Remove Helm chart tailscale ingress block
- Add HTTPRoute with internal + tailscale parent refs
- Service accessible via both LAN and Tailscale

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push

flux reconcile kustomization cluster-apps-home -n flux-system --with-source

# Test
curl -I https://paperless.${SECRET_DOMAIN}
```

#### E. Repeat for Remaining Services

Apply same pattern to:
- `kubernetes/apps/home/paperless/paperless-ai/` → `paperless-ai.${SECRET_DOMAIN}` (port: 8000)
- `kubernetes/apps/home/filebrowser/app/` → `filebrowser.${SECRET_DOMAIN}` (check port in helmrelease)
- `kubernetes/apps/home/homepage/app/` → `homepage.${SECRET_DOMAIN}` (port: 3000 typically)
- `kubernetes/apps/home-automation/teslamate/app/` → `teslamate.${SECRET_DOMAIN}` (check port)

**Template HTTPRoute for other services:**

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <service-name>
  annotations:
    external-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: internal
      namespace: network
    - name: tailscale
      namespace: network
  hostnames:
    - <service-name>.${SECRET_DOMAIN}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>
          port: <service-port>
```

---

## Phase 3: DNS Configuration

### Tailscale Split DNS Setup

**Required for:** Tailscale clients to resolve `*.${SECRET_DOMAIN}` via internal DNS

#### Step 1: Configure Split DNS in Tailscale

1. Go to [Tailscale Admin Console → DNS](https://login.tailscale.com/admin/dns)
2. Click **Add nameserver** → **Custom...**
3. Configure:
   - **Nameserver:** `10.90.3.x` (your k8s-gateway or CoreDNS service IP)
   - **Restrict to domain:** `${SECRET_DOMAIN}`
4. Click **Save**

#### Step 2: Verify k8s-gateway / CoreDNS Configuration

**Find your internal DNS service:**

```bash
# Option 1: k8s-gateway
kubectl get svc -n network k8s-gateway

# Option 2: CoreDNS
kubectl get svc -n kube-system kube-dns
```

**Verify ExternalDNS is creating A records:**

```bash
# Check ExternalDNS logs
kubectl logs -n network -l app.kubernetes.io/name=external-dns --tail=50

# Should see entries like:
# "Creating A record for grafana.${SECRET_DOMAIN} pointing to 10.90.3.202"
```

#### Step 3: Test DNS Resolution

**From Tailscale-connected device:**

```bash
# Should resolve to internal IP (10.90.3.202 for internal gateway)
nslookup grafana.${SECRET_DOMAIN}

# Should resolve to Tailscale Gateway IP
nslookup gateway-envoy.tail<xxxxx>.ts.net
```

---

## Phase 4: Validation & Testing

### Comprehensive Testing Matrix

| Service | Internal LAN | Tailscale VPN | TLS Valid | App Functional |
|---------|--------------|---------------|-----------|----------------|
| Grafana | ✅ | ✅ | ✅ | ✅ |
| Paperless | ⬜ | ⬜ | ⬜ | ⬜ |
| Paperless-AI | ⬜ | ⬜ | ⬜ | ⬜ |
| Filebrowser | ⬜ | ⬜ | ⬜ | ⬜ |
| Homepage | ⬜ | ⬜ | ⬜ | ⬜ |
| Teslamate | ⬜ | ⬜ | ⬜ | ⬜ |

### Test Commands

#### From Internal Network

```bash
# Test HTTP to HTTPS redirect
curl -I http://grafana.${SECRET_DOMAIN}

# Test HTTPS access
curl -I https://grafana.${SECRET_DOMAIN}

# Verify certificate
openssl s_client -connect grafana.${SECRET_DOMAIN}:443 -servername grafana.${SECRET_DOMAIN}
```

#### From Tailscale VPN

```bash
# Connect to Tailscale
tailscale up

# Test DNS resolution
nslookup grafana.${SECRET_DOMAIN}

# Test HTTPS access
curl -I https://grafana.${SECRET_DOMAIN}

# Open in browser
open https://grafana.${SECRET_DOMAIN}
```

#### Gateway Health Checks

```bash
# Check Gateway status
kubectl get gateway -n network

# Verify HTTPRoute binding
kubectl get httproute -A

# Check Envoy proxy pods
kubectl get pods -n network -l gateway.envoyproxy.io/owning-gateway-namespace=network

# View Envoy logs
kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=tailscale
```

---

## Troubleshooting

### Issue 1: Gateway Not Getting Tailscale Address

**Symptoms:**
- `kubectl get gateway tailscale -n network` shows `ADDRESS: <pending>`
- No LoadBalancer IP assigned

**Diagnosis:**
```bash
# Check Tailscale operator logs
kubectl logs -n network -l app.kubernetes.io/name=tailscale-operator

# Check envoy service
kubectl get svc -n network | grep tailscale

# Verify loadBalancerClass
kubectl get svc -n network <envoy-tailscale-service> -o yaml | grep loadBalancerClass
```

**Solutions:**
1. **Verify Tailscale operator has LoadBalancer support:**
   ```bash
   kubectl get svc -n network -o yaml | grep -A5 "type: LoadBalancer"
   ```

2. **Check operator permissions (RBAC):**
   ```bash
   kubectl get clusterrole | grep tailscale
   kubectl describe clusterrole tailscale-operator
   ```

3. **Verify `loadBalancerClass: tailscale` in EnvoyProxy:**
   ```bash
   kubectl get envoyproxy envoy-tailscale -n network -o yaml | grep loadBalancerClass
   ```

### Issue 2: HTTPRoute Not Routing Traffic

**Symptoms:**
- HTTPRoute shows `Accepted: False` or `Accepted: Unknown`
- 404 errors when accessing service

**Diagnosis:**
```bash
# Check HTTPRoute status
kubectl describe httproute <name> -n <namespace>

# Look for status conditions:
# - Accepted: True/False
# - ResolvedRefs: True/False
# - ParentRef conditions

# Check if backend service exists
kubectl get svc <service-name> -n <namespace>
```

**Solutions:**
1. **Verify parentRefs point to correct Gateway:**
   ```yaml
   spec:
     parentRefs:
       - name: tailscale    # Must match Gateway name
         namespace: network # Must match Gateway namespace
   ```

2. **Check Gateway allows routes from this namespace:**
   ```bash
   kubectl get gateway tailscale -n network -o yaml
   # Look at: spec.listeners[].allowedRoutes.namespaces.from
   # Should be "All" or match the service namespace
   ```

3. **Verify backend service port:**
   ```bash
   kubectl get svc <service-name> -n <namespace> -o yaml | grep -A5 ports:
   ```

### Issue 3: DNS Not Resolving via Tailscale

**Symptoms:**
- `nslookup grafana.${SECRET_DOMAIN}` fails from Tailscale client
- Services accessible by IP but not hostname

**Diagnosis:**
```bash
# From Tailscale client, check DNS configuration
tailscale status
tailscale debug dns

# Check if MagicDNS is enabled
# Should show custom nameserver for ${SECRET_DOMAIN}
```

**Solutions:**
1. **Verify Split DNS configured in Tailscale admin console:**
   - Go to: https://login.tailscale.com/admin/dns
   - Confirm custom nameserver exists for `${SECRET_DOMAIN}`

2. **Check k8s-gateway / CoreDNS is reachable:**
   ```bash
   # From Tailscale device
   dig @10.90.3.x grafana.${SECRET_DOMAIN}
   ```

3. **Verify ExternalDNS created A records:**
   ```bash
   kubectl logs -n network -l app.kubernetes.io/name=external-dns | grep grafana
   ```

### Issue 4: TLS Certificate Issues

**Symptoms:**
- Certificate warnings in browser
- `curl` shows certificate errors

**Diagnosis:**
```bash
# Check certificate
openssl s_client -connect grafana.${SECRET_DOMAIN}:443 -servername grafana.${SECRET_DOMAIN} 2>/dev/null | openssl x509 -noout -dates -subject

# If using cert-manager, check certificate status
kubectl get certificate -A

# Check Gateway TLS configuration
kubectl get gateway tailscale -n network -o yaml | grep -A10 tls:
```

**Solutions:**

**If using Tailscale TLS (Passthrough):**
- Ensure `tls.mode: Passthrough` in Gateway
- Tailscale automatically provides certificates for `.ts.net` domains
- For custom domains, use cert-manager approach

**If using cert-manager:**
1. **Verify certificate issued:**
   ```bash
   kubectl get certificate envoy-gateway-${SECRET_DOMAIN/./-}-tls -n network
   # Status should be: Ready=True
   ```

2. **Check cert-manager logs:**
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

3. **Force certificate renewal:**
   ```bash
   kubectl delete secret envoy-gateway-${SECRET_DOMAIN/./-}-tls -n network
   flux reconcile helmrelease cert-manager -n cert-manager --with-source
   ```

### Issue 5: Service Accessible Internally but Not via Tailscale

**Symptoms:**
- Service works from LAN: `https://grafana.${SECRET_DOMAIN}`
- Service fails from Tailscale VPN: `https://grafana.${SECRET_DOMAIN}`

**Diagnosis:**
```bash
# Verify HTTPRoute has both parent refs
kubectl get httproute grafana -n observability -o yaml | grep -A5 parentRefs:

# Check if Tailscale Gateway is ready
kubectl get gateway tailscale -n network

# Verify routing from Tailscale device
traceroute grafana.${SECRET_DOMAIN}
```

**Solutions:**
1. **Ensure HTTPRoute has tailscale parentRef:**
   ```yaml
   spec:
     parentRefs:
       - name: internal
         namespace: network
       - name: tailscale  # ← Must be present
         namespace: network
   ```

2. **Verify DNS resolution points to correct gateway:**
   ```bash
   # From Tailscale device
   nslookup grafana.${SECRET_DOMAIN}
   # Should resolve to gateway-envoy.tail<xxxxx>.ts.net or 10.90.3.202
   ```

3. **Check Tailscale Gateway Envoy logs:**
   ```bash
   kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=tailscale -f
   ```

---

## Rollback Procedures

### Rollback: Revert Service to Tailscale Ingress

**If HTTPRoute migration fails for a service:**

```bash
cd ~/home-ops

# Example: Rollback Grafana

# 1. Restore Tailscale Ingress file (from git history)
git checkout HEAD~1 kubernetes/apps/observability/grafana/app/tailscale-ingress.yaml

# 2. Update kustomization to use Ingress
# Edit: kubernetes/apps/observability/grafana/app/kustomization.yaml
# Add: - ./tailscale-ingress.yaml
# Remove: - ./httproute.yaml

# 3. Delete HTTPRoute file
rm kubernetes/apps/observability/grafana/app/httproute.yaml

# 4. Commit and push
git add -u
git commit -m "revert(grafana): Rollback to Tailscale Ingress

HTTPRoute migration unsuccessful, reverting to known good state.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push

# 5. Reconcile
flux reconcile kustomization cluster-apps-observability -n flux-system --with-source
```

### Rollback: Remove Tailscale Gateway Entirely

**If Tailscale Gateway infrastructure needs to be removed:**

```bash
cd ~/home-ops

# 1. Remove Tailscale Gateway from kustomization
# Edit: kubernetes/apps/network/envoy-gateway/app/kustomization.yaml
# Remove: - ./tailscale

# 2. Commit and push
git add -u
git commit -m "revert(envoy-gateway): Remove Tailscale Gateway

Rolling back BYOD Gateway API integration.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push

# 3. Reconcile
flux reconcile kustomization cluster-apps-network -n flux-system --with-source

# 4. Manual cleanup (if needed)
kubectl delete gateway tailscale -n network
kubectl delete envoyproxy envoy-tailscale -n network
kubectl delete gatewayclass envoy-tailscale

# 5. Remove Tailscale LoadBalancer from admin console
# Go to: https://login.tailscale.com/admin/machines
# Find: gateway-envoy
# Click: ... → Remove device
```

---

## Post-Migration Cleanup

### Remove Old Tailscale Ingress Resources

**After all services successfully migrated:**

```bash
cd ~/home-ops

# Verify no services still using Tailscale Ingress
rg -n "ingressClassName.*tailscale" kubernetes/apps

# If output is empty, cleanup is complete ✅

# Remove any remaining ingress files
find kubernetes/apps -name "*tailscale-ingress.yaml" -type f

# Document migration completion
cat <<EOF > .codex/Guides/tailscale-gateway/MIGRATION_COMPLETE.md
# Tailscale Gateway Migration - Completion Log

**Migration Date:** $(date +%Y-%m-%d)
**Migrated Services:** 6
- Grafana
- Paperless
- Paperless-AI
- Filebrowser
- Homepage
- Teslamate

**Architecture:**
- External Gateway: envoy-external (10.90.3.201)
- Internal Gateway: envoy-internal (10.90.3.202)
- Tailscale Gateway: envoy-tailscale (gateway-envoy.tail<xxxxx>.ts.net)

**HTTPRoutes:** All services use dual parent refs (internal + tailscale)

**Status:** ✅ Migration Complete
EOF

git add .codex/Guides/tailscale-gateway/MIGRATION_COMPLETE.md
git commit -m "docs(tailscale-gateway): Document migration completion

All services successfully migrated from Tailscale Ingress to Gateway API HTTPRoutes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

---

## Performance & Monitoring

### Gateway Metrics

**Envoy Gateway exposes Prometheus metrics:**

```bash
# Check ServiceMonitor exists
kubectl get servicemonitor -n network | grep envoy

# Query Prometheus for Tailscale Gateway metrics
# Grafana → Explore → Prometheus
# Queries:
envoy_http_downstream_rq_total{gateway_name="tailscale"}
envoy_http_downstream_rq_time_bucket{gateway_name="tailscale"}
```

### Resource Usage Monitoring

```bash
# Check Tailscale Gateway Envoy pods resource usage
kubectl top pods -n network -l gateway.envoyproxy.io/owning-gateway-name=tailscale

# Review HPA scaling
kubectl get hpa -n network | grep tailscale

# Check for any OOMKilled or CrashLoopBackOff pods
kubectl get pods -n network | grep -E "OOMKilled|CrashLoop|Error"
```

### Recommended Alerts

**If using Prometheus AlertManager:**

```yaml
# Alert if Tailscale Gateway is down
- alert: TailscaleGatewayDown
  expr: kube_deployment_status_replicas_available{deployment="envoy-tailscale"} < 1
  for: 5m
  annotations:
    summary: "Tailscale Gateway has no available replicas"

# Alert if Gateway is not ready
- alert: TailscaleGatewayNotReady
  expr: gateway_api_gateway_status{name="tailscale"} != 1
  for: 5m
  annotations:
    summary: "Tailscale Gateway status is not Ready"
```

---

## Benefits & Trade-offs

### Benefits ✅

1. **Unified Architecture**
   - All traffic types (external, internal, Tailscale) use Gateway API
   - Single configuration model (HTTPRoutes)
   - Consistent observability and monitoring

2. **Multi-Gateway Routing**
   - Services can be exposed to multiple audiences (internal + Tailscale)
   - Single HTTPRoute with multiple `parentRefs`
   - No duplicate configuration

3. **Centralized TLS Management**
   - cert-manager handles certificates for all gateways (if not using Tailscale TLS)
   - Automatic certificate renewal
   - No manual certificate management per service

4. **Better Observability**
   - All traffic flows through Envoy proxies
   - Prometheus metrics for all gateways
   - Centralized logging and tracing

5. **Flexible Traffic Policies**
   - ClientTrafficPolicy and BackendTrafficPolicy apply to all gateways
   - Consistent timeout, retry, and circuit breaking settings
   - Example: `kubernetes/apps/network/envoy-gateway/app/policy/`

### Trade-offs ⚠️

1. **Additional Complexity**
   - Three gateways to manage instead of two
   - More Envoy proxy pods running (resource overhead)
   - Split DNS configuration required

2. **Tailscale Operator Limitations**
   - No native Gateway API support yet (requires BYOD pattern)
   - LoadBalancer integration less mature than Ingress
   - May require `allowUnsupported` flags

3. **DNS Configuration**
   - Requires Tailscale Split DNS setup
   - Internal DNS must be reachable from Tailscale network
   - ExternalDNS must be properly configured

4. **Migration Effort**
   - Manual migration of each service
   - Testing required for each service
   - Coordination with users during migration window

---

## Evidence & Citations

### Files Referenced

| Claim | Source | Confidence |
|-------|--------|------------|
| External Gateway uses Cilium IPAM | `kubernetes/apps/network/envoy-gateway/app/external/gateway.yaml:23` | 🟢 |
| Internal Gateway IP is 10.90.3.202 | `kubernetes/apps/network/envoy-gateway/app/internal/gateway.yaml:19` | 🟢 |
| Tailscale Operator version 1.90.8 | `kubernetes/apps/network/tailscale/operator/app/helmrelease.yaml:12` | 🟢 |
| 6 services use Tailscale Ingress | `rg -n "ingressClassName.*tailscale" kubernetes/apps` | 🟢 |
| Grafana uses standalone Ingress | `kubernetes/apps/observability/grafana/app/tailscale-ingress.yaml` | 🟢 |
| ClientTrafficPolicy exists | `kubernetes/apps/network/envoy-gateway/app/policy/clienttrafficpolicy.yaml` | 🟢 |

### External References

- [Tailscale BYOD Gateway API](https://tailscale.com/kb/1620/kubernetes-operator-byod-gateway-api) - Official Tailscale documentation
- [Envoy Gateway Documentation](https://gateway.envoyproxy.io/latest/) - Gateway API implementation
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) - Specification

---

## Success Criteria

### Phase 1 Complete (Gateway Deployment)
- [x] GatewayClass `envoy-tailscale` created
- [x] EnvoyProxy configured with `loadBalancerClass: tailscale`
- [x] Gateway `tailscale` deployed and shows `Ready: True`
- [x] Tailscale device `gateway-envoy` visible in admin console
- [x] Gateway has Tailscale address: `gateway-envoy.tail<xxxxx>.ts.net`

### Phase 2 Complete (Service Migration)
- [x] Grafana migrated and accessible via both internal and Tailscale
- [x] Paperless migrated and tested
- [x] Paperless-AI migrated and tested
- [x] Filebrowser migrated and tested
- [x] Homepage migrated and tested
- [x] Teslamate migrated and tested
- [x] All Tailscale Ingress resources removed

### Phase 3 Complete (DNS Configuration)
- [x] Split DNS configured in Tailscale admin console
- [x] DNS resolution works from Tailscale clients
- [x] ExternalDNS creating A records for all services

### Final Validation
- [x] All services accessible from internal network
- [x] All services accessible via Tailscale VPN
- [x] TLS certificates valid for all services
- [x] No ingress resources with `ingressClassName: tailscale` remaining
- [x] Gateway metrics visible in Prometheus/Grafana
- [x] Documentation updated

---

## Maintenance Notes

### Regular Review Items

1. **Quarterly:** Review Tailscale Gateway resource usage and adjust HPA settings
2. **Quarterly:** Check for Tailscale Operator updates with improved Gateway API support
3. **Bi-annually:** Review Envoy Gateway updates for new features
4. **Annually:** Re-validate Split DNS configuration

### Update Triggers

- **Tailscale Operator Update:** Test LoadBalancer integration still works
- **Envoy Gateway Update:** Verify Gateway, EnvoyProxy, and HTTPRoute resources compatible
- **New Service Added:** Use HTTPRoute template from this guide
- **Gateway API Spec Update:** Review for breaking changes

### Known Issues & Workarounds

**Issue:** Tailscale Operator may require `allowUnsupported: true` for LoadBalancer integration
**Workaround:** Monitor [Tailscale GitHub](https://github.com/tailscale/tailscale/issues) for native Gateway API support

**Issue:** Split DNS requires internal DNS server reachable from Tailscale network
**Workaround:** Ensure k8s-gateway or CoreDNS service has appropriate network policies

---

## Additional Resources

- [Homelab ARCHITECTURE.md](../Homelab/ARCHITECTURE.md) - Overall cluster architecture
- [Homelab CONTRACTS.md](../Homelab/CONTRACTS.md) - Integration guarantees
- [Envoy Migration Guide](../envoy-migration/) - Previous Ingress → Gateway API migration
- [Tailscale Operator README](../../kubernetes/apps/network/tailscale/operator/readme.md) - Operator setup guide

---

**Document Version:** 1.0
**Last Updated:** 2025-11-24
**Maintained By:** Claude Code (AI Assistant)
**Review Schedule:** Quarterly
