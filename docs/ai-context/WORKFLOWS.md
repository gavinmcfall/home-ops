---
description: Operational workflows for deploying apps, managing secrets, and troubleshooting
tags: ["AppDeployment", "SecretManagement", "Troubleshooting", "TaskfileOperations"]
audience: ["LLMs", "Humans"]
categories: ["How-To[100%]", "Workflows[95%]"]
---

# Homelab Workflows

## Deploying a New App

### Prerequisites
- `config.yaml` exists with required variables
- `age.key` exists for SOPS encryption
- Virtual environment set up (`task workstation:venv`)

### Steps

1. **Create app structure**
   ```
   kubernetes/apps/<namespace>/<app>/
   ├── app/
   │   ├── helmrelease.yaml
   │   ├── kustomization.yaml
   │   └── secret.sops.yaml (if needed)
   └── ks.yaml
   ```

2. **Write HelmRelease** using app-template pattern:
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: &app myapp
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
     values:
       controllers:
         myapp:
           containers:
             app:
               image:
                 repository: ghcr.io/org/myapp
                 tag: latest@sha256:...
   ```

3. **Add routing** (Gateway API or Tailscale):
   ```yaml
   # Gateway API (external or internal)
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

   # Tailscale (optional, in addition)
   ingress:
     tailscale:
       enabled: true
       className: tailscale
       hosts:
         - host: "{{ .Release.Name }}"
   ```

4. **Wire into namespace kustomization**:
   ```yaml
   # kubernetes/apps/<namespace>/kustomization.yaml
   resources:
     - ./myapp/ks.yaml
   ```

5. **Validate and deploy**:
   ```bash
   task kubernetes:kubeconform
   git add -A && git commit -m "feat(myapp): initial deployment"
   git push
   ```

### Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| HelmRelease stuck | Missing secret or invalid values | Check `flux logs`, verify secrets |
| Route not working | Missing gateway or DNS | Verify `parentRefs`, check external-dns |
| Pod pending | Missing PVC or node resources | Create PVC, check node capacity |

---

## Adding a Secret

### For SOPS-encrypted secrets

1. **Create secret template** (if using templates):
   ```yaml
   # bootstrap/templates/kubernetes/apps/<ns>/<app>/app/secret.sops.yaml.j2
   apiVersion: v1
   kind: Secret
   metadata:
     name: myapp-secret
   stringData:
     API_KEY: "#{myapp.api_key}#"
   ```

2. **Add values to config.yaml**:
   ```yaml
   myapp:
     api_key: "actual-secret-value"
   ```

3. **Render and encrypt**:
   ```bash
   task configure  # Renders template and encrypts
   ```

### For direct secrets (no template)

1. **Create secret file**:
   ```yaml
   # kubernetes/apps/<ns>/<app>/app/secret.sops.yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: myapp-secret
   stringData:
     API_KEY: "actual-value"
   ```

2. **Encrypt**:
   ```bash
   sops --encrypt --in-place kubernetes/apps/<ns>/<app>/app/secret.sops.yaml
   ```

---

## Updating an Existing App

### If template exists (`bootstrap/templates/`)

1. Edit the `.j2` template file
2. Run `task configure`
3. Review diff in `kubernetes/apps/`
4. Commit and push

### If no template (direct edit)

1. Edit `kubernetes/apps/<ns>/<app>/app/helmrelease.yaml`
2. Run `task kubernetes:kubeconform`
3. Commit and push

### Force Flux reconciliation

```bash
task flux:reconcile
# Or for specific app:
flux reconcile kustomization <name> --with-source
```

---

## Troubleshooting

### Check Flux status

```bash
# All kustomizations
flux get kustomizations

# All HelmReleases
flux get helmreleases -A

# Specific HelmRelease
flux get helmrelease <name> -n <namespace>
```

### View Flux logs

```bash
# Kustomize controller
kubectl logs -n flux-system deploy/kustomize-controller

# Helm controller
kubectl logs -n flux-system deploy/helm-controller

# Source controller
kubectl logs -n flux-system deploy/source-controller
```

### Restart failed HelmReleases

```bash
task flux:hr-restart cluster=main
```

### Force secret sync

```bash
task kubernetes:sync-secrets
# Or specific secret:
task kubernetes:sync-secrets ns=downloads secret=prowlarr-secret
```

### Debug networking

```bash
task kubernetes:network ns=downloads
# Spawns netshoot pod for network debugging
```

---

## Taskfile Commands Reference

| Command | Purpose |
|---------|---------|
| `task configure` | Render templates + encrypt secrets + validate |
| `task kubernetes:kubeconform` | Validate YAML against schemas |
| `task kubernetes:resources` | List all cluster resources |
| `task kubernetes:sync-secrets` | Force ExternalSecret refresh |
| `task kubernetes:network` | Debug pod networking |
| `task flux:bootstrap` | Initial Flux installation |
| `task flux:apply path=<ns>/<app>` | Apply specific app |
| `task flux:reconcile` | Force full reconciliation |
| `task flux:hr-restart` | Restart failed HelmReleases |
| `task sops:encrypt` | Encrypt all SOPS files |

---

## Evidence

| Claim | Source | Confidence |
|-------|--------|------------|
| task configure runs template+encrypt+validate | `Taskfile.yaml:53-60` | Verified |
| flux:apply targets specific apps | `.taskfiles/Flux/Taskfile.yaml:26-51` | Verified |
| kubernetes:sync-secrets forces refresh | `.taskfiles/Kubernetes/Taskfile.yaml:38-55` | Verified |
