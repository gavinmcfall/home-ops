---
description: Instructions for GitHub Copilot when working with this homelab repository
---

# GitHub Copilot Instructions

## Documentation Location

**All comprehensive repository context is centralized in `docs/ai-context/`:**

- [docs/ai-context/README.md](../docs/ai-context/README.md) - Navigation and overview
- [docs/ai-context/ARCHITECTURE.md](../docs/ai-context/ARCHITECTURE.md) - GitOps architecture and key decisions
- [docs/ai-context/DOMAIN.md](../docs/ai-context/DOMAIN.md) - Business rules and domain model
- [docs/ai-context/WORKFLOWS.md](../docs/ai-context/WORKFLOWS.md) - Operational workflows
- [docs/ai-context/TOOLS.md](../docs/ai-context/TOOLS.md) - Discovery and validation commands
- [docs/ai-context/CONVENTIONS.md](../docs/ai-context/CONVENTIONS.md) - Coding standards

Please reference these files for complete context about the repository structure, workflows, and conventions.

## Quick Reference

### Core Pattern
This homelab uses **GitOps + templated manifests**:
- Taskfile and Makejinja render templates from `bootstrap/`
- Flux applies manifests from `kubernetes/apps/<namespace>/<app>/`
- Talos manages immutable node configuration

### Essential Workflows

#### Deploying New Apps
1. Create directory: `kubernetes/apps/<namespace>/<app>/`
2. Add files: `kustomization.yaml`, `app/helmrelease.yaml`, optional `externalsecret.yaml`
3. Configure placeholders: `${SECRET_DOMAIN}`, `${DB_URI}`, etc.
4. Render: `task configure`
5. Validate: `task kubernetes:kubeconform`
6. Check diff: `flux diff kustomization <namespace>`
7. Create PR, merge, monitor: `flux get helmrelease <name>`

#### Updating Configuration
1. Edit templates in `bootstrap/` or app manifests
2. Render: `task configure`
3. Validate: `task kubernetes:kubeconform`
4. Review git diff
5. Create PR with `flux diff` evidence

### Key Rules

**Do:**
- ✅ Always run `task configure` after editing templates
- ✅ Use placeholders for secrets (`${SECRET_DOMAIN}`, `${DB_URI}`)
- ✅ Define storage explicitly in HelmRelease `persistence` sections
- ✅ Pin container images: `<tag>@<digest>` (use `crane digest`)
- ✅ Follow conventional commits: `chore(app): description`
- ✅ Run `task kubernetes:kubeconform` before PRs
- ✅ Include `flux diff` output in PR descriptions

**Don't:**
- ❌ Manually edit generated files under `kubernetes/apps/*/app/`
- ❌ Use `kubectl apply` directly (Flux will revert changes)
- ❌ Commit secrets (use placeholders + ExternalSecrets)
- ❌ Skip validation steps
- ❌ Push directly to `main` (use PRs)

### Discovery Commands

```bash
# Find all HelmReleases
rg --files -g"helmrelease.yaml" kubernetes/apps

# Find placeholder usage
rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps

# List all apps by namespace
ls kubernetes/apps/*/

# Show Taskfile tasks
task --list

# Check Flux status
flux get kustomizations
flux get helmreleases
```

### File Organization

```
kubernetes/
├── apps/<namespace>/<app>/        # Application manifests
│   ├── ks.yaml                    # Kustomization entry point
│   └── app/
│       ├── kustomization.yaml
│       ├── helmrelease.yaml
│       └── externalsecret.yaml
├── flux/                          # Flux configuration
│   └── vars/                      # Shared ConfigMaps/Secrets
├── bootstrap/                     # Makejinja templates (source)
└── templates/                     # Reusable templates

.taskfiles/                        # Task modules
talosconfig/                       # Talos node configs
scripts/                           # Helper scripts
```

### Cluster Information

**Hardware:** 3x Minisforum MS-01 nodes
- OS: TalosOS v1.10.4
- Kubernetes: v1.33.1
- CPU: Intel Core i9-12900H
- RAM: 96 GB per node
- Storage: NVMe SSDs (990 Pro + PM9A3), Rook Ceph cluster

**Network:**
- LAN: 1 Gbps Ethernet
- Ceph: Thunderbolt ring interconnect

### Placeholder Reference

Common placeholders used throughout manifests:

- `${SECRET_DOMAIN}` - External domain suffix for ingresses
- `${MEDIA_SERVER}` - Media server hostname/IP
- `${MEDIA_ROOT}` - Media root path
- `${NFS_STORAGE_HOST}` - NFS server for persistent storage
- `PLANE_*` - Plane app configuration
- `ROMM_*` - ROMM app configuration

These are resolved via ExternalSecrets referencing 1Password vaults.

### Code Style

- **Indentation:** 2 spaces (YAML), 4 spaces (bash/Python)
- **Line endings:** LF (Unix)
- **Directory names:** lowercase-hyphenated
- **Helm chart:** Default to `bjw-s/app-template`
- **Image tags:** Pin with digest: `image: foo:1.0.0@sha256:abc123...`

### Validation Pipeline

Before merging any PR:

1. `task configure` - Render templates
2. `task kubernetes:kubeconform` - Validate manifests
3. `flux diff kustomization <name>` - Check what Flux will apply
4. Review git diff for unintended changes
5. If secrets changed: `task sops:encrypt`

### Troubleshooting

**HelmRelease stuck in Reconciling:**
- Check: `flux logs --kind=HelmRelease --name=<name>`
- Verify: ExternalSecrets are populated
- Validate: Chart values against schema

**Pods in Pending state:**
- Check: PVC definitions exist
- Verify: Storage class available
- Review: `persistence` sections in HelmRelease

**Template rendering fails:**
- Check: Required variables in `bootstrap/config.yaml`
- Verify: Makejinja syntax
- Review: `task configure` output

**For detailed troubleshooting guides, see [docs/ai-context/](../docs/ai-context/).**
