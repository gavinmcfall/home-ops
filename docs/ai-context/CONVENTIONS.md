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
| HelmRelease | `helmrelease.yaml` | `kubernetes/apps/home/filebrowser/app/helmrelease.yaml` |
| Kustomization | `kustomization.yaml` | `kubernetes/apps/home/filebrowser/app/kustomization.yaml` |
| Flux Kustomization | `ks.yaml` | `kubernetes/apps/home/filebrowser/ks.yaml` |
| SOPS secret | `secret.sops.yaml` | `kubernetes/apps/home/filebrowser/app/secret.sops.yaml` |
| Template | `*.yaml.j2` | `bootstrap/templates/.../helmrelease.yaml.j2` |

### Resources

| Type | Pattern | Example |
|------|---------|---------|
| App name | lowercase, hyphenated | `filebrowser`, `home-assistant` |
| Secret name | `<app>-secret` | `filebrowser-secret` |
| PVC name | `<app>-data` or descriptive | `filebrowser-config` |
| ConfigMap | `<app>-config` | `filebrowser-config` |

---

## YAML Style

### HelmRelease Pattern

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app filebrowser  # Anchor for reuse
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
      filebrowser:
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
  repository: docker.io/filebrowser/filebrowser
  tag: v2.45.0@sha256:c751c3a0ed38a8a18b647ae7897b57c793f52a6501a75be2fe4b72d1c27b60ea
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
feat(filebrowser): add initial deployment
fix(pocket-id): correct database connection string
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

---

## Common Mistakes & Correct Patterns

### Quick Reference

| Pattern | Correct | Wrong |
|---------|---------|-------|
| Secret store | `onepassword-connect` | `onepassword`, `1password` |
| Block storage | `ceph-block` | `ceph-block-storage` |
| Filesystem storage | `ceph-filesystem` | `cephfs` |
| Hostname | `{{ .Release.Name }}.${SECRET_DOMAIN}` | `appname.${SECRET_DOMAIN}` |
| Timezone | `${TIMEZONE}` | `Pacific/Auckland` |
| Gateway name | `internal` or `external` | `envoy-internal`, `envoy-external` |
| Gateway namespace | `network` | `default`, `networking` |
| Internal DNS annotation | `internal-dns.alpha.kubernetes.io/target` | missing entirely |
| External DNS annotation | `external-dns.alpha.kubernetes.io/target` | missing entirely |
| Image tag | `v1.0@sha256:abc...` | `latest`, `v1.0` |
| Default UID/GID | `568` | `1000` (unless verified) |

### External Secrets Provider

**Invariant**: ClusterSecretStore name is `onepassword-connect`.

```yaml
# CORRECT
secretStoreRef:
  kind: ClusterSecretStore
  name: onepassword-connect

# WRONG
name: onepassword         # Missing "-connect"
name: 1password-connect   # Wrong prefix
```

### Storage Classes

**Invariant**: Storage classes are `ceph-block` and `ceph-filesystem`.

```yaml
# CORRECT
storageClassName: ceph-block      # Single-instance apps, databases
storageClassName: ceph-filesystem # Shared/multi-instance

# WRONG
storageClassName: ceph-block-storage  # Does not exist
storageClassName: cephfs              # Wrong name
```

### Route Hostnames

**Invariant**: Use Helm template for hostname, not hardcoded app name.

```yaml
# CORRECT
hostnames:
  - "{{ .Release.Name }}.${SECRET_DOMAIN}"

# WRONG - Creates drift if app renamed
hostnames:
  - kopia.${SECRET_DOMAIN}
```

### Route DNS Annotations

**Invariant**: Routes require DNS annotation or they won't get DNS records.

| Exposure | Annotation | Target Value |
|----------|------------|--------------|
| Internal | `internal-dns.alpha.kubernetes.io/target` | `internal.${SECRET_DOMAIN}` |
| External | `external-dns.alpha.kubernetes.io/target` | `external.${SECRET_DOMAIN}` |

```yaml
# CORRECT - Internal app (complete example)
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https

# CORRECT - External app
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

# WRONG - Missing annotation entirely (no DNS record created)
route:
  app:
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

### Security Context

**Invariant**: Default UID/GID is `568`; verify container requirements before changing.

```yaml
# CORRECT
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: 568
    runAsGroup: 568
    fsGroup: 568
    fsGroupChangePolicy: OnRootMismatch
    supplementalGroups: [10000]
    seccompProfile: {type: RuntimeDefault}

# Container-level
containers:
  app:
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: ["ALL"]}
```

### Probe Endpoints

**Invariant**: Check actual app documentation for probe path; don't assume `/`.

| App Type | Probe Path |
|----------|------------|
| Arr apps (Radarr, Sonarr) | `/ping` |
| Go apps | `/healthz` |
| Generic | `/health` |
| 1Password | `/heartbeat` |

```yaml
# WRONG - Assuming "/" works
probes:
  liveness:
    spec:
      httpGet:
        path: /
        port: *port

# CORRECT - Check docs first
probes:
  liveness:
    spec:
      httpGet:
        path: /ping    # Verified for this app
        port: *port
```

### Image Tags

**Invariant**: Always pin images with `@sha256:` digest.

```yaml
# CORRECT
image:
  repository: ghcr.io/home-operations/radarr
  tag: 6.0.4@sha256:73fbdba72dcde5fec16264e63a9daba7829b5c2806a75615463a67117b100de3

# WRONG
tag: latest        # Never use
tag: v1.0.0        # Missing digest
```

### Cluster Variables

**Invariant**: Use `${VARIABLE}` substitution, not hardcoded values.

| Variable | Purpose |
|----------|---------|
| `${TIMEZONE}` | Timezone for apps |
| `${SECRET_DOMAIN}` | Primary domain |
| `${VOLSYNC_STORAGECLASS:-ceph-block}` | VolSync storage class |

```yaml
# CORRECT
env:
  TZ: ${TIMEZONE}

# WRONG
env:
  TZ: Pacific/Auckland
```

### Gateway References

**Invariant**: Gateways are `internal` or `external` in namespace `network`.

| Gateway | Name | Namespace |
|---------|------|-----------|
| Internal apps | `internal` | `network` |
| External apps | `external` | `network` |

```yaml
# CORRECT
parentRefs:
  - name: internal       # or "external"
    namespace: network
    sectionName: https

# WRONG - Common mistakes
parentRefs:
  - name: envoy-internal   # Wrong: don't prefix with "envoy-"
  - name: envoy-external   # Wrong: don't prefix with "envoy-"
  - name: gateway          # Wrong: use "internal" or "external"
    namespace: default     # Wrong: always "network"
    sectionName: http      # Wrong: always "https"
```
