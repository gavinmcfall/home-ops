# 02 – Feature Parity Mapping

> **IaC-only reminder:** Capture all adjustments (new policies, patches, helper manifests) in Git for Flux to apply. Kubectl should only be used for inspection.

Before migrating routes, catalogue ingress behaviours that require Envoy equivalents.

## Inventory
- **Timeouts / Body Size**: `pasta`, `rook-ceph-objectstore`, `manyfold`, etc. (NGINX annotations `proxy-read-timeout`, `proxy-body-size`).
- **HTTPS Upstreams**: `network/external-services` (`truenas`, `unifi`, `proxmox`, `voron`) use `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`.
- **IP Whitelist**: `syncthing` restricts source ranges.
- **Static Response Snippet**: Home Assistant Tesla key uses `server-snippet` to serve a PEM file.
- **OAuth2 Proxy**: `/oauth2` path on `oauth2-proxy` Ingress handles auth for downstream apps.
- **Misc Dashboard Hosts**: Ceph objectstore, S3, etc. rely on external hostnames + wildcard TLS.

## Envoy Solutions
1. **Timeouts & Buffer Sizes**
   - Use `HTTPRoute` `timeouts` and `filters` or attach `EnvoyPatchPolicy` (per-listener/per-route) to configure `request_headers_timeout`, `idle_timeout`, `max_request_bytes`.
   - Document each app’s requirements; create reusable patches if multiple services share settings.

2. **HTTPS Upstream Support**
   - Define `BackendTLSPolicy` CRs pointing at Service backends to enable TLS, optionally disable validation or provide CA bundles.
   - Verify SNI expectations and certificate trust.

3. **IP Whitelisting**
   - Implement via `EnvoyPatchPolicy` to inject RBAC filters with `source-ip` match, or front-load with NetworkPolicy if L4 enforcement suffices.
   - Ensure management subnets retained (10.69.0.0/16, 10.96.0.0/16, 10.90.0.0/16).

4. **Static Responses / Special Paths**
   - Prefer serving static files via dedicated sidecar/ConfigMap + normal routing; as alternative use `DirectResponseAction` via `EnvoyPatchPolicy`.

5. **Authentication Workflows**
   - Validate oauth2-proxy integration: required headers (`X-Auth-Request-*`, `Authorization`) must pass through Envoy.
   - If relying on NGINX `auth-url`, re-create with Envoy `HTTPRouteFilter` `RequestMirror` or `JWT` provider features, or by keeping oauth2-proxy separate and adjusting upstream config.

6. **DNS & Certificates**
   - Track per-host secrets; ensure `ReferenceGrant` coverage and determine whether to consolidate to wildcard certificates.

## Deliverables
- Matrix mapping each application to required Envoy constructs (HTTPRoute, BackendTLSPolicy, PatchPolicy, etc.).
- Template snippets (`yaml` overlays) for common patterns to speed conversion.
- Notes on unsupported behaviours (if any) with proposed alternatives.
