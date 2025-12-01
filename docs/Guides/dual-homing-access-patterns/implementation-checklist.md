# Implementation Checklist

Apps to convert from external-only to dual-homed for full persona coverage.

## Current State

| Persona | Status | Notes |
|---------|--------|-------|
| 1 - External OIDC-native | ✅ | Grafana works |
| 2 - External Gateway OIDC | ✅ | BentoPDF works |
| 3 - LAN Internal (No Auth) | ✅ | SearXNG, *arr apps work |
| 4 - LAN Internal + OIDC | ✅ | Paperless, Bookstack work |
| 5 - LAN via Split-Horizon | ⚠️ | Only pocket-id dual-homed |
| 6 - LAN Auth Bypass | ❌ | Not implemented |
| 7 - Tailscale | ✅ | Many apps have ingress |

---

## Phase 1: Dual-Home External Apps (Persona 5)

Convert these external-only apps to dual-homed by adding internal routes.

### Entertainment (13 apps)

| App | File | Status |
|-----|------|--------|
| audiobookshelf | `kubernetes/apps/entertainment/audiobookshelf/app/helmrelease.yaml` | ⬜ |
| calibre-web | `kubernetes/apps/entertainment/calibre-web/app/helmrelease.yaml` | ⬜ |
| jellyfin | `kubernetes/apps/entertainment/jellyfin/app/helmrelease.yaml` | ⬜ |
| kavita | `kubernetes/apps/entertainment/kavita/app/helmrelease.yaml` | ⬜ |
| overseerr | `kubernetes/apps/entertainment/overseerr/app/helmrelease.yaml` | ⬜ |
| pasta | `kubernetes/apps/entertainment/pasta/app/httproute.yaml` | ⬜ |
| peertube | `kubernetes/apps/entertainment/peertube/app/helmrelease.yaml` | ⬜ |
| plex | `kubernetes/apps/entertainment/plex/app/helmrelease.yaml` | ⬜ |
| stash | `kubernetes/apps/entertainment/stash/app/helmrelease.yaml` | ⬜ |
| tautulli | `kubernetes/apps/entertainment/tautulli/app/helmrelease.yaml` | ⬜ |
| wizarr | `kubernetes/apps/entertainment/wizarr/app/helmrelease.yaml` | ⬜ |

### Cortex (2 apps)

| App | File | Status |
|-----|------|--------|
| litellm | `kubernetes/apps/cortex/litellm/app/helmrelease.yaml` | ⬜ |
| open-webui | `kubernetes/apps/cortex/open-webui/app/helmrelease.yaml` | ⬜ |

### Home (3 apps)

| App | File | Status |
|-----|------|--------|
| linkwarden | `kubernetes/apps/home/linkwarden/app/helmrelease.yaml` | ⬜ |
| manyfold | `kubernetes/apps/home/manyfold/app/helmrelease.yaml` | ⬜ |
| thelounge | `kubernetes/apps/home/thelounge/app/helmrelease.yaml` | ⬜ |

### Home Automation (1 app)

| App | File | Status |
|-----|------|--------|
| home-assistant | `kubernetes/apps/home-automation/home-assistant/app/helmrelease.yaml` | ⬜ |

### Observability (3 apps)

| App | File | Status |
|-----|------|--------|
| grafana | `kubernetes/apps/observability/grafana/app/helmrelease.yaml` | ⬜ |
| gatus | `kubernetes/apps/observability/gatus/app/helmrelease.yaml` | ⬜ |
| kromgo | `kubernetes/apps/observability/kromgo/app/helmrelease.yaml` | ⬜ |

### Games (1 app)

| App | File | Status |
|-----|------|--------|
| romm | `kubernetes/apps/games/romm/app/helmrelease.yaml` | ⬜ |

### Plane (1 app)

| App | File | Status |
|-----|------|--------|
| plane | `kubernetes/apps/plane/plane/app/httproute.yaml` | ⬜ |

### Rook-Ceph (1 app)

| App | File | Status |
|-----|------|--------|
| objectstore | `kubernetes/apps/rook-ceph/rook-ceph/cluster/objectstore-httproute.yaml` | ⬜ |

---

## Phase 2: LAN Auth Bypass (Persona 6)

For gateway-protected apps, add internal route and scope SecurityPolicy to external only.

| App | HelmRelease | SecurityPolicy | Status |
|-----|-------------|----------------|--------|
| bentopdf | `kubernetes/apps/home/bentopdf/app/helmrelease.yaml` | `kubernetes/apps/home/bentopdf/app/securitypolicy.yaml` | ⬜ |

---

## Already Complete

| App | Pattern | Notes |
|-----|---------|-------|
| pocket-id | Dual-homed | OIDC provider, must be accessible from both |
| cloudflared | Infrastructure | DNS endpoint only |
| envoy-gateway | Infrastructure | Gateway itself |

---

## Execution Order

1. **BentoPDF** - Proof of concept for Persona 6
2. **Entertainment apps** - Low risk batch (13 apps)
3. **Remaining apps** - By namespace

---

## Validation Steps

After each change:

```bash
# 1. Validate YAML
task kubernetes:kubeconform

# 2. Check HelmRelease status
flux get hr <app> -n <namespace>

# 3. Check HTTPRoutes created
kubectl get httproutes -n <namespace> | grep <app>

# 4. Test DNS resolution
nslookup <app>.${SECRET_DOMAIN}  # From LAN

# 5. Test access
# LAN: Direct access, no tunnel
# External: Via Cloudflare
```

For BentoPDF specifically:
- LAN: Should NOT redirect to Pocket-ID
- External: SHOULD redirect to Pocket-ID
