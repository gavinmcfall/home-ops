## Envoy Feature Parity Matrix

| App / Hostname | Namespace | Current NGINX behaviour | Envoy resources needed | Notes / Status |
| -------------- | --------- | ----------------------- | ---------------------- | -------------- |
| Pasta (`pasta.${SECRET_DOMAIN}`) | entertainment | 3600 s proxy read/send timeout; homepage annotations | `HTTPRoute` with `timeouts.request/backendRequest=3600s`; reuse homepage annotations | Ingress removed; production HTTPRoute serving traffic via Envoy |
| Manyfold (`3d.${SECRET_DOMAIN}`) | home | 600 s proxy timeouts; unlimited body size | `HTTPRoute` + timeout override; evaluate max body via `EnvoyPatchPolicy` | Pending |
| Rook RGW (`s3.${SECRET_DOMAIN}`) | rook-ceph | 3600 s timeouts; proxy body size 0; buffering off | `HTTPRoute`; custom patch to disable buffering / raise limits | Pending |
| Syncthing (`sync.${SECRET_DOMAIN}`) | storage | CIDR allowlist for ingress | `EnvoyPatchPolicy` injecting RBAC filter or NetworkPolicy | Pending |
| OAuth2 Proxy (`oauth2-proxy.${SECRET_DOMAIN}`) | network | `/oauth2` upstream terminus; passes auth headers | `HTTPRoute` + auth filter strategy (ext-authz or future Gateway feature) | Pending |
| Home Assistant Tesla key (`hass.${SECRET_DOMAIN}` exact path) | home-automation | `server-snippet` serving static PEM response | `EnvoyPatchPolicy` direct response or static service | Pending |
| External services (Truenas, Unifi, Proxmox) | network | HTTPS backends, forced redirects | `HTTPRoute` + `BackendTLSPolicy` (+ CA bundles as needed) | Pending |
| Voron (`voron.${SECRET_DOMAIN}`) | network | EndpointSlice with HTTPS appProtocol on port 80 | Confirm protocol; `BackendTLSPolicy` if TLS | Pending |
| Flux webhook (`flux-webhook.${SECRET_DOMAIN}`) | flux-system | Plain ingress | Straight `HTTPRoute` | Pending |
| Grafana (tailscale class) | observability | Tailscale-specific ingress class | Determine replacement strategy (Gateway + LB or retain tailscale ingress) | Pending |

### Reusable Policy Building Blocks

- **Timeout profiles** – define shared YAML overlays for 600 s and 3600 s routes; attach via labels on `HTTPRoute` resources.
- **Backend TLS** – per-service `BackendTLSPolicy` templates referencing Secrets/ConfigMaps for CA material when upstream presents self-signed certs.
- **IP allowlists** – `EnvoyPatchPolicy` snippets injecting RBAC filter with configurable CIDRs; evaluate if NetworkPolicy is sufficient for specific apps.
- **Static responses** – either a direct-response patch using `EnvoyPatchPolicy` or a tiny static file service fronted by a standard route.
- **Auth integration** – prototype Envoy ext-authz configuration to replicate nginx `auth-url` semantics until Gateway API gains native auth filters.

Update this matrix as each app is ported or when additional nginx-specific behaviours surface.
