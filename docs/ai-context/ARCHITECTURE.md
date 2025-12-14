---
description: GitOps architecture overview covering the template pipeline, routing patterns, and operational constraints
tags: ["GitOps", "FluxReconciliation", "MakejinjaTemplates", "GatewayAPI", "TailscaleIngress"]
audience: ["LLMs", "Humans"]
categories: ["Architecture[100%]", "Reference[90%]"]
---

# Homelab Architecture Overview

## Core Pattern

### Capsule: GitOpsReconciliation

**Invariant**
Cluster state converges to match Git; Flux reverts manual changes on next sync.

**Example**
Push HelmRelease to `kubernetes/apps/downloads/prowlarr/`; Flux detects within 5 minutes; cluster deploys. `kubectl edit` gets overwritten on reconciliation.

**Depth**
- Distinction: GitOps is declarative (desired state in Git); `kubectl` is imperative
- Trade-off: Consistency and auditability vs immediate manual changes
- NotThis: `kubectl apply` bypasses GitOps and creates drift
- SeeAlso: `MakejinjaTemplates`, `FluxBootstrap`

---

### Capsule: MakejinjaTemplates

**Invariant**
Jinja2 templates in `bootstrap/templates/` render to `kubernetes/` via Makejinja; edit templates, not output.

**Example**
Edit `bootstrap/templates/kubernetes/apps/network/cloudflared/app/helmrelease.yaml.j2` -> run `task configure` -> generates `kubernetes/apps/network/cloudflared/app/helmrelease.yaml` -> commit and push.
//BOUNDARY: Editing generated files directly loses changes on next `task configure`.

**Depth**
- Distinction: Templates use `#{variable}#` syntax (not `{{`); generated files are plain YAML
- Trade-off: Extra local step but enables config-driven generation
- NotThis: Hand-editing files in `kubernetes/apps/` when a template exists
- SeeAlso: `GitOpsReconciliation`, `SopsEncryption`

---

### Capsule: SopsEncryption

**Invariant**
Secrets are encrypted with SOPS+age in Git; decrypted at runtime by Flux.

**Example**
`secret.sops.yaml.j2` template -> `task configure` renders it -> `task sops:encrypt` encrypts -> Flux decrypts in cluster.
//BOUNDARY: Unencrypted secrets in Git expose credentials publicly.

**Depth**
- Distinction: SOPS encrypts the file; age provides the key; Flux decrypts
- Trade-off: Secure storage but requires age key management
- NotThis: Using plain secrets or committing unencrypted values
- SeeAlso: `MakejinjaTemplates`

---

## Routing Patterns

### Capsule: GatewayAPIRouting

**Invariant**
External/internal traffic routes via Gateway API `HTTPRoute`; ingress-nginx is legacy.

**Example**
```yaml
route:
  app:
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: external
        namespace: network
        sectionName: https
```
//BOUNDARY: Missing `parentRefs` breaks routing entirely.

**Depth**
- Distinction: `external` gateway for public; `internal` gateway for private
- Trade-off: More explicit but requires gateway infrastructure
- SeeAlso: `TailscaleIngress`, `ExternalDNS`

---

### Capsule: TailscaleIngress

**Invariant**
Tailscale VPN access uses `className: tailscale` ingress separately from Gateway API.

**Example**
```yaml
ingress:
  tailscale:
    enabled: true
    className: tailscale
    hosts:
      - host: "{{ .Release.Name }}"
```

**Depth**
- Distinction: Tailscale ingress is for VPN access; Gateway API is for DNS-based access
- Trade-off: Two routing systems but enables secure remote access
- SeeAlso: `GatewayAPIRouting`

---

## Application Patterns

### Capsule: AppTemplateChart

**Invariant**
Apps use `bjw-s/app-template` chart; vendor charts are exceptions, not defaults.

**Example**
```yaml
chart:
  spec:
    chart: app-template
    version: 4.4.0
    sourceRef:
      kind: HelmRepository
      name: bjw-s
      namespace: flux-system
```

**Depth**
- Distinction: app-template provides consistent structure; vendor charts vary
- Trade-off: Learning curve but consistent patterns across all apps
- NotThis: Using random Helm charts without checking if app-template works
- SeeAlso: `HelmReleaseStructure`

---

### Capsule: SecretReference

**Invariant**
Secrets are referenced via `secretRef`; actual values come from SOPS-encrypted files or ExternalSecrets.

**Example**
```yaml
envFrom:
  - secretRef:
      name: prowlarr-secret
```
Secret `prowlarr-secret` is created by SOPS decryption or ExternalSecret sync.

**Depth**
- Distinction: HelmRelease references secrets; doesn't define them inline
- Trade-off: Indirection but keeps secrets out of HelmRelease
- SeeAlso: `SopsEncryption`

---

## Directory Structure

```
home-ops/
├── bootstrap/
│   ├── templates/           # Jinja2 templates (SOURCE)
│   │   └── kubernetes/apps/ # App templates
│   ├── scripts/             # Makejinja plugins
│   └── overrides/           # Template overrides
├── kubernetes/              # GENERATED output
│   ├── apps/                # Rendered app manifests
│   │   ├── cert-manager/
│   │   ├── database/
│   │   ├── downloads/
│   │   ├── entertainment/
│   │   ├── home/
│   │   ├── network/
│   │   ├── observability/
│   │   └── ...
│   ├── bootstrap/           # Flux bootstrap
│   └── flux/                # Flux configuration
├── config.yaml              # Template variables (SECRET - not committed)
├── Taskfile.yaml            # Task runner
└── makejinja.toml           # Template engine config
```

**Key Insight**: `bootstrap/templates/` contains some apps; `kubernetes/apps/` contains all apps (both generated and hand-created).

---

## Namespaces

| Namespace | Purpose | Key Apps |
|-----------|---------|----------|
| actions-runner-system | GitHub Actions | actions-runner-controller |
| cert-manager | TLS certificates | cert-manager |
| database | Data stores | cloudnative-pg, mariadb, dragonfly, mosquitto |
| downloads | Media acquisition | prowlarr, radarr, sonarr, qbittorrent, sabnzbd |
| entertainment | Media serving | plex, jellyfin, audiobookshelf, immich, overseerr |
| external-secrets | Secret sync | external-secrets operator |
| flux-system | GitOps | flux, weave-gitops |
| games | Gaming | romm |
| home | Home apps | homepage, linkwarden, paperless, bookstack, searxng |
| home-automation | IoT | home-assistant, n8n, teslamate |
| kube-system | Core k8s | cilium, coredns, metrics-server |
| network | Networking | cloudflared, external-dns, envoy-gateway, tailscale |
| observability | Monitoring | kube-prometheus-stack, grafana, loki, gatus |
| openebs-system | Storage | openebs |
| plane | Project mgmt | plane |
| rook-ceph | Distributed storage | ceph cluster |
| security | Auth | pocket-id |
| storage | Backup/sync | kopia, volsync, syncthing, snapshot-controller |
| system-upgrade | Updates | tuppr |

---

## Operational Limits

| Resource | Behavior |
|----------|----------|
| Flux reconciliation | Every 30m or on Git push |
| HelmRelease retry | 3 retries with rollback on failure |
| Secret sync | SOPS decrypts on Flux reconcile |

---

## Common Failures

### HelmRelease stuck Reconciling
**Cause**: Missing secret, invalid values, or chart error
**Fix**: Check `flux logs`, ensure secrets exist, validate values

### Pod Pending on storage
**Cause**: PVC not bound or missing
**Fix**: Create PVC or check rook-ceph cluster health

### Route not working
**Cause**: Missing gateway, wrong `parentRefs`, or DNS not configured
**Fix**: Verify gateway exists in `network` namespace, check external-dns logs

---

## Evidence

| Claim | Source | Confidence |
|-------|--------|------------|
| Apps use bjw-s/app-template | `kubernetes/apps/*/helmrelease.yaml` | Verified |
| Gateway API routing pattern | `kubernetes/apps/downloads/prowlarr/app/helmrelease.yaml:90-108` | Verified |
| SOPS encryption for secrets | `Taskfile.yaml:59`, `.taskfiles/Sops/` | Verified |
| Makejinja template pipeline | `makejinja.toml`, `bootstrap/templates/` | Verified |
