---
description: Coding standards, naming conventions, and project structure rules
tags: ["NamingConventions", "DirectoryStructure", "CommitGuidelines", "YAMLStyle"]
audience: ["LLMs", "Humans"]
categories: ["Conventions[100%]", "Reference[85%]"]
---

# Repository Conventions

## Directory Structure

### Template vs Generated

| Location | Type | Edit? |
|----------|------|-------|
| `bootstrap/templates/` | Jinja2 templates | Yes - source |
| `kubernetes/apps/` | Generated YAML | Only if no template exists |
| `kubernetes/flux/` | Generated Flux config | Only if no template exists |
| `config.yaml` | Template variables | Yes - not committed |

### App Structure

```
kubernetes/apps/<namespace>/<app>/
├── ks.yaml                    # Flux Kustomization
└── app/
    ├── helmrelease.yaml       # HelmRelease
    ├── kustomization.yaml     # Kustomize resources list
    └── secret.sops.yaml       # Encrypted secrets (optional)
```

### Namespace Organization

| Namespace | Purpose |
|-----------|---------|
| `cert-manager` | TLS certificates |
| `database` | Databases (postgres, mariadb, dragonfly) |
| `downloads` | Media acquisition (arr stack) |
| `entertainment` | Media playback (plex, jellyfin) |
| `flux-system` | GitOps infrastructure |
| `home` | Home utilities (homepage) |
| `home-automation` | IoT (home-assistant) |
| `kube-system` | Core Kubernetes |
| `network` | Networking (gateways, DNS) |
| `observability` | Monitoring (prometheus, grafana) |
| `security` | Auth (pocket-id) |

---

## Naming Conventions

### Files

| Type | Pattern | Example |
|------|---------|---------|
| HelmRelease | `helmrelease.yaml` | `kubernetes/apps/downloads/prowlarr/app/helmrelease.yaml` |
| Kustomization | `kustomization.yaml` | `kubernetes/apps/downloads/prowlarr/app/kustomization.yaml` |
| Flux Kustomization | `ks.yaml` | `kubernetes/apps/downloads/prowlarr/ks.yaml` |
| SOPS secret | `secret.sops.yaml` | `kubernetes/apps/downloads/prowlarr/app/secret.sops.yaml` |
| Template | `*.yaml.j2` | `bootstrap/templates/.../helmrelease.yaml.j2` |

### Resources

| Type | Pattern | Example |
|------|---------|---------|
| App name | lowercase, hyphenated | `prowlarr`, `home-assistant` |
| Secret name | `<app>-secret` | `prowlarr-secret` |
| PVC name | `<app>-data` or descriptive | `prowlarr-config` |
| ConfigMap | `<app>-config` | `prowlarr-config` |

---

## YAML Style

### HelmRelease Pattern

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app prowlarr  # Anchor for reuse
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 4.4.0
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  values:
    # Use anchors for repeated values
    controllers:
      prowlarr:
        containers:
          app:
            image:
              repository: ghcr.io/org/app
              tag: version@sha256:digest  # Always pin with digest
```

### Image Tags

**Always pin images with digest**:
```yaml
image:
  repository: ghcr.io/home-operations/prowlarr
  tag: 2.3.0@sha256:1a8a4b11972b2e62671b49949c622b8cb1110e2b5c77199ac795a6d79fe106e8
```

### Environment Variables

```yaml
env:
  TZ: ${TIMEZONE}           # From cluster-settings
  APP_URL: https://app.${SECRET_DOMAIN}  # Composed
envFrom:
  - secretRef:
      name: app-secret      # From SOPS
```

---

## Git Conventions

### Commit Messages

**Format**: `type(scope): description`

| Type | Use For |
|------|---------|
| `feat` | New app or feature |
| `fix` | Bug fix |
| `chore` | Maintenance, updates |
| `docs` | Documentation |
| `refactor` | Code restructure |

**Examples**:
```
feat(prowlarr): add initial deployment
fix(radarr): correct database connection string
chore(deps): update app-template to 4.4.0
docs(readme): add troubleshooting section
```

### Branch Strategy

- `main` is the deployment branch
- Flux reconciles from `main`
- Use feature branches for complex changes
- Direct commits to `main` for simple changes

---

## Security Practices

### Secrets

- **Never** commit unencrypted secrets
- Use SOPS for all secret files
- Reference secrets via `secretRef`, don't inline
- Store actual values in `config.yaml` (not committed)

### File Permissions

- `age.key` - 600 (owner read/write only)
- `kubeconfig` - 600 (owner read/write only)
- `config.yaml` - 600 (owner read/write only)

### .gitignore

Already configured to exclude:
- `config.yaml`
- `age.key`
- `kubeconfig`
- `.venv/`

---

## Template Conventions

### Makejinja Delimiters

**Non-standard** to avoid conflicts with Helm/Flux:

| Type | Syntax |
|------|--------|
| Variable | `#{variable}#` |
| Block | `#% block %#` |
| Comment | `#| comment |#` |

### Template Variables

Access via `config.yaml`:
```jinja
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
stringData:
  API_KEY: "#{app.api_key}#"
```

---

## Validation

### Before Commit

1. `task configure` - Render templates
2. `task kubernetes:kubeconform` - Validate schemas
3. Review diff in `kubernetes/apps/`

### After Push

1. Check `flux get kustomizations`
2. Check `flux get helmreleases -A`
3. Verify pods running

---

## Evidence

| Claim | Source | Confidence |
|-------|--------|------------|
| Image pinning with digest | `kubernetes/apps/*/helmrelease.yaml` | Verified |
| SOPS encryption required | `.sops.yaml`, `Taskfile.yaml:59` | Verified |
| Makejinja delimiter syntax | `makejinja.toml:12-17` | Verified |
| app-template chart standard | `kubernetes/apps/*/helmrelease.yaml` | Verified |
