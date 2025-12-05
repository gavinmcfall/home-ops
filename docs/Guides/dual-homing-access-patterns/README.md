# Dual-Homing and Access Pattern Guide

This guide documents the access patterns for exposing applications in a home Kubernetes cluster with split-horizon DNS, Envoy Gateway, and OIDC authentication.

## Contents

- [Access Personas](#access-personas)
- [Architecture Overview](#architecture-overview)
- [Split-Horizon DNS](#split-horizon-dns)
- [Routing Patterns](#routing-patterns)
- [OIDC Authentication](#oidc-authentication)
- [Implementation Guide](#implementation-guide)
- [Reference Implementations](#reference-implementations)
- [Deep Dive: Why Persona 6 Requires Route Separation](#deep-dive-why-persona-6-requires-route-separation)
- [What Would Need to Be True](#what-would-need-to-be-true)
- [Deep Dive: Persona 7 - Tailscale Access](#deep-dive-persona-7---tailscale-access)

---

## Access Personas

Seven distinct access patterns describe how users reach applications based on their location and the app's security requirements.

| Persona | User Location | App Type | Authentication | DNS Resolution |
|---------|---------------|----------|----------------|----------------|
| 1 | Internet | OIDC-native | App handles OIDC | Cloudflare |
| 2 | Internet | No native OIDC | Gateway OIDC | Cloudflare |
| 3 | LAN | Internal-only | None (trusted) | UDM Pro |
| 4 | LAN | Internal + sensitive | App handles OIDC | UDM Pro |
| 5 | LAN | External app | Same as external | UDM Pro (split-horizon) |
| 6 | LAN | Gateway-protected | None (bypass) | UDM Pro (split-horizon) |
| 7 | Tailscale | Internal | Tailscale trust | MagicDNS/Internal |

### Persona Details

**Persona 1: External User → OIDC-Native App**
- Example: Grafana with native OIDC configured
- Flow: Internet → Cloudflare Tunnel → External Gateway → App → Pocket-ID redirect
- App handles authentication natively

**Persona 2: External User → Gateway-Protected App**
- Example: BentoPDF (no native auth)
- Flow: Internet → Cloudflare Tunnel → External Gateway → SecurityPolicy OIDC → App
- Envoy Gateway intercepts and handles OIDC before request reaches app

**Persona 3: LAN User → Internal-Only App (No Auth)**
- Example: SearXNG, Homepage, *arr apps
- Flow: LAN → UDM DNS → Internal Gateway → App
- Trusted network, no authentication required

**Persona 4: LAN User → Internal App with OIDC**
- Example: Paperless, Bookstack
- Flow: LAN → UDM DNS → Internal Gateway → App → Pocket-ID redirect
- App handles OIDC even on LAN (sensitive data)

**Persona 5: LAN User → External App via Split-Horizon**
- Example: Grafana accessed from home
- Flow: LAN → UDM DNS (returns internal IP) → Internal Gateway → App
- Same URL, same auth, but traffic stays on LAN

**Persona 6: LAN User → Gateway-Protected App (Auth Bypass)**
- Example: BentoPDF accessed from home
- Flow: LAN → UDM DNS → Internal Gateway (no OIDC) → App
- External requires OIDC, LAN bypasses it

**Persona 7: Tailscale User → Internal App**
- Example: Any internal app via Tailscale
- Flow: Tailscale → Internal Gateway → App
- Tailscale authentication provides trust

---

## Architecture Overview

```
                                    ┌─────────────────────────────────────────┐
                                    │           Kubernetes Cluster            │
                                    │                                         │
┌──────────────┐                    │  ┌─────────────────────────────────┐   │
│   Internet   │                    │  │     External Gateway            │   │
│    Client    │──Cloudflare───────────│     10.90.3.201                 │   │
└──────────────┘    Tunnel          │  │     (OIDC via SecurityPolicy)   │   │
                                    │  └──────────────┬──────────────────┘   │
                                    │                 │                       │
                                    │                 ▼                       │
                                    │           ┌──────────┐                  │
                                    │           │   Apps   │                  │
                                    │           └──────────┘                  │
                                    │                 ▲                       │
                                    │                 │                       │
┌──────────────┐                    │  ┌──────────────┴──────────────────┐   │
│     LAN      │                    │  │     Internal Gateway            │   │
│    Client    │──UDM DNS──────────────│     10.90.3.202                 │   │
└──────────────┘   (direct)         │  │     (No OIDC for bypass)        │   │
                                    │  └─────────────────────────────────┘   │
                                    │                                         │
                                    └─────────────────────────────────────────┘
```

### Key Components

| Component | IP | Purpose |
|-----------|-----|---------|
| External Gateway | 10.90.3.201 | Cloudflare tunnel ingress, OIDC enforcement |
| Internal Gateway | 10.90.3.202 | Direct LAN access, optional auth bypass |
| UDM Pro | 10.90.254.1 | LAN DNS resolver, split-horizon records, upstream DNS for pods |
| Pocket-ID | id.${SECRET_DOMAIN} | OIDC provider (dual-homed) |

---

## Split-Horizon DNS

Split-horizon DNS enables the same hostname to resolve to different IPs based on client location.

### How It Works

**LAN Client requests `app.${SECRET_DOMAIN}`:**
1. Query goes to UDM Pro (local DNS)
2. UDM has A record pointing to internal gateway (10.90.3.202)
3. Client connects directly to internal gateway

**Internet Client requests `app.${SECRET_DOMAIN}`:**
1. Query goes to Cloudflare DNS
2. Cloudflare returns edge IP (proxied)
3. Client connects to Cloudflare edge
4. Cloudflare tunnels to external gateway (10.90.3.201)

### DNS Record Creation

Two external-dns instances manage DNS records:

| Instance | What It Watches | Creates Records In |
|----------|-----------------|-------------------|
| external-dns | HTTPRoutes with `external-dns.alpha.kubernetes.io/target` annotation | Cloudflare |
| external-dns-unifi | ALL HTTPRoutes (no filter) | UDM Pro |

### Benefits

- **No hairpin NAT**: LAN traffic stays local
- **Reduced latency**: Direct connection vs tunnel round-trip
- **Works during outages**: LAN access unaffected by internet issues
- **Single URL**: Users don't need to remember different hostnames

---

## Routing Patterns

### Pattern 1: External-Only

Apps accessible only via Cloudflare tunnel.

```yaml
route:
  app:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - app.${SECRET_DOMAIN}
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
```

**DNS Result:**
- Cloudflare: CNAME to `external.${SECRET_DOMAIN}`
- UDM: No record (forwards to upstream, hits Cloudflare)

### Pattern 2: Internal-Only

Apps accessible only on LAN.

```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - app.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

**DNS Result:**
- Cloudflare: No record
- UDM: A record → 10.90.3.202

### Pattern 3: Dual-Homed

Apps accessible from both internet and LAN with optimal routing.

```yaml
route:
  external:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - app.${SECRET_DOMAIN}
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
  internal:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - app.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

**DNS Result:**
- Cloudflare: CNAME to `external.${SECRET_DOMAIN}`
- UDM: A record → 10.90.3.202

**Key**: Same hostname in both routes. Split-horizon DNS handles routing.

---

## OIDC Authentication

### Gateway-Level OIDC

Envoy Gateway can enforce OIDC for apps without native support using SecurityPolicy.

**Components required:**
1. **Backend** - Points to Pocket-ID service
2. **SecurityPolicy** - Configures OIDC for HTTPRoute
3. **ExternalSecret** - Provides client credentials

### Technical Limitation: No Conditional OIDC

**Problem**: Want OIDC for external access, bypass for LAN.

**Finding**: Envoy processes authentication BEFORE authorization. Cannot conditionally skip OIDC based on source IP.

```
Envoy Filter Chain Order:
1. Authentication (OIDC) → Runs first, redirects unauthenticated
2. Authorization (RBAC/CIDR) → Runs second, after auth complete
```

### Solution: Route Separation

Instead of conditional OIDC, use separate routes:
- External route → SecurityPolicy with OIDC
- Internal route → No SecurityPolicy (open)

Split-horizon DNS ensures:
- Internet clients hit external route → OIDC required
- LAN clients hit internal route → No OIDC

---

## Implementation Guide

### Converting External-Only to Dual-Homed

**Before (external-only):**
```yaml
route:
  app:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
```

**After (dual-homed):**
```yaml
route:
  external:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
  internal:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

### Adding LAN Auth Bypass for Gateway-Protected Apps

For apps like BentoPDF that have SecurityPolicy OIDC:

1. **Convert to dual-homed** (as above)

2. **Update SecurityPolicy targetRef** to only target external route:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-oidc
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: app-external  # Only target external route
```

The internal route has no SecurityPolicy → open access on LAN.

---

## Reference Implementations

### Pocket-ID (Dual-Homed OIDC Provider)

Location: `kubernetes/apps/security/pocket-id/app/helmrelease.yaml:90-108`

The OIDC provider itself must be dual-homed so both external and LAN users can authenticate.

### BentoPDF (Gateway OIDC)

Location: `kubernetes/apps/home/bentopdf/app/`
- `helmrelease.yaml` - Route configuration
- `securitypolicy.yaml` - OIDC enforcement
- `backend.yaml` - Pocket-ID backend reference

### Syncthing (IP-Based Authorization)

Location: `kubernetes/apps/storage/syncthing/app/securitypolicy.yaml`

Example of CIDR-based access control (different from OIDC):
```yaml
authorization:
  rules:
    - action: Allow
      principal:
        clientCIDRs:
          - "10.69.0.0/16"
          - "10.96.0.0/16"
          - "10.90.0.0/16"
```

---

## Validation

After implementing dual-homing:

1. **Check DNS resolution:**
   ```bash
   # From LAN - should return internal gateway
   nslookup app.${SECRET_DOMAIN}
   # Expected: 10.90.3.202

   # From internet - should return Cloudflare
   dig app.${SECRET_DOMAIN} @1.1.1.1
   # Expected: Cloudflare edge IP
   ```

2. **Check HTTPRoutes created:**
   ```bash
   kubectl get httproutes -A | grep app
   # Should see both app-external and app-internal
   ```

3. **Test access:**
   - LAN: Should reach app directly (check browser network tab for IP)
   - External: Should go through Cloudflare (check headers)

4. **For OIDC-protected apps:**
   - LAN: Should load without redirect
   - External: Should redirect to Pocket-ID

---

## Summary

| Goal | Pattern | Implementation |
|------|---------|----------------|
| External + LAN access | Dual-homed routes | Two route definitions, same hostname |
| OIDC on external only | Route separation | SecurityPolicy targets external route only |
| LAN auth bypass | Split-horizon DNS | Internal route has no SecurityPolicy |
| Same URL everywhere | Split-horizon DNS | UDM returns internal IP, Cloudflare returns edge |

---

## Deep Dive: Why Persona 6 Requires Route Separation

This section explains **why** conditional OIDC based on source IP is not possible with Envoy Gateway, and why route separation is the only viable solution.

### The Desired Behavior

The ideal Persona 6 implementation would be:

```
IF source_ip IN lan_cidr:
    skip OIDC, allow request
ELSE:
    require OIDC authentication
```

This would allow a single route with conditional authentication. **This is not possible.**

### Envoy's HTTP Filter Chain Architecture

Envoy processes HTTP requests through a ordered chain of filters. The order is fixed and cannot be changed:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Envoy HTTP Filter Chain                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Request → [1. OAuth2/OIDC] → [2. JWT] → [3. RBAC] → [4. Router] → Backend
│              (authn)           (authn)    (authz)                       │
│                                                                         │
│   ▲                                                                     │
│   │                                                                     │
│   └── Authentication filters run BEFORE authorization filters           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key insight**: The OAuth2 filter (which implements OIDC) is an **authentication** filter. The RBAC filter (which checks source IP/CIDR) is an **authorization** filter. Authentication always runs first.

### What Happens When OIDC is Configured

When a SecurityPolicy with OIDC is attached to an HTTPRoute:

1. **Request arrives** at Envoy
2. **OAuth2 filter activates** (authentication phase)
3. Filter checks for valid OIDC session cookie
4. **If no valid session**: Immediately redirects to IdP (Pocket-ID)
5. Authorization filters **never execute** - request was already redirected

```
Request (no session) → OAuth2 Filter → 302 Redirect to IdP
                           │
                           └── RBAC filter never sees the request
                               Source IP check never happens
```

### Why Authorization Rules Can't Help

You might think: "Configure authorization to allow LAN IPs, deny others, then OIDC handles the denied ones."

This doesn't work because:

1. **OIDC runs first** - unauthenticated requests redirect before reaching authorization
2. **Authorization is post-authentication** - it assumes identity is already established
3. **No "skip authentication" action** - authorization can Allow/Deny, not "skip auth"

```yaml
# This DOES NOT achieve conditional OIDC
spec:
  oidc:
    # ... OIDC config ...
  authorization:
    rules:
      - action: Allow
        principal:
          clientCIDRs: ["10.90.0.0/16"]
```

The above config means:
- All requests must authenticate via OIDC first
- After authentication, LAN IPs are allowed, others denied
- LAN users still have to authenticate - the Allow just permits their authenticated request

### The OAuth2 Filter's Behavior

Envoy's OAuth2 filter has specific behavior that prevents conditional execution:

1. **No bypass mechanism**: The filter has no configuration for "skip if source matches X"
2. **Session-based**: Checks for session cookie, redirects if missing
3. **All-or-nothing**: Either the filter is in the chain or it isn't
4. **No per-request conditions**: Filter configuration is static, not request-dependent

From Envoy's OAuth2 filter documentation:
> "The filter will redirect unauthenticated requests to the authorization endpoint"

There is no "unless source IP matches" clause.

### Why SecurityPolicy Can't Express This

Envoy Gateway's SecurityPolicy CRD maps to Envoy filter configuration:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
spec:
  oidc:         # → Creates OAuth2 filter (authentication)
  authorization: # → Creates RBAC filter (authorization)
```

These are **separate filters** in Envoy's chain. SecurityPolicy provides no way to make one conditional on the other, because Envoy itself doesn't support that.

### The Filter Chain Is Not Programmable

Unlike a general-purpose programming language, Envoy's filter chain is a fixed pipeline:

| What You Want | What Envoy Supports |
|---------------|---------------------|
| `if (lan) skip_oidc else require_oidc` | Not expressible |
| `oidc.bypass_cidrs = ["10.0.0.0/8"]` | No such configuration |
| `authorization.skip_auth_for = [...]` | Authorization is post-auth only |
| Run authorization before authentication | Filter order is fixed |

### External Authorization: The Partial Solution

Envoy supports External Authorization (ext_authz) - delegating auth decisions to an external service. This could theoretically implement conditional logic:

```
Request → ext_authz service → "Allow" or "Deny" or "Require OIDC"
```

However:
- Envoy Gateway's SecurityPolicy doesn't support "require OIDC" as an ext_authz response
- You'd need a custom ext_authz service
- It adds latency and complexity
- Still requires the OAuth2 filter to be in the chain

### Why Route Separation Works

Route separation sidesteps the filter chain limitation entirely:

```
                    ┌─ External Route ─→ [OAuth2] → [RBAC] → Backend
                    │   (has SecurityPolicy)
Split-Horizon DNS ──┤
                    │
                    └─ Internal Route ─→ [RBAC only] → Backend
                        (no SecurityPolicy)
```

- **Different routes = different filter chains**
- External route has OAuth2 filter (OIDC required)
- Internal route has no OAuth2 filter (no OIDC)
- DNS determines which route receives the request
- Each route can have its own SecurityPolicy (or none)

This is **architectural bypass** rather than **conditional logic**.

---

## What Would Need to Be True

For true conditional OIDC (single route, auth based on source IP), these changes would be required:

### Option 1: Envoy Filter Chain Enhancement

**What would need to change in Envoy:**

1. **Conditional filter execution**: Ability to skip filters based on request attributes
   ```yaml
   # Hypothetical - does not exist
   http_filters:
     - name: oauth2
       condition:
         not:
           source_ip: "10.90.0.0/16"
   ```

2. **OAuth2 filter bypass configuration**: Native support for IP-based bypass
   ```yaml
   # Hypothetical - does not exist
   oauth2:
     bypass_cidrs:
       - "10.90.0.0/16"
       - "10.69.0.0/16"
   ```

**Likelihood**: Low. This would be a significant architectural change to Envoy's filter model.

**Upstream issue**: Would require an Envoy enhancement proposal (not just Envoy Gateway).

### Option 2: Envoy Gateway SecurityPolicy Enhancement

**What would need to change in Envoy Gateway:**

1. **Conditional OIDC in SecurityPolicy CRD**:
   ```yaml
   # Hypothetical - does not exist
   apiVersion: gateway.envoyproxy.io/v1alpha1
   kind: SecurityPolicy
   spec:
     oidc:
       provider: ...
       bypassCIDRs:        # New field
         - "10.90.0.0/16"
   ```

2. **Implementation**: Envoy Gateway would need to:
   - Generate an ext_authz filter that checks source IP first
   - Only invoke OAuth2 flow if IP doesn't match bypass list
   - Handle session cookies correctly for both paths

**Likelihood**: Medium. This is implementable but adds complexity.

**Where to request**: [Envoy Gateway GitHub Issues](https://github.com/envoyproxy/gateway/issues)

### Option 3: Pre-Authentication Filter

**What would need to exist:**

A new filter type that runs **before** OAuth2 and can short-circuit authentication:

```
Request → [Pre-Auth Check] → [OAuth2] → [RBAC] → Backend
               │
               └── If source matches trusted CIDR:
                   Skip remaining auth filters, proceed to RBAC
```

**Implementation approaches:**

1. **Lua filter** (runs early in chain):
   ```lua
   -- Hypothetical Lua filter
   function envoy_on_request(handle)
     local source = handle:connection():remoteAddress()
     if matches_cidr(source, "10.90.0.0/16") then
       handle:headers():add("x-auth-bypass", "true")
       -- But OAuth2 filter doesn't respect this header
     end
   end
   ```

   **Problem**: OAuth2 filter doesn't check for bypass headers.

2. **Custom ext_authz that sets authentication context**:
   ```
   ext_authz response:
     - For LAN: Set authenticated identity, skip OAuth2
     - For external: Return "unauthenticated", trigger OAuth2
   ```

   **Problem**: ext_authz can't inject authenticated identity that OAuth2 would accept.

### Option 4: Application-Level Changes

**If apps handled auth themselves:**

1. **Add OIDC support to apps**: Apps like BentoPDF would need native OIDC
   - Then they become Persona 1/4 (app handles OIDC)
   - Gateway-level OIDC becomes unnecessary
   - App can implement its own "trust LAN" logic

2. **Reverse proxy with auth in front of app**:
   - Deploy oauth2-proxy as sidecar
   - Configure oauth2-proxy to bypass LAN IPs
   - oauth2-proxy supports `--trusted-ip` flag

   ```yaml
   # oauth2-proxy supports this
   args:
     - --trusted-ip=10.90.0.0/16
   ```

   **Trade-off**: More complex deployment, per-app configuration.

### Option 5: Network-Level Separation (Current Solution)

**What we do today:**

Use network topology (split-horizon DNS) to route requests to different gateways:

| Requirement | How It's Met |
|-------------|--------------|
| Same URL | Both routes use same hostname |
| OIDC for external | External route has SecurityPolicy |
| No OIDC for LAN | Internal route has no SecurityPolicy |
| Automatic selection | DNS returns different IPs by location |

**Why this works**: We're not trying to make Envoy do conditional auth. We're using network architecture to send requests to different configurations.

### Summary: What Would Enable True Conditional OIDC

| Level | Change Required | Effort | Likelihood |
|-------|-----------------|--------|------------|
| Envoy Core | Conditional filter execution | Very High | Low |
| Envoy Gateway | SecurityPolicy bypass CIDRs | High | Medium |
| Deployment | oauth2-proxy sidecar per app | Medium | High (but complex) |
| Application | Native OIDC in apps | Varies | App-dependent |
| Network | Route separation (current) | Low | Already working |

### Recommendation

**Continue with route separation** (current solution) because:

1. **It works today** - no upstream changes needed
2. **Architecturally clean** - uses DNS and routing, not filter hacks
3. **Maintainable** - standard Gateway API patterns
4. **Scalable** - same pattern works for any app

If Envoy Gateway adds `bypassCIDRs` to SecurityPolicy OIDC configuration in the future, migration would be straightforward: remove internal route, add bypass config to SecurityPolicy.

---

## Deep Dive: Persona 7 - Tailscale Remote Access

Persona 7 provides remote access to internal applications via Tailscale VPN, extending the "trusted LAN" concept to anywhere in the world.

### The Problem Tailscale Solves

Without Tailscale, remote access requires one of:
1. **VPN to home network** - Complex setup, single point of failure
2. **Expose apps externally** - Security risk, requires OIDC for everything
3. **Port forwarding** - Security nightmare, no encryption

Tailscale provides:
- **Zero-config mesh VPN** - Devices connect directly via WireGuard
- **Identity-based access** - Device authentication replaces network location trust
- **No exposed ports** - NAT traversal handles connectivity
- **Split DNS** - Route DNS queries through the VPN for internal resolution

### The Goal: Same URL Everywhere

The ideal experience:
- Type `radarr.nerdz.cloud` from anywhere
- If on LAN → resolves to internal gateway, works
- If on Tailscale → resolves to internal gateway via WireGuard, works
- If on internet (no VPN) → no access (app is internal-only)

**This is achieved with Split DNS, not separate Tailscale ingresses.**

### Recommended Architecture: Split DNS + Internal Gateway

```
┌─────────────────────────────────────────────────────────────────────────┐
│                 Persona 7: Split DNS Architecture                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Remote Device (Tailscale connected)                                   │
│       │                                                                 │
│       │ 1. Browser: radarr.nerdz.cloud                                 │
│       │ 2. OS DNS query                                                 │
│       ▼                                                                 │
│   ┌─────────────────┐                                                   │
│   │ Tailscale Client│  3. Intercepts DNS (Split DNS configured)        │
│   │                 │     for *.nerdz.cloud                            │
│   └────────┬────────┘                                                   │
│            │                                                            │
│            │ 4. Forward DNS query via WireGuard tunnel                 │
│            ▼                                                            │
│   ┌─────────────────┐                                                   │
│   │    UDM Pro      │  5. Resolves radarr.nerdz.cloud                  │
│   │   10.90.254.1   │     Returns: 10.90.3.202 (internal gateway)      │
│   └────────┬────────┘     (record created by external-dns-unifi)       │
│            │                                                            │
│            │ 6. Response travels back via WireGuard                    │
│            ▼                                                            │
│   ┌─────────────────┐                                                   │
│   │ Tailscale Client│  7. Browser now knows IP: 10.90.3.202            │
│   └────────┬────────┘                                                   │
│            │                                                            │
│            │ 8. HTTPS request to 10.90.3.202 via WireGuard             │
│            ▼                                                            │
│   ┌─────────────────┐                                                   │
│   │ Internal Gateway│  9. Matches HTTPRoute, serves request            │
│   │   10.90.3.202   │                                                   │
│   └─────────────────┘                                                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key insight**: The internal gateway (10.90.3.202) is reachable from Tailscale clients via the WireGuard mesh. UDM serves the same DNS records to LAN clients, pods, and Tailscale clients. No separate gateway or per-app ingress needed!

### Why This is Simpler Than Tailscale Ingress

| Approach | Components | New Pods | Complexity |
|----------|------------|----------|------------|
| **Tailscale Ingress** (legacy) | 23 per-app proxy pods | 23 | High |
| **BYOD Gateway** (over-engineered) | New Envoy gateway + Split DNS | 3+ | Medium |
| **Split DNS + Internal Gateway** | Just DNS config | **0** | **Low** |

The Split DNS approach:
- Reuses existing internal gateway
- No new pods or infrastructure
- Same URL works on LAN and Tailscale
- Apps only need internal routes (which most already have)

---

## Configuring Tailscale Split DNS

### Step 1: Access Tailscale DNS Settings

1. Log in to [Tailscale Admin Console](https://login.tailscale.com/admin/dns)
2. Navigate to the **DNS** tab

**Reference**: [Tailscale DNS Documentation](https://tailscale.com/kb/1054/dns)

### Step 2: Add Custom Nameserver with Domain Restriction

1. In the **Nameservers** section, click **Add nameserver**
2. Select **Custom...**
3. Configure:
   - **Nameserver**: `10.90.254.1` (your UDM Pro IP)
   - Check **Restrict to domain**
   - **Domain**: `nerdz.cloud` (your domain, without wildcard)

```
┌─────────────────────────────────────────────────────────────────┐
│  Add nameserver                                           [x]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Nameserver                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 10.90.254.1                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ☑ Restrict to domain                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ nerdz.cloud                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  This nameserver will only be used for DNS queries matching    │
│  *.nerdz.cloud                                                 │
│                                                                 │
│                                        [Cancel]  [Save]         │
└─────────────────────────────────────────────────────────────────┘
```

### Step 3: Enable Override Local DNS (Recommended)

In the DNS settings, enable **Override local DNS** to ensure Tailscale's DNS settings take precedence when connected.

This forces all `*.nerdz.cloud` queries through your UDM, regardless of the device's local DNS configuration.

### Step 4: Ensure Subnet Router is Configured

For Split DNS to work, your UDM (10.90.254.1) must be reachable from Tailscale. This requires a **subnet router** that advertises your home network.

**Check if subnet routes exist:**
```bash
# On your Tailscale node
tailscale status

# Should show advertised routes like:
# 10.90.0.0/16
```

**If not configured**, on a node in your cluster:
```bash
tailscale up --advertise-routes=10.90.0.0/16 --accept-routes
```

Then approve the routes in [Tailscale Admin → Machines](https://login.tailscale.com/admin/machines).

**Reference**: [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets)

### Step 5: Verify Configuration

**From a Tailscale-connected device (away from home):**

```bash
# Check Tailscale DNS status
tailscale status
tailscale debug dns

# Test DNS resolution
dig radarr.nerdz.cloud

# Expected result:
# radarr.nerdz.cloud.    0    IN    A    10.90.3.202
```

**From LAN (without Tailscale):**

```bash
dig radarr.nerdz.cloud

# Expected result (via UDM DNS):
# radarr.nerdz.cloud.    0    IN    A    10.90.3.202
```

Both should return the internal gateway IP - **same URL, same destination**.

---

## Migration: Removing Tailscale Ingresses

Once Split DNS is configured, Tailscale Ingress resources become redundant and can be removed.

### Before (per-app Tailscale proxy):
```yaml
# Each app has its own Tailscale ingress
ingress:
  tailscale:
    enabled: true
    className: tailscale
    hosts:
      - host: radarr  # MagicDNS name only
```

### After (Split DNS, internal route only):
```yaml
# Just the internal route - works for both LAN and Tailscale
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - radarr.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network

# No ingress.tailscale block needed!
```

### Migration Steps

1. **Configure Split DNS** in Tailscale admin (Steps 1-4 above)
2. **Verify subnet routes** are working
3. **Test access** via `radarr.nerdz.cloud` on a Tailscale-connected device
4. **Remove Tailscale ingress** blocks from HelmReleases
5. **Clean up** orphaned Tailscale devices in admin console

### Apps to Migrate (23 total)

| Namespace | Apps |
|-----------|------|
| downloads | qbittorrent, sonarr, sonarr-uhd, sonarr-foreign, radarr, radarr-uhd, prowlarr, bazarr, readarr, whisparr, sabnzbd, autobrr, dashbrr, kapowarr, metube, qui |
| home | paperless, paperless-ai, filebrowser, homepage |
| home-automation | teslamate |
| cortex | whisper, open-webui |

---

## Authentication Model: Tailscale Trust

**Key Insight**: Tailscale authentication replaces network-location trust.

| Traditional Model | Tailscale Model |
|-------------------|-----------------|
| "If you're on LAN, you're trusted" | "If you're on Tailnet, you're trusted" |
| Physical network boundary | Cryptographic identity boundary |
| IP-based access control | Device-based access control |

**Why this is secure:**
1. **Device authentication** - Each device has unique WireGuard keys
2. **User authentication** - Devices tied to authenticated users
3. **ACLs** - Tailscale ACLs can restrict access per-service
4. **No network exposure** - Internal gateway never exposed to internet

---

## Persona 7 Interaction with Other Personas

| Scenario | Result |
|----------|--------|
| Tailscale + Internal-only app (P3) | ✅ Works - Same internal route serves both |
| Tailscale + OIDC-native app (P4) | ✅ Works - App still requires OIDC login |
| Tailscale + Dual-homed app (P5) | ✅ Works - Tailscale uses internal route |
| Tailscale + Gateway-protected (P6) | ✅ Works - Internal route has no OIDC |

**The beauty**: Personas 3, 5, 6, and 7 all use the **same internal gateway**. Split DNS just determines how remote users reach it.

---

## Why Not Use Tailscale for Everything?

**Limitations of Tailscale-only:**
1. **No external access** - Family/friends would need Tailscale accounts
2. **Device limits** - Free tier has device limits
3. **Mobile apps** - Some apps have deep links expecting public URLs

**Best Practice**: Use Tailscale (via Split DNS) for:
- Internal/sensitive apps (downloads, admin interfaces)
- Apps that shouldn't be exposed externally

Use External Gateway for:
- Shared apps (Plex, Jellyfin for family)
- Apps with native OIDC
- Public-facing services

---

## Summary: Persona 7 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Persona 7: Tailscale Remote Access                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Trust Model:     Device identity (Tailscale WireGuard keys)          │
│   Network Path:    WireGuard mesh → Internal Gateway → Service          │
│   DNS:             Split DNS forwards *.nerdz.cloud to UDM (10.90.254.1)│
│   TLS:             cert-manager wildcard (same as LAN)                  │
│   Authentication:  None beyond Tailscale (device = identity)            │
│   URL:             Same as LAN (radarr.nerdz.cloud)                     │
│                                                                         │
│   Key Insight:     Split DNS + WireGuard mesh = LAN from anywhere       │
│                    UDM serves same DNS to LAN, pods, and Tailscale      │
│                    No separate gateway or per-app ingress needed        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## References

- [Tailscale DNS Documentation](https://tailscale.com/kb/1054/dns) - Official Split DNS guide
- [What is Split DNS?](https://tailscale.com/learn/why-split-dns) - Conceptual overview
- [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets) - Making internal networks reachable
- [Homelab Split DNS Guide](https://aottr.dev/posts/2024/08/homelab-using-the-same-local-domain-to-access-my-services-via-tailscale-vpn/) - Real-world example
- [SplitDNS Magic with Tailscale](https://blog.ktz.me/splitdns-magic-with-tailscale/) - Detailed walkthrough
