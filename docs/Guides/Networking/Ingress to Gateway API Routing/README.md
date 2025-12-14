# Gateway API Routing: A Step-by-Step Guide

A beginner-friendly guide to exposing your Kubernetes applications using Gateway API and Envoy Gateway.

---

## What You'll Learn

By the end of this guide, you'll understand:
- What Gateway API is and why it replaced Ingress
- How to expose your apps to your local network
- How to expose apps to the internet
- How DNS works with routes
- How to troubleshoot routing issues

**Time required**: 15-30 minutes to read, then a few minutes per app

**Difficulty**: Beginner-friendly

**Workflow**: This guide follows GitOps practices. You'll edit files in your repository and push to git - Flux (or ArgoCD) will apply the changes to your cluster automatically. No `kubectl apply` needed!

---

## Part 1: Understanding the Concepts

### What Problem Are We Solving?

You have apps running in Kubernetes. They have internal cluster IPs like `10.96.45.123`. But you want to access them using nice URLs like `https://grafana.yourdomain.com`.

**The journey:**
```
Your browser                                              Your app
     |                                                        |
     |  https://grafana.yourdomain.com                        |
     |                                                        |
     ↓                                                        |
   DNS lookup                                                 |
   "Where is grafana.yourdomain.com?"                         |
     |                                                        |
     ↓                                                        |
   Returns IP: 10.99.8.202                                    |
     |                                                        |
     ↓                                                        |
   Traffic goes to Gateway                                    |
   (at 10.99.8.202)                                           |
     |                                                        |
     ↓                                                        |
   Gateway checks its routes:                                 |
   "grafana.yourdomain.com → send to grafana service"         |
     |                                                        |
     ↓                                                        |
   Traffic forwarded to your app ─────────────────────────────→
```

### The Key Players

| Component | What It Is | Analogy |
|-----------|------------|---------|
| **Gateway** | Entry point for traffic | The front door of a building |
| **HTTPRoute** | Rules for where traffic goes | The building directory ("Floor 3 → Accounting") |
| **Service** | Your app's internal address | A specific office on that floor |
| **external-dns** | Creates DNS records automatically | The receptionist who updates the phone directory |

### Gateway API vs. Ingress (The Old Way)

You might have heard of "Ingress". Gateway API is the newer, better replacement.

| Feature | Ingress (Old) | Gateway API (New) |
|---------|---------------|-------------------|
| Multiple gateways | Hard | Easy |
| Traffic splitting | Limited | Built-in |
| Header matching | Depends on controller | Standard |
| Maintained by | Various | Kubernetes SIG |

**Bottom line**: Gateway API is more powerful and standardized. If you're starting fresh, use Gateway API.

### The Two Gateways in This Setup

This cluster has two "front doors":

| Gateway | IP | Purpose |
|---------|-----|---------|
| `internal` | 10.99.8.202 | Apps accessible from your home network (LAN) |
| `external` | 10.99.8.201 | Apps accessible from the internet (via Cloudflare) |

Most of your apps will use the `internal` gateway. Only apps you want accessible from outside your home use `external`.

---

## Part 2: Before You Start

### Prerequisites

- [ ] Kubernetes cluster with Envoy Gateway installed
- [ ] BGP configured for LoadBalancer IPs (see [L2 to BGP Guide](../L2%20to%20BGP%20Migration/README.md))
- [ ] `external-dns` running (for automatic DNS record creation)
- [ ] `kubectl` access to your cluster

### Verify Your Setup

**Check Envoy Gateway is running:**
```bash
kubectl get pods -n network -l app.kubernetes.io/name=envoy-gateway
```

You should see pods in "Running" state.

**Check the gateways exist:**
```bash
kubectl get gateway -n network
```

You should see `internal` and `external` gateways.

---

## Part 3: Exposing Your First App (Internal Only)

Let's expose an app so you can access it from your home network.

### Scenario

You have an app called `myapp` running in the `default` namespace. It has a service on port 80. You want to access it at `https://myapp.yourdomain.com`.

### Step 3.1: Understand What You're Creating

You need an **HTTPRoute** that tells the gateway:
- **When** someone visits `myapp.yourdomain.com`
- **Send** the traffic to the `myapp` service on port 80

### Step 3.2: Create the HTTPRoute

Create a file called `myapp-route.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp                    # Name of this route
  namespace: default             # Same namespace as your app
  annotations:
    # This tells external-dns to create a DNS record
    internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  # Which gateway should handle this traffic?
  parentRefs:
    - name: internal             # Use the internal gateway
      namespace: network         # Gateways are in the network namespace
      sectionName: https         # Use HTTPS (TLS termination)

  # What hostname should match?
  hostnames:
    - myapp.${SECRET_DOMAIN}     # ${SECRET_DOMAIN} is replaced by Flux

  # Where should matching traffic go?
  rules:
    - backendRefs:
        - name: myapp            # Name of your Kubernetes service
          port: 80               # Port your service listens on
```

### Step 3.3: Add to Your Repository

Place the file in your app's directory:
```
kubernetes/apps/default/myapp/app/httproute.yaml
```

Add it to your kustomization:
```yaml
# kubernetes/apps/default/myapp/app/kustomization.yaml
resources:
  - helmrelease.yaml
  - httproute.yaml   # Add this line
```

### Step 3.4: Commit and Push

```bash
git add kubernetes/apps/default/myapp/
git commit -m "feat(myapp): add HTTPRoute for internal access"
git push
```

### Step 3.5: Wait for Flux to Reconcile

Flux will automatically apply your changes:

```bash
# Watch Flux apply the changes
flux get kustomizations --watch

# Or force an immediate reconcile
flux reconcile kustomization myapp --with-source
```

### Step 3.6: Verify the Route Was Created

```bash
kubectl get httproute myapp -n default
```

Check the route is attached to the gateway:
```bash
kubectl describe httproute myapp -n default
```

Look for:
```
Status:
  Parents:
    Conditions:
      Type:    Accepted
      Status:  True
```

### Step 3.7: Verify DNS Was Created

Wait about 30 seconds for external-dns to create the record, then:

```bash
# Check if DNS resolves (replace with your actual domain)
dig myapp.yourdomain.com @10.90.254.1
```

You should see it resolve to `10.99.8.202` (the internal gateway IP).

### Step 3.8: Test It!

Open your browser and go to `https://myapp.yourdomain.com`

You should see your app!

**✅ Checkpoint**: Can you access your app? Great! You've exposed your first app.

---

## Part 4: The Easier Way (Inline Routes in HelmRelease)

If your app uses the `bjw-s/app-template` Helm chart (most homelab apps do), you can define the route directly in the HelmRelease. This is easier because everything is in one file.

### Example: Adding a Route to a HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
spec:
  # ... other HelmRelease config ...
  values:
    # ... other values ...

    service:
      app:
        controller: myapp
        ports:
          http:
            port: 80

    # This replaces the standalone HTTPRoute file!
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

**Benefits of inline routes:**
- Everything in one file
- `{{ .Release.Name }}` automatically uses the app name
- Route is deleted when you delete the HelmRelease

### When to Use Which?

| Situation | Use |
|-----------|-----|
| App uses bjw-s/app-template | Inline route in HelmRelease |
| App uses different Helm chart | Standalone HTTPRoute file |
| Non-Helm deployment | Standalone HTTPRoute file |
| External service (outside K8s) | Standalone HTTPRoute + Backend |

---

## Part 5: Exposing Apps to the Internet

Want to access an app from outside your home? You need to use the `external` gateway.

### How External Access Works

```
Internet user
      |
      ↓
Cloudflare (your domain's DNS)
      |
      ↓
Cloudflare Tunnel
      |
      ↓
External Gateway (10.99.8.201)
      |
      ↓
Your app
```

### Step 5.1: Create an External Route

The route looks almost identical, but uses `external` instead of `internal`:

```yaml
route:
  app:
    annotations:
      # Note: external-dns, not internal-dns
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external           # Use external gateway
        namespace: network
        sectionName: https
```

### Step 5.2: Verify External DNS

```bash
# Check Cloudflare DNS (use public resolver)
dig myapp.yourdomain.com @1.1.1.1
```

---

## Part 6: Dual-Homing (Internal AND External)

Some apps should be accessible from both inside and outside your home. This is called "dual-homing."

### Why Dual-Home?

- **Same URL everywhere**: `grafana.yourdomain.com` works whether you're home or away
- **Better performance at home**: Traffic stays local instead of going through Cloudflare
- **Works during internet outages**: LAN access still works

### How It Works

Create **two routes** for the same app - one for each gateway:

```yaml
route:
  # Route for external access (from internet)
  external:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external
        namespace: network
        sectionName: https

  # Route for internal access (from LAN)
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

### What Happens with Split-Horizon DNS

| Your Location | DNS Query | Result |
|---------------|-----------|--------|
| At home (LAN) | `grafana.yourdomain.com` | Returns 10.99.8.202 (internal) |
| Away (internet) | `grafana.yourdomain.com` | Returns Cloudflare proxy IP |

Your UDM Pro has a local DNS record that "overrides" the public one when you're home.

---

## Part 7: Adding Homepage Dashboard Integration

If you use the Homepage dashboard, you can add widgets for your apps using annotations.

### Example with Homepage Annotations

```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}

      # Homepage integration
      gethomepage.dev/enabled: "true"
      gethomepage.dev/group: Media          # Dashboard group
      gethomepage.dev/name: Sonarr          # Display name
      gethomepage.dev/icon: sonarr.png      # Icon name
      gethomepage.dev/description: TV Shows # Description

      # Widget configuration (optional)
      gethomepage.dev/widget.type: sonarr
      gethomepage.dev/widget.url: http://sonarr.downloads
      gethomepage.dev/widget.key: "{{ `{{HOMEPAGE_VAR_SONARR_TOKEN}}` }}"

    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

---

## Part 8: Routing to External Services (Outside Kubernetes)

Sometimes you want to route traffic to something that's not in your Kubernetes cluster, like a NAS or a Proxmox server.

### Step 8.1: Create a Backend Resource

First, tell Envoy Gateway where the external service is:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: truenas
  namespace: network
spec:
  endpoints:
    - ip: 10.90.3.10      # IP of your external service
      port: 443            # Port it listens on
```

### Step 8.2: Create the HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: truenas
  namespace: network
  annotations:
    internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: internal
      namespace: network
      sectionName: https
  hostnames:
    - nas.${SECRET_DOMAIN}
  rules:
    - backendRefs:
        - group: gateway.envoyproxy.io   # Different from normal!
          kind: Backend                   # Reference the Backend resource
          name: truenas
          port: 443
```

**Notice**: The `backendRefs` points to a `Backend` resource instead of a Kubernetes `Service`.

---

## Part 9: Common Patterns Quick Reference

### Pattern A: Internal-Only App (Most Common)

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

**Use for**: Sonarr, Radarr, Home Assistant, Paperless, most apps

### Pattern B: External-Only App

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

**Use for**: Webhooks, public-facing services

### Pattern C: Dual-Homed App

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

**Use for**: Grafana, Overseerr, apps you use both at home and away

---

## Part 10: Troubleshooting

### Problem: "Page Not Found" or Connection Timeout

**Step 1**: Check the HTTPRoute exists
```bash
kubectl get httproute -A | grep myapp
```

If nothing shows up, your route wasn't created or is in a different namespace.

**Step 2**: Check the route is accepted by the gateway
```bash
kubectl describe httproute myapp -n NAMESPACE
```

Look for this in the output:
```yaml
Status:
  Parents:
    Conditions:
      Type:    Accepted
      Status:  True      # Should be True!
      Type:    ResolvedRefs
      Status:  True      # Should be True!
```

If `Accepted` is `False`, check the `Message` field for the error.

**Step 3**: Check the service exists and has endpoints
```bash
kubectl get svc myapp -n NAMESPACE
kubectl get endpoints myapp -n NAMESPACE
```

If endpoints show `<none>`, your pods aren't running or aren't matching the service selector.

**Step 4**: Check the pod is running
```bash
kubectl get pods -n NAMESPACE -l app=myapp
```

### Problem: DNS Doesn't Resolve

**Step 1**: Check the annotation is present and correct
```bash
kubectl get httproute myapp -n NAMESPACE -o yaml | grep -A3 annotations
```

You should see either:
- `internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}` (for internal)
- `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}` (for external)

**Step 2**: Check external-dns logs for errors
```bash
# For internal DNS (UDM records)
kubectl logs -n network deploy/external-dns-unifi --tail=100 | grep -i myapp

# For external DNS (Cloudflare records)
kubectl logs -n network deploy/external-dns --tail=100 | grep -i myapp
```

**Step 3**: Test DNS resolution directly
```bash
# For internal DNS
dig myapp.yourdomain.com @10.90.254.1

# For external DNS
dig myapp.yourdomain.com @1.1.1.1
```

**Step 4**: Wait and retry
DNS changes can take 30-60 seconds to propagate. Wait a minute and try again.

### Problem: Works Internally but Not Externally

1. **Check you have both annotations** (one won't work for both)
2. **Check Cloudflare Tunnel is running**:
   ```bash
   kubectl get pods -n network -l app=cloudflared
   ```
3. **Check the external gateway is healthy**:
   ```bash
   kubectl get gateway external -n network
   ```

### Problem: Certificate Errors in Browser

The gateways handle TLS automatically. If you see certificate errors:

```bash
# Check if certificate exists
kubectl get certificate -n network

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager --tail=100
```

---

## Part 11: Quick Reference Card

### The Three Things Every Route Needs

1. **DNS annotation** - tells external-dns to create a DNS record
2. **Hostname** - what URL to respond to
3. **ParentRef** - which gateway to use

### ParentRef Values (Copy-Paste These)

**For internal apps:**
```yaml
parentRefs:
  - name: internal
    namespace: network
    sectionName: https
```

**For external apps:**
```yaml
parentRefs:
  - name: external
    namespace: network
    sectionName: https
```

### DNS Annotations (Copy-Paste These)

**For internal apps (LAN access):**
```yaml
annotations:
  internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
```

**For external apps (internet access):**
```yaml
annotations:
  external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
```

### Common Mistakes to Avoid

| Mistake | Correct |
|---------|---------|
| `name: envoy-internal` | `name: internal` |
| `namespace: default` | `namespace: network` |
| `sectionName: http` | `sectionName: https` |
| Forgetting the DNS annotation | Always add it! |
| Wrong annotation for gateway | `internal-dns` for internal, `external-dns` for external |

### Useful Commands

| Task | Command |
|------|---------|
| List all routes | `kubectl get httproute -A` |
| Check route status | `kubectl describe httproute NAME -n NAMESPACE` |
| Check gateways | `kubectl get gateway -n network` |
| Test internal DNS | `dig app.domain @10.90.254.1` |
| Test external DNS | `dig app.domain @1.1.1.1` |
| Check external-dns logs | `kubectl logs -n network deploy/external-dns-unifi --tail=50` |
| Check gateway pods | `kubectl get pods -n network -l app.kubernetes.io/name=envoy` |

---

## What's Next?

Now that you understand routing:

1. **Add authentication**: See the [Dual-Homing Guide](../dual-homing-access-patterns/README.md) for OIDC and SecurityPolicy
2. **Understand LoadBalancer IPs**: See the [L2 to BGP Guide](../L2%20to%20BGP%20Migration/README.md) if you haven't already
3. **Add more apps**: Each new app just needs a route block!

---

## Further Reading

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/) - Official docs
- [Envoy Gateway Documentation](https://gateway.envoyproxy.io/) - Controller-specific docs
- [External DNS Documentation](https://kubernetes-sigs.github.io/external-dns/) - DNS automation docs
