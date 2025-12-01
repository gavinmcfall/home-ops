# Pattern Quick Reference

Copy-paste patterns for common routing configurations.

---

## External-Only Route

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

---

## Internal-Only Route

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

---

## Dual-Homed Route (Split-Horizon)

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

---

## Internal + Tailscale

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
ingress:
  tailscale:
    enabled: true
    className: tailscale
    hosts:
      - host: "{{ .Release.Name }}"
```

---

## OIDC SecurityPolicy (External Only)

When dual-homing a gateway-protected app, target only the external route:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-oidc
  namespace: <namespace>
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <app>-external  # Only external route
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
    clientIDRef:
      name: "<app>-oidc"
    clientSecret:
      name: "<app>-oidc"
    redirectURL: "https://<app>.${SECRET_DOMAIN}/oauth2/callback"
    scopes: ["openid", "profile", "email"]
```

---

## Backend for OIDC Provider

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

---

## IP-Based Authorization (Not OIDC)

For internal-only apps needing IP restriction:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-ip-allow
  namespace: <namespace>
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <app>
  authorization:
    defaultAction: Deny
    rules:
      - action: Allow
        principal:
          clientCIDRs:
            - "10.90.0.0/16"   # LAN
            - "10.69.0.0/16"   # Pods
            - "10.96.0.0/16"   # Services
```

---

## Gateway Reference

| Gateway | IP | Use For |
|---------|-----|---------|
| external | 10.90.3.201 | Internet access via Cloudflare |
| internal | 10.90.3.202 | Direct LAN access |

---

## Annotation Reference

| Annotation | DNS Provider | Creates |
|------------|--------------|---------|
| `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}` | Cloudflare | CNAME |
| `internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}` | UDM Pro | A record |
