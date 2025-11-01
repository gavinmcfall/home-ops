# 01 – Foundation: Install Envoy Gateway Side-by-Side

> **IaC-only reminder:** Perform every change in this section via Git so Flux applies it. Use `kubectl` solely to observe results (status checks, logs, etc.).

## Goals
- Deploy Envoy Gateway controller and CRDs without disrupting ingress-nginx.
- Define GatewayClasses, EnvoyProxy specs, and Gateways mirroring existing ingress behaviour.
- Prepare supporting systems (External-DNS, cert-manager references, reference grants).

## Tasks
1. **Add Envoy Gateway Helm repo + release**
   - Create `helmrepository` and `helmrelease` resources under `kubernetes/apps/network/envoy-gateway`.
   - Enable CRD installation (e.g., `install.crds: Create`).
   - Ensure the `network` namespace contains necessary RBAC/service accounts.

2. **Define EnvoyProxy specs**
   - Author `EnvoyProxy` CRs for external/internal gateways with:
     - Static service IPs: external `10.90.3.201`, internal `10.90.3.202`.
     - `externalTrafficPolicy: Local` to preserve client IPs.
     - Resource requests/limits comparable to ingress-nginx.
     - Prometheus metrics enabled (`telemetry.metrics.prometheus`).
     - HPA configuration (min 1, max 5, CPU target 60%, 5-minute stabilization windows).

3. **Create GatewayClasses & Gateways**
   - `GatewayClass envoy-external` → references external EnvoyProxy.
   - `GatewayClass envoy-internal` → references internal EnvoyProxy.
   - `Gateway` objects in `network` namespace replicating current listener setup:
     - External gateway: HTTP 80 & HTTPS 443 listeners, wildcard TLS secret `network/${SECRET_DOMAIN/./-}-production-tls`, DNS annotations for external-dns + Cilium IPAM.
     - Internal gateway: same TLS secret, IP 10.90.3.202, restricted to internal use.
     - `allowedRoutes`: HTTP limited to same namespace, HTTPS allows all (matching nginx admission selectors).

4. **Reference Grants & Secrets**
   - Add `ReferenceGrant` objects so routes in other namespaces can reference `network/${SECRET_DOMAIN/./-}-production-tls` and other secrets/configmaps hosted in `network`.
   - Confirm cert-manager Certificates require no change (secret names unchanged).

5. **Update External-DNS configuration**
   - Extend Helm values to include `--source=gateway` and optionally `--gateway-classes=envoy-external,envoy-internal`.
   - Leave `--source=ingress` during coexistence.

6. **Monitoring hooks**
   - Create `ServiceMonitor`/`PodMonitor` resources scraping Envoy Gateway metrics.
   - Note required Grafana dashboard updates once metrics flow.

## Validation Checklist
- `kubectl get pods -n network` shows Envoy Gateway deployment running.
- `kubectl get gatewayclass` and `kubectl get gateway -n network` report `Accepted=True` / `Programmed=True`.
- External-DNS logs include "gateway" source watch.
- Existing nginx Ingress traffic continues uninterrupted.
