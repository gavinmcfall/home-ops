# 03 – Route Migration & Testing

> **IaC-only reminder:** Disable Ingresses and add Gateway routes through Git commits. Use kubectl commands only to verify state and testing outcomes.

## Strategy
- Migrate services incrementally, starting with low-risk endpoints (internal-only services) before business-critical apps.
- Keep nginx Ingress resources in place until each route is validated through Envoy.

## Steps per Application
1. **Disable Helm Ingress (if applicable)**
   - For bjw-s `app-template` charts, set `values.ingress.*.enabled: false`.
   - Commit change alongside new Gateway manifests to avoid dual ownership.

2. **Author HTTPRoute (or GRPCRoute/TLSRoute)**
   - Place under the app directory (e.g., `.../app/httproute.yaml`).
   - `parentRefs` → `network/external` or `network/internal` gateway with relevant `sectionName` (`https` or `http`).
   - Include `hostnames`, `matches`, `backendRefs`, and `filters` replicating original paths/annotations.
   - Attach `BackendTLSPolicy`/`EnvoyPatchPolicy` as identified in feature mapping.

3. **Create canary hostname (optional but recommended)**
   - Add secondary host (e.g., `envoy-test.<app>.${SECRET_DOMAIN}`) to validate connectivity without disturbing production.
   - Update External-DNS annotations accordingly.

4. **Deploy & Validate**
   - Ensure Flux reconciles new manifests (`flux reconcile ks <name>`).
   - Confirm DNS record exists and resolves to the Envoy IP.
   - Validate functionality: HTTP responses, auth redirects, file uploads, large transfers, etc.
   - Monitor Envoy logs/metrics for errors.

5. **Promote to Production Hostname**
   - Update the HTTPRoute to include production host; remove canary if no longer needed.
   - Delete old Ingress resource (or leave disabled in Helm values).
   - Verify External-DNS swaps record to Envoy IP.

## Order Suggestions
1. Internal services (`syncthing`, `truenas`, `proxmox`, etc.).
2. External dashboards (`rook-ceph`, `grafana via tailscale` remains separate).
3. User-facing apps (`pasta`, media services, oauth2-proxy-backed routes).
4. Webhooks (`flux-webhook`) – ensure GitHub config updated if endpoint changes.

## Tracking
- Maintain a migration checklist (spreadsheet or YAML) with columns: App, Route created, Feature parity applied, Canary tested, Production cutover, Old ingress removed.
- Note any deviations or issues per service for post-mortem documentation.
