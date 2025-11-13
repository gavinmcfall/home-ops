# Design & Guidance – Tailscale + Envoy Gateway

## Current State
- The Tailscale operator (v1.90.6) is installed via `apps/network/tailscale` and implicitly registers an `IngressClass` named `tailscale`. Any Kubernetes `Ingress` referencing that class causes the operator to spin up a proxy pod and a dedicated Tailscale device whose DNS name matches the ingress host.
- 22 different HelmReleases still emit `values.ingress.tailscale.*` blocks (see `tailscale-scope.md`). Each block carries the authoritative hostnames that should be reachable from the tailnet.
- Envoy Gateway is already online with two GatewayClasses (`envoy-external`, `envoy-internal`), two LoadBalancer Services with static IPs, shared TLS certificates, and cross-namespace `HTTPRoute` support. Several workloads (e.g., Sonarr) already expose HTTPRoutes.
- Goal: decommission `Ingress` completely (including the Tailscale class) and manage every HTTP exposure through Envoy Gateway + Gateway API primitives.

## Constraints & Realities
1. **Operator feature set** – As of v1.90 the Tailscale operator only watches `Ingress` resources and annotated `Service` objects (`tailscale.com/expose: "true"`). There is no native Gateway API controller yet, so we cannot expect it to read `HTTPRoute` objects directly.
2. **Per-host DNS automation** – Every tailnet hostname today is provisioned automatically because the operator creates a distinct Tailscale node per ingress host. If we collapse traffic behind a single Envoy Service without recreating this mapping, we would lose those MagicDNS entries or be forced to maintain them manually via the Tailscale admin UI.
3. **TLS termination** – Tailscale terminates TLS for tailnet clients using certs it manages. Traffic that reaches Kubernetes can remain HTTP (what the current ingress setup does), so the Envoy listener for tailnet traffic can safely listen on plain HTTP without additional cert management.
4. **External-DNS interactions** – `external-dns` (Cloudflare + Unifi) watches `HTTPRoute` resources. Any Tailscale-specific HTTPRoute must set `external-dns.alpha.kubernetes.io/exclude: "true"` (or similar) to avoid leaking tailnet-only hostnames into public DNS.

## Options Considered
### 1. Keep Tailscale Ingresses (Status Quo)
- **Pros:** Zero change to operator behavior; hostnames remain automatic; only need to point each ingress backend at the Envoy service.
- **Cons:** Fails the stated goal (“remove ingress entirely”), keeps two competing configuration surfaces (Ingress + HTTPRoute), increases maintenance burden, and prevents us from deleting ingress-nginx.

### 2. Single Envoy Service Exposed via One Tailscale Node
- **Idea:** Annotate the Envoy service with `tailscale.com/expose: "true"` so the operator creates a single proxy (e.g., `envoy-gw`). Point all HTTPRoute hostnames at this one tailnet DNS entry.
- **Pros:** Simple to wire; only one Tailscale node to manage.
- **Cons:** Breaks existing UX because MagicDNS would only create one hostname (the node name). Users would need custom DNS overrides or would be forced to browse via `https://envoy-gw/app`, eliminating host-based routing. Not acceptable without additional automation inside Tailscale.

### 3. Dedicated Envoy Gateway Class + Per-Host Tailscale **Services** (Recommended)
- **Idea:** Launch a third Envoy Gateway stack (`envoy-tailscale`) that runs inside the cluster with a `ClusterIP` service. For every tailnet hostname we need, create a lightweight Kubernetes `Service` that selects the Envoy pods, exposes the HTTP listener port, and is annotated with `tailscale.com/expose: "true"` + `tailscale.com/hostname: <host>`. Tailscale will create one proxy device per service (preserving MagicDNS), while Envoy + HTTPRoutes own all HTTP routing logic.
- **Pros:** Removes all `Ingress` usage, keeps HTTP routing centralized in Envoy, preserves per-host MagicDNS automation, and still leverages supported operator features (Service annotations). Also allows us to attach the same `HTTPRoute` to `internal`, `external`, and `tailscale` gateways via multiple `parentRefs`.
- **Cons:** Requires generating/maintaining N small Services (one per host). We need to ensure the Envoy service can be targeted by many other Services (label selector approach). Slightly more YAML, but still simpler than dual ingress definitions.

## Recommended Architecture
1. **New Gateway stack**
   - Add `envoy-tailscale` `GatewayClass`, `Gateway`, and `EnvoyProxy` definitions alongside the existing internal/external ones under `apps/network/envoy-gateway/app`.
   - Configure the EnvoyProxy’s `envoyService` as `type: ClusterIP` with a stable name (e.g., `envoy-tailscale`) and no load balancer IPs. Set `externalTrafficPolicy: Cluster` and keep listener ports at 80/443 (443 optional if we want mTLS to Envoy later).
   - Give the Gateway two listeners:
     - `http` on port 80 with `allowedRoutes.namespaces.from: All`.
     - Optional `https` listener if we ever decide to terminate TLS inside Envoy for tailnet traffic (can reuse the wildcard cert).
   - Apply the same Backend/ClientTrafficPolicy resources if we want consistent behavior (compression, buffering) with the other gateways.

2. **Per-host Tailscale services**
   - For each hostname in `tailscale-scope.md`, create a `Service` inside the app’s namespace (or centrally in `network`) that selects the Envoy deployment (labels: `app.kubernetes.io/name: envoy-gateway`, etc.) and exposes a single port pointing at the Envoy ClusterIP listener.
   - Annotate each service with at least:
     ```
     tailscale.com/expose: "true"
     tailscale.com/hostname: <host>
     tailscale.com/tags: tag:k8s
     tailscale.com/https: "true"        # if you want Tailscale-managed TLS
     tailscale.com/proxy-class: ???     # optional if we define ProxyClasses
     ```
   - Optional: add `tailscale.com/funnel: "true"` if we ever want to reach these via the public internet (probably not).
   - Consider templating these services inside each HelmRelease (under a `values.tailscale.service` map) so they live with the rest of the app config. Because the selector targets Envoy, the only app-specific pieces are `metadata.name` and the hostname annotation.

3. **HTTPRoute updates**
   - Expand each app’s HTTPRoute (or create one if missing) to include a second `parentRef` pointing at the new `tailscale` Gateway:
     ```yaml
     parentRefs:
       - name: internal
         namespace: network
         sectionName: https
       - name: tailscale
         namespace: network
         sectionName: http   # assuming we only expose HTTP
     ```
   - Ensure every Tailscale-only hostname is listed in `spec.hostnames`. You can keep templated hosts like `{{ .Release.Name }}`; Envoy doesn’t require a FQDN, and MagicDNS will hand out the single-label name.
   - Add `metadata.annotations.external-dns.alpha.kubernetes.io/exclude: "true"` on any HTTPRoute that includes tailnet-only hostnames so Cloudflare/Unifi controllers ignore them.

4. **Operator RBAC / ProxyClass (optional but recommended)**
   - Define a `ProxyClass` CR (if/when the operator supports it) to capture defaults such as ACL tags, auth preferences, and funnel settings. Reference it from every Service via `tailscale.com/proxy-class`.
   - Confirm the `tailscale-user` ClusterRoleBinding still grants the operator permission to impersonate the configured email for node auth.

## Implementation Notes & Gotchas
- **Namespace for the helper Services:** Placing the Services in the same namespace as each workload keeps ownership obvious and makes it easier to template from Helm. The selector just needs to match Envoy’s service labels, so create a small helper `ConfigMap` or values snippet that contains those labels to avoid typos.
- **Selector stability:** The Envoy HelmRelease currently uses the default labels produced by the chart. Inspect the generated `envoy-external` service to copy the exact selector (e.g., `app.kubernetes.io/name: envoy-gateway`). Hard-code that in one place so future chart upgrades don’t break Tailscale Services.
- **Port mapping:** Keep the Service port names unique (e.g., `http`, `https`) even though they all hit Envoy. The operator will expose every named port to Tailscale, so only expose what you intend (likely a single HTTP listener).
- **Testing strategy:** Reuse `apps/network/echo-server` to validate the flow—attach a Tailscale host to the echo route, confirm HTTPRoute binding, and only then roll out to the rest of the apps from `tailscale-scope.md`.
- **Ingress removal order:** Once an app has (a) an HTTPRoute parented to `tailscale` and (b) a Service annotated for Tailscale pointing at Envoy, you can safely delete its `values.ingress.tailscale` block. Keep this order to avoid downtime.
- **DNS hygiene:** Decide whether tailnet hostnames should include `.${SECRET_DOMAIN}` for familiarity or remain single-label (current behavior). Both are possible; the operator just needs the literal string in `tailscale.com/hostname`.

Following this architecture lets Envoy Gateway become the single control plane for HTTP traffic while still leveraging supported Tailscale operator features for secure remote access—all without keeping any legacy Ingress resources around.
