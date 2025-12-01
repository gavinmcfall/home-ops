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
| k8s-gateway | 10.90.3.200 | Cluster DNS for pods |
| UDM Pro | 10.90.254.1 | LAN DNS resolver, split-horizon records |
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

Two external-dns instances watch for different annotations:

| Instance | Annotation | Creates Records In |
|----------|------------|-------------------|
| external-dns | `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}` | Cloudflare |
| external-dns-unifi | `internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}` | UDM Pro |

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
