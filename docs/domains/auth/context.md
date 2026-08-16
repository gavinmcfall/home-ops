---
description: "Authentication & Identity — LLM context: apps, routes, storage, flows"
tags: ["Auth", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# Authentication & Identity — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [oauth2-proxy](../../../kubernetes/apps/security/oauth2-proxy) | security | app-template / quay.io/oauth2-proxy/oauth2-proxy | none | none | none | onepassword-connect | none |
| [pocket-id](../../../kubernetes/apps/security/pocket-id) | security | app-template / ghcr.io/pocket-id/pocket-id | id.${SECRET_DOMAIN} · external + internal (dual-homed) | ceph-block 1Gi | VolSync | onepassword-connect | rook-ceph/cluster-apps-rook-ceph, storage/volsync |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

```mermaid
flowchart TB
    client["Client"]

    subgraph Gateway["Envoy Gateway"]
        envoy_securitypolicy["SecurityPolicy (per-route)"]
    end

    pocket_id["pocket-id"]

    subgraph GatewayPattern["Gateway-Intercept Pattern"]
        bentopdf["bentopdf (home, example)"]
    end

    subgraph ProxyPattern["Reverse-Proxy Pattern (dormant)"]
        oauth2_proxy["oauth2-proxy"]
        lighthouse["lighthouse (cortex, example)"]
    end

    client --> envoy_securitypolicy
    envoy_securitypolicy -->|redirects for auth| pocket_id
    pocket_id -->|authenticated| envoy_securitypolicy
    envoy_securitypolicy --> bentopdf

    client -.->|not yet routed| oauth2_proxy
    oauth2_proxy -->|OIDC issuer| pocket_id
    oauth2_proxy -->|upstream| lighthouse

    classDef client fill:#E0E0E0,stroke:#616161,color:#000
    classDef gateway fill:#81D4FA,stroke:#0277BD,color:#000
    classDef auth fill:#90EE90,stroke:#2E7D32,color:#000
    classDef example fill:#FFE082,stroke:#F57C00,color:#000

    class client client
    class envoy_securitypolicy gateway
    class pocket_id,oauth2_proxy auth
    class bentopdf,lighthouse example

    %% MEANING: Two OIDC integration patterns against pocket-id -- (1) Envoy Gateway SecurityPolicy intercepts a route and redirects to pocket-id before forwarding to a backend with no native auth (bentopdf is NETWORKING.md's verified example); (2) oauth2-proxy is a reverse-proxy that itself authenticates against pocket-id as an OIDC client and forwards identity headers to an upstream (lighthouse), currently dormant -- no HTTPRoute points at it yet
    %% COLOR: Gray = client, Blue = gateway, Green = auth domain apps, Yellow = example backends in other domains (not auth-domain members)
    %% GOTCHA: bentopdf and lighthouse are NOT auth-domain apps -- they're included only as NETWORKING.md's documented example and oauth2-proxy's configured (but currently unrouted) upstream, to show what each pattern connects to. The dotted client->oauth2-proxy edge marks that no live HTTPRoute forwards traffic there yet (OAUTH2_PROXY_UPSTREAMS is pre-set for a future cutover).
    %% NAVIGATION: Top-to-bottom -- one pocket-id serves both patterns; the gateway-intercept pattern (left) is live for apps like bentopdf, the reverse-proxy pattern (right) is configured but dormant
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- downloads (inbound): [dashbrr](../../../kubernetes/apps/downloads/dashbrr) and [qui](../../../kubernetes/apps/downloads/qui) authenticate against pocket-id (`OIDC_ISSUER`/`QUI__OIDC_ISSUER` env pointing at `id.${SECRET_DOMAIN}`) per their ExternalSecret templates (see [downloads domain](../downloads/context.md)).
- observability (inbound): [grafana](../../../kubernetes/apps/observability/grafana) authenticates against pocket-id via generic OAuth (`auth_url`/`token_url`/`api_url` pointing at `id.${SECRET_DOMAIN}`) per its HelmRelease (see [observability domain](../observability/context.md)).
- reading (inbound): [bookorbit](../../../kubernetes/apps/entertainment/bookorbit) enables OIDC login against pocket-id (`OIDC_ALLOW_LOCAL_ISSUERS` lets pocket-id's internal-gateway issuer through the SSRF guard) per its HelmRelease env (see [reading domain](../reading/context.md)).
- reading (inbound): [shelfmark](../../../kubernetes/apps/downloads/shelfmark) authenticates via pocket-id OIDC (`OIDC_DISCOVERY_URL` points at `id.${SECRET_DOMAIN}`) per its HelmRelease env (see [reading domain](../reading/context.md)).
<!-- generated:end -->

<!-- curated -->
## Capsules

### EnvoyOIDC

Envoy Gateway's `SecurityPolicy` resource intercepts requests at the gateway, redirects unauthenticated clients to pocket-id, and only forwards authenticated requests to the backend. This gives apps with no native authentication (e.g. bentopdf) SSO for free — the pattern needs an `EndpointSlice` pointing at `pocket-id.security.svc.cluster.local:1411`, a `SecurityPolicy`, an `ExternalSecret` for client credentials, and a `ReferenceGrant` letting the consuming namespace's `SecurityPolicy` reference the `pocket-id` Service cross-namespace. See `docs/ai-context/NETWORKING.md`'s OIDC Authentication section for the full bentopdf example.
<!-- seeded: review -->

### tsidp + Tailscale SSO Guide Is Not Deployed

`docs/Guides/Security/Pocket ID + Tailscale SSO/README.md` walks through pairing pocket-id with Tailscale's `tsidp` bridge for Tailnet-wide SSO, but it is a generic, domain-agnostic tutorial (placeholder hostnames like `yourdomain.com`, pocket-id image pinned to `v1.16.0` against Postgres 17) rather than a description of this cluster. No `kubernetes/apps/security/tsidp/` directory exists, and the live pocket-id deployment runs `v2.11.0` against `postgres18-cluster`. Treat this guide as reference material for a possible future pattern, not current state.
<!-- seeded: review -->

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
