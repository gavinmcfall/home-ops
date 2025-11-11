# Task Breakdown

## Immediate Prerequisites
1. **Capture Envoy selectors** – Describe the labels applied to the Envoy data plane pods/services (from `apps/network/envoy-gateway/app/*/envoyproxy.yaml`) and stash them in a snippet that other charts can import. Every tailscale Service will need the same selector.
2. **Decide on host naming convention** – Confirm whether tailnet hosts remain single-label (e.g., `homepage`) or move to `homepage.${SECRET_DOMAIN}`. Update `tailscale-scope.md` if any names change.
3. **Document operator defaults** – Record the tag(s) (`tag:k8s`), ACL expectations, and whether `tailscale.com/https` should always be `"true"`. This becomes the template for every Service annotation block.

## Core Work
| Order | Work Item | Details |
| --- | --- | --- |
| 1 | **Add `envoy-tailscale` Gateway stack** | Mirror the structure under `apps/network/envoy-gateway/app/{external,internal}` to create `{tailscale}` variants (GatewayClass, Gateway, EnvoyProxy). Service should be `ClusterIP`, listeners default to HTTP, and the Gateway should allow `HTTPRoute` from all namespaces. |
| 2 | **Create reusable Helm values snippet for tailscale Services** | Extend the HelmRelease convention (probably via `_helpers.tpl` or the bjw app chart) to support an optional `values.tailscale.service` item that renders a `Service`. Fields: `enabled`, `name`, `hostname`, `port`, `annotations`. Backend selectors point at Envoy via the captured labels. |
| 3 | **Pilot conversion on a low-risk app** | Use `apps/home/homepage` or `apps/network/echo-server` to prove the flow: add HTTPRoute parentRef → add tailscale Service → delete ingress block. Verify MagicDNS shows the host, and the route works through Envoy. |
| 4 | **Batch migrate the downloads namespace** | Follow the checklist in `tailscale-scope.md`, touching one HelmRelease at a time: add HTTPRoute parentRef, add tailscale Service, drop ingress. Run tests after each (curl via tailnet device). |
| 5 | **Handle remaining namespaces (home, cortex, home-automation)** | Repeat the pattern. Pay attention to charts where the host differs from `.Release.Name` (`qb`, `chat`, `whisper`, `sabnzbd`). |
| 6 | **Delete the `tailscale` ingress class** | Once no HelmRelease references `values.ingress.tailscale`, remove any leftover CRDs or references in docs. Keep the operator for API server proxy / Services. |
| 7 | **Clean up ingress-nginx** | With HTTPRoutes everywhere (including tailnet), evaluate whether ingress-nginx can be shut down entirely. Update `cloudflared` config to point at Envoy load balancers. |

## Validation Checklist
- [ ] `kubectl get svc -n network envoy-tailscale` shows a ClusterIP service and pods are healthy.
- [ ] `tailscale status` lists one entry per host defined in `tailscale-scope.md`, all tagged `k8s`.
- [ ] `kubectl get httproutes --all-namespaces | grep tailscale` confirms every HTTPRoute that needs tailnet access has a `parentRef` pointing at the new gateway.
- [ ] `rg -l 'className: tailscale' kubernetes/apps` returns zero hits.
- [ ] Cloudflare / Unifi DNS stay untouched by tailnet-only hosts (verify via `external-dns` logs).
