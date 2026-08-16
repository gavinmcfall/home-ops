---
description: "Authentication & Identity — human overview: what it is, how it fits together, how to operate it"
tags: ["Auth", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# Authentication & Identity

<!-- generated:start section=summary -->
The Authentication & Identity domain runs 2 apps across the security namespace.

## Components

| App | What it does | UI |
|---|---|---|
| oauth2-proxy | Reverse-proxy auth gate that authenticates against pocket-id and forwards identity headers to an upstream; currently dormant pending the lighthouse cutover | internal (no route yet) |
| pocket-id | Self-hosted OIDC identity provider — issues SSO logins consumed across the cluster | https://id.${SECRET_DOMAIN} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

```mermaid
flowchart TB
    client["Client"]
    envoy_securitypolicy["Envoy Gateway<br>SecurityPolicy (per-route)"]
    pocket_id["pocket-id"]
    bentopdf["bentopdf (home, example)<br>gateway-intercept pattern"]
    oauth2_proxy["oauth2-proxy<br>reverse-proxy pattern (dormant)"]
    lighthouse["lighthouse (cortex, example)"]

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
    %% NAVIGATION: Top-to-bottom -- one pocket-id serves both patterns; pattern names ride in the node labels (no subgraph boxes, so no edge can cross a group title). The SecurityPolicy round-trip is the live gateway-intercept path; the oauth2-proxy chain is configured but dormant
```
<!-- generated:end -->

<!-- curated -->
## Operating Notes

pocket-id is dual-homed (both the external and internal gateways) — one of the few apps allowed to break the internal-or-external rule, since both LAN clients and Cloudflare-facing clients need to reach the same login page. Most other apps get OIDC "for free" through Envoy Gateway's `SecurityPolicy` pattern rather than talking to pocket-id directly; see the EnvoyOIDC capsule in [context.md](context.md).
<!-- seeded: review -->

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
