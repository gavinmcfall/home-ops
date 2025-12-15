# Dual-Homing and Access Patterns: A Step-by-Step Guide

A beginner-friendly guide to exposing applications with split-horizon DNS, multiple gateways, and OIDC authentication.

---

## What You'll Learn

By the end of this guide, you'll understand:
- How to access the same app from both home (LAN) and the internet with the same URL
- Why split-horizon DNS is essential for a good experience
- How to add OIDC authentication for external access while bypassing it on LAN
- How to use Tailscale for remote access without exposing apps to the internet

**Time required**: 30-45 minutes to read, implementation varies by app

**Difficulty**: Intermediate

**Workflow**: This guide follows GitOps practices. You'll edit files in your repository and push to git - Flux (or ArgoCD) will apply the changes automatically.

**Prerequisites**: Complete the [Gateway API Routing Guide](../networking/gateway-api-routing/) first.

---

## Part 1: Understanding the Problem

### The Typical Homelab Dilemma

You have apps running in your cluster. You want to:
1. Access them from home without going through the internet
2. Access them from outside your home (mobile, travel, etc.)
3. Use the **same URL** everywhere (not `app-internal.domain.com` vs `app.domain.com`)

### What Happens Without Dual-Homing

**Without split-horizon DNS:**
```
You at home type: grafana.yourdomain.com
         ↓
Your router asks Cloudflare DNS
         ↓
Returns Cloudflare's IP (not your local gateway!)
         ↓
Traffic goes: You → Internet → Cloudflare → Back to your house
         ↓
Slower, wasteful, fails if internet is down
```

**With split-horizon DNS:**
```
You at home type: grafana.yourdomain.com
         ↓
Your router asks LOCAL DNS (UDM Pro)
         ↓
Returns your internal gateway IP (10.99.8.202)
         ↓
Traffic goes: You → Internal Gateway → App
         ↓
Fast, direct, works even if internet is down!
```

### The Seven Access Patterns (Personas)

Different apps need different access patterns. Here are the seven "personas":

| # | Who | Where | Auth Needed? | Example |
|---|-----|-------|--------------|---------|
| 1 | Internet user | External | App handles OIDC | Grafana |
| 2 | Internet user | External | Gateway handles OIDC | BentoPDF |
| 3 | LAN user | Internal only | None (trusted network) | Sonarr, Radarr |
| 4 | LAN user | Internal | App handles OIDC | Paperless |
| 5 | LAN user | Dual-homed app | Same as external | Grafana from home |
| 6 | LAN user | Dual-homed + bypass | None (LAN trusted) | BentoPDF from home |
| 7 | Tailscale user | Remote via VPN | Tailscale identity | Any internal app |

**Don't worry about memorizing these!** The patterns below will show you exactly what to do for each situation.

---

## Part 2: How Split-Horizon DNS Works

### The Key Insight

**Split-horizon DNS** means the same domain name returns different IP addresses depending on who's asking.

| Who's Asking | DNS Server Used | Returns |
|--------------|-----------------|---------|
| LAN client | UDM Pro (10.90.254.1) | Internal gateway (10.99.8.202) |
| Internet client | Cloudflare | Cloudflare edge → tunnels to external gateway (10.99.8.201) |

### How DNS Records Get Created

You don't manually create DNS records. Two `external-dns` instances watch your HTTPRoutes:

| Instance | Watches For | Creates Records In |
|----------|-------------|-------------------|
| `external-dns` | `external-dns.alpha.kubernetes.io/target` annotation | Cloudflare |
| `external-dns-unifi` | `internal-dns.alpha.kubernetes.io/target` annotation | UDM Pro |

When you add the right annotation to an HTTPRoute, DNS records are automatically created!

### The Two Gateways

| Gateway | IP | Purpose |
|---------|-----|---------|
| `external` | 10.99.8.201 | Traffic from internet (via Cloudflare Tunnel) |
| `internal` | 10.99.8.202 | Traffic from LAN (direct) |

---

## Part 3: Setting Up a Dual-Homed App

Let's walk through making an app accessible from both LAN and internet.

### Scenario

You have Grafana. Currently it's external-only. You want:
- Same URL (`grafana.yourdomain.com`) to work from home AND away
- Traffic to stay local when you're home
- Grafana handles its own OIDC authentication

### Step 3.1: Understand the Current State

Your current route probably looks like this (external-only):

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

### Step 3.2: Add the Internal Route

Change `app` to `external` and add an `internal` route:

```yaml
route:
  # External route (for internet access)
  external:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
  # Internal route (for LAN access) - ADD THIS
  internal:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"  # Same hostname!
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

**Key points:**
- Both routes use the **same hostname**
- Different `parentRefs` (external vs internal gateway)
- Different DNS annotations (external-dns vs internal-dns)

### Step 3.3: Commit and Push

```bash
git add kubernetes/apps/observability/grafana/app/helmrelease.yaml
git commit -m "feat(grafana): add internal route for dual-homing"
git push
```

### Step 3.4: Wait for Reconciliation

```bash
flux reconcile kustomization observability --with-source
```

### Step 3.5: Verify DNS Records

**Check internal DNS (from LAN):**
```bash
dig grafana.yourdomain.com @10.90.254.1
```
Should return: `10.99.8.202` (internal gateway)

**Check external DNS:**
```bash
dig grafana.yourdomain.com @1.1.1.1
```
Should return: Cloudflare proxy IP

### Step 3.6: Test Access

**From LAN:**
1. Open `https://grafana.yourdomain.com`
2. Check browser dev tools → Network tab → Look at the IP
3. Should connect to `10.99.8.202` (internal gateway)

**From internet (or mobile data):**
1. Open `https://grafana.yourdomain.com`
2. Should go through Cloudflare

**✅ Checkpoint**: Same URL works from both locations? You've dual-homed an app!

---

## Part 4: Understanding OIDC Authentication

### Two Types of OIDC

| Type | How It Works | Example Apps |
|------|--------------|--------------|
| **App-Native OIDC** | App has built-in OIDC support | Grafana, Paperless, Bookstack |
| **Gateway OIDC** | Envoy Gateway handles auth before request reaches app | BentoPDF, simple apps |

### Why Gateway OIDC?

Some apps have no authentication. To protect them externally:
1. Envoy Gateway intercepts the request
2. Checks for valid OIDC session
3. If not authenticated → redirects to Pocket-ID
4. After login → allows request through

### Gateway OIDC Components

```
Request → Envoy Gateway → SecurityPolicy checks OIDC → App
                              ↓
                         If no session:
                         Redirect to Pocket-ID
```

You need three resources:
1. **Backend** - Points to your OIDC provider (Pocket-ID)
2. **SecurityPolicy** - Configures OIDC for the route
3. **ExternalSecret** - Provides client ID/secret

---

## Part 5: LAN Auth Bypass (The Tricky Part)

### The Problem

You have an app protected by Gateway OIDC (like BentoPDF):
- External users should authenticate via OIDC
- LAN users should NOT need to authenticate (trusted network)

**Can we conditionally skip OIDC based on source IP?**

### The Answer: No (But There's a Workaround)

> [!IMPORTANT]
> Envoy processes authentication BEFORE authorization. You cannot skip OIDC based on source IP because the OIDC redirect happens before any IP checks run.

```
Request arrives
     ↓
Authentication (OIDC) runs FIRST
     ↓
No session? → Redirect to IdP (IP never checked!)
     ↓
Authorization (IP checks) would run SECOND
     ↓
But we never get here for unauthenticated requests
```

### The Solution: Route Separation

Instead of conditional OIDC on one route, use **two routes**:
- **External route** → Has SecurityPolicy with OIDC
- **Internal route** → No SecurityPolicy (open access)

Split-horizon DNS ensures:
- Internet clients → External route → OIDC required
- LAN clients → Internal route → No OIDC needed

### Step 5.1: Create Dual-Homed Routes

First, dual-home the app (as shown in Part 3):

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

### Step 5.2: Target SecurityPolicy to External Route Only

Update your SecurityPolicy to only target the external route:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: bentopdf-oidc
  namespace: home
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: bentopdf-external  # Only the external route!
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
    clientID:
      name: "bentopdf-oidc"
    clientSecret:
      name: "bentopdf-oidc"
    redirectURL: "https://bentopdf.${SECRET_DOMAIN}/oauth2/callback"
    scopes: ["openid", "profile", "email"]
```

**Key**: The `name: bentopdf-external` targets only the external HTTPRoute. The internal route has no SecurityPolicy → no OIDC.

### Step 5.3: Verify the Behavior

**From LAN:**
1. Open `https://bentopdf.yourdomain.com`
2. Should load immediately (no login)

**From internet:**
1. Open `https://bentopdf.yourdomain.com`
2. Should redirect to Pocket-ID for login

**✅ Checkpoint**: LAN bypasses auth, external requires it? Success!

---

## Part 6: Tailscale Remote Access

### The Problem Tailscale Solves

You want to access internal apps from outside your home, but:
- Don't want to expose them to the internet
- Don't want OIDC for every app
- Want the same URL to work everywhere

### The Solution: Split DNS + Tailscale

Instead of creating per-app Tailscale proxies, use **Tailscale Split DNS**:

```
You (on Tailscale, away from home)
         ↓
Type: radarr.yourdomain.com
         ↓
Tailscale intercepts DNS query
         ↓
Forwards to your UDM (via WireGuard)
         ↓
UDM returns: 10.99.8.202 (internal gateway)
         ↓
Traffic goes via WireGuard to internal gateway
         ↓
Same experience as being on LAN!
```

### Step 6.1: Configure Tailscale Split DNS

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/dns)
2. Navigate to **DNS** tab
3. Click **Add nameserver** → **Custom...**
4. Configure:
   - **Nameserver**: `10.90.254.1` (your UDM IP)
   - Check **Restrict to domain**
   - **Domain**: `yourdomain.com`
5. Save

### Step 6.2: Ensure Subnet Routes Are Advertised

Your UDM needs to be reachable from Tailscale. A node in your network must advertise subnet routes:

```bash
# On a Tailscale-connected node in your cluster
tailscale up --advertise-routes=10.90.0.0/16 --accept-routes
```

Then approve the routes in [Tailscale Admin → Machines](https://login.tailscale.com/admin/machines).

### Step 6.3: Verify

**From a Tailscale-connected device (away from home):**

```bash
# Check DNS works
dig radarr.yourdomain.com

# Should return: 10.99.8.202 (internal gateway)
```

Then open `https://radarr.yourdomain.com` in your browser - it should work!

### Why This Is Better Than Tailscale Ingress

| Approach | Pods Needed | Complexity |
|----------|-------------|------------|
| Per-app Tailscale Ingress | 1 per app (23 apps = 23 pods) | High |
| Split DNS | 0 extra pods | **Low** |

Split DNS reuses your existing internal gateway and routes. No new infrastructure needed!

---

## Part 7: Troubleshooting

### Problem: LAN Traffic Going Through Cloudflare

**Symptoms**: From home, traffic goes to Cloudflare instead of directly to internal gateway

**Check 1**: Is internal DNS record created?
```bash
dig app.yourdomain.com @10.90.254.1
```
Should return `10.99.8.202`. If not, check the `internal-dns` annotation.

**Check 2**: Is your device using UDM for DNS?
```bash
# macOS/Linux
cat /etc/resolv.conf

# Or check your router DHCP settings
```

**Check 3**: Check external-dns-unifi logs:
```bash
kubectl logs -n network deploy/external-dns-unifi --tail=100
```

### Problem: External Access Not Working

**Symptoms**: App works on LAN but not from internet

**Check 1**: Is external DNS record created?
```bash
dig app.yourdomain.com @1.1.1.1
```

**Check 2**: Is Cloudflare Tunnel running?
```bash
kubectl get pods -n network -l app=cloudflared
```

**Check 3**: Check external gateway is healthy:
```bash
kubectl get gateway external -n network
kubectl describe gateway external -n network
```

### Problem: OIDC Redirect Loop

**Symptoms**: Keeps redirecting to Pocket-ID, never completes login

**Check 1**: Is Pocket-ID itself dual-homed?
The OIDC provider must be reachable from wherever you're authenticating.

**Check 2**: Check callback URL matches:
```bash
kubectl get securitypolicy -n <namespace> -o yaml | grep redirectURL
```

**Check 3**: Check Pocket-ID logs:
```bash
kubectl logs -n security deploy/pocket-id --tail=100
```

### Problem: Tailscale DNS Not Working

**Symptoms**: DNS queries don't resolve when on Tailscale

**Check 1**: Is Split DNS configured in Tailscale admin?

**Check 2**: Are subnet routes approved?
```bash
tailscale status
```
Look for your home subnet (10.90.0.0/16) in the routes.

**Check 3**: Can you reach the UDM?
```bash
ping 10.90.254.1
```

---

## Part 8: Quick Reference

### Route Patterns (Copy-Paste)

**Internal-Only (Persona 3):**
```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

**External-Only (Persona 1, 2):**
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

**Dual-Homed (Persona 5, 6):**
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

### SecurityPolicy for External-Only OIDC

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: <app>-oidc
  namespace: <namespace>
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <app>-external  # Only external!
  oidc:
    provider:
      backendRefs:
        - group: gateway.envoyproxy.io
          kind: Backend
          name: <app>-oidc-provider
          port: 1411
      issuer: "https://id.${SECRET_DOMAIN}"
      authorizationEndpoint: "https://id.${SECRET_DOMAIN}/authorize"
      tokenEndpoint: "https://id.${SECRET_DOMAIN}/api/oidc/token"
    clientID:
      name: "<app>-oidc"
    clientSecret:
      name: "<app>-oidc"
    redirectURL: "https://<app>.${SECRET_DOMAIN}/oauth2/callback"
    scopes: ["openid", "profile", "email"]
```

### Backend for OIDC Provider

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: <app>-oidc-provider
  namespace: <namespace>
spec:
  endpoints:
    - fqdn:
        hostname: pocket-id.security.svc.cluster.local
        port: 1411
```

### Decision Tree: Which Pattern?

```
Is the app sensitive/needs auth?
├── No → Internal-only (Persona 3)
└── Yes
    ├── App has native OIDC?
    │   ├── Yes → Dual-homed, app handles auth (Persona 4/5)
    │   └── No → Need Gateway OIDC
    │       └── Want LAN to bypass OIDC?
    │           ├── Yes → Dual-homed + SecurityPolicy on external only (Persona 6)
    │           └── No → External-only with SecurityPolicy (Persona 2)
```

### Useful Commands

| Task | Command |
|------|---------|
| Check internal DNS | `dig app.domain @10.90.254.1` |
| Check external DNS | `dig app.domain @1.1.1.1` |
| List all HTTPRoutes | `kubectl get httproute -A` |
| Check SecurityPolicies | `kubectl get securitypolicy -A` |
| Check external-dns logs | `kubectl logs -n network deploy/external-dns-unifi` |
| Check Tailscale status | `tailscale status` |

---

## Summary

| Goal | Solution |
|------|----------|
| Same URL from LAN and internet | Dual-homed routes + split-horizon DNS |
| OIDC for external, open on LAN | SecurityPolicy targets external route only |
| Remote access without exposure | Tailscale Split DNS |
| Reduce complexity | Internal gateway serves LAN, Tailscale, and pods |

---

## Further Reading

- [Gateway API Routing Guide](../networking/gateway-api-routing/) - Basic routing concepts
- [Tailscale Split DNS](https://tailscale.com/kb/1054/dns) - Official documentation
- [Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/docs/tasks/security/oidc/) - OIDC configuration
