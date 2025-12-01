---
description: User access personas for Kubernetes resources covering authentication patterns, traffic flows, and split-horizon DNS requirements
tags: ["AccessPatterns", "SplitHorizon", "DNS", "OIDC", "PocketID", "EnvoyGateway", "Cloudflare", "Tailscale", "Authentication"]
audience: ["LLMs", "Humans"]
categories: ["Architecture[50%]", "Networking[75%]", "Authentication[100%]", "AccessControl[100%]"]
---

# Kubernetes Access Pattern Personas

## Purpose

These personas describe desired access patterns for a home Kubernetes cluster with split-horizon DNS. Each persona represents a distinct combination of user location, resource exposure, and authentication requirements.

---

## Persona 1: External User → OIDC-Native Application

**Context**: User on the internet (mobile data, coffee shop, work network) accessing a publicly exposed application that has native OIDC support.

**Example Applications**: Grafana, Immich, any app with built-in OIDC configuration

**Access Flow**:
- User navigates to `https://grafana.${SECRET_DOMAIN}$`
- Request arrives via Cloudflare Tunnel
- Application redirects to Pocket-ID for authentication
- User authenticates with Pocket-ID
- Application handles session/token natively

**Authentication**: Pocket-ID OIDC (handled by application)

**Key Characteristic**: The application itself manages the OIDC flow - no gateway-level auth interception needed.

---

## Persona 2: External User → Non-OIDC Application (Gateway-Protected)

**Context**: User on the internet accessing a publicly exposed application that has NO native OIDC support.

**Example Applications**: BentoPDF, SearXNG

**Access Flow**:
- User navigates to `https://pdf.${SECRET_DOMAIN}`
- Request arrives via Cloudflare Tunnel
- Envoy Gateway intercepts request before it reaches the application
- Gateway redirects to Pocket-ID for authentication
- After successful auth, gateway allows request through to application
- Application sees an already-authenticated request

**Authentication**: Pocket-ID OIDC (enforced by Envoy Gateway)

**Key Characteristic**: Gateway acts as authentication proxy for apps that can't do OIDC themselves.

---

## Persona 3: LAN User → Internal-Only Application (No Auth)

**Context**: User on the home LAN accessing an application that is only exposed internally and requires no authentication.

**Example Applications**: Home Assistant, internal dashboards, Prometheus, development tools

**Access Flow**:
- User navigates to `https://hass.${SECRET_DOMAIN}`
- DNS resolves to internal gateway
- Gateway routes request directly to application
- No authentication required

**Authentication**: None - trusted network

**Key Characteristic**: Internal-only exposure with implicit trust based on network location. Not accessible from internet at all.

---

## Persona 4: LAN User → Internal Application with OIDC

**Context**: User on the home LAN accessing an internally-exposed application that still requires OIDC authentication (sensitive data, multi-user, audit requirements).

**Example Applications**: Paperless, apps with user-specific data

**Access Flow**:
- User navigates to `https://paperless.${SECRET_DOMAIN}`
- DNS resolves to internal gateway
- Application redirects to Pocket-ID for authentication
- User authenticates with Pocket-ID
- Application handles session/token natively

**Authentication**: Pocket-ID OIDC (handled by application)

**Key Characteristic**: Even though user is on trusted LAN, application sensitivity requires authentication. Pocket-ID must be accessible from LAN.

---

## Persona 5: LAN User → External Application via Internal Path

**Context**: User on the home LAN accessing an application that IS publicly exposed, but the request should stay internal rather than going out to the internet and back through Cloudflare Tunnel.

**Example Applications**: Grafana, Immich - same apps as Persona 1, but accessed from home

**Access Flow**:
- User navigates to `https://grafana.${SECRET_DOMAIN}` (same URL as external)
- Split-horizon DNS resolves to internal gateway IP (not Cloudflare)
- Request routed directly to application internally
- Application redirects to Pocket-ID for authentication (if OIDC-native)
- Normal auth flow proceeds

**Authentication**: Same as external (Pocket-ID OIDC if app supports it)

**Key Characteristic**: Same URL, same auth - but traffic stays on LAN. Reduces latency, avoids Cloudflare tunnel bottleneck, works during internet outages.

---

## Persona 6: LAN User → Gateway-Protected Application (Auth Bypass)

**Context**: User on the home LAN accessing an application that would normally require gateway-level OIDC (Persona 2), but should bypass authentication because the request originates from the trusted LAN.

**Example Applications**: BentoPDF, SearXNG - same apps as Persona 2, but accessed from home

**Access Flow**:
- User navigates to `https://pdf.${SECRET_DOMAIN}` (same URL as external)
- Split-horizon DNS resolves to internal gateway IP
- Gateway recognizes request as LAN-originated
- Gateway bypasses OIDC enforcement
- Request passes directly to application

**Authentication**: None - LAN source is implicitly trusted

**Key Characteristic**: Same URL as external access, but no auth friction when at home. The gateway needs to differentiate between "came from Cloudflare Tunnel" (require auth) and "came from LAN" (trust).

---

## Persona 7: Tailscale User → Internal Application

**Context**: User connected to the Tailnet from anywhere (home, mobile, remote) accessing internally-exposed applications as if they were on the LAN.

**Example Applications**: Any internal-only app (Persona 3), potentially auth-bypass apps (Persona 6)

**Access Flow**:
- User connected to Tailscale
- User navigates to `https://app.${SECRET_DOMAIN}` (or Tailscale MagicDNS name)
- Request arrives via Tailscale interface
- Treated as trusted internal traffic

**Authentication**: Tailscale device authentication provides implicit trust (similar to LAN)

**Key Characteristic**: Extends "trusted LAN" concept to remote access. Tailscale authentication substitutes for network-location trust.

---

## Summary Matrix

| Persona | Location | Resource Type | Auth Method | DNS Resolution |
|---------|----------|---------------|-------------|----------------|
| 1 | Internet | External + OIDC-native | App-level Pocket-ID | Cloudflare |
| 2 | Internet | External + No OIDC | Gateway-level Pocket-ID | Cloudflare |
| 3 | LAN | Internal-only | None | Internal |
| 4 | LAN | Internal + OIDC-native | App-level Pocket-ID | Internal |
| 5 | LAN | External + OIDC-native | App-level Pocket-ID | Internal (split-horizon) |
| 6 | LAN | External + No OIDC | None (bypass) | Internal (split-horizon) |
| 7 | Tailscale | Internal | None (Tailscale trust) | Internal/MagicDNS |

---
