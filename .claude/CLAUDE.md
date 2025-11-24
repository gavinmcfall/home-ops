# Homelab Repository Context

This repository manages a Kubernetes homelab using GitOps principles with Flux, Talos, and Taskfile-driven workflows.

## Core Documentation

The following files contain comprehensive context about this repository. They are the single source of truth shared across all AI coding assistants:

@docs/ai-context/README.md
@docs/ai-context/architecture.md
@docs/ai-context/domain.md
@docs/ai-context/workflows.md
@docs/ai-context/tools.md
@docs/ai-context/conventions.md

## MCP Configuration

MCP servers are configured in the root `.mcp.json` file (shared across VS Code and Claude Code).

When using the Flux MCP server for troubleshooting:

@docs/ai-context/flux-mcp.md

## Quick Reference

- **Core Pattern**: GitOps + templated manifests via Taskfile and Makejinja
- **Directory Structure**: `kubernetes/apps/<namespace>/<app>/` contains HelmRelease, ExternalSecret, and kustomization
- **Secret Management**: Placeholders (`${SECRET_DOMAIN}`, `${DB_URI}`) resolved via ExternalSecrets
- **Validation**: Always run `task configure` → `task kubernetes:kubeconform` → `flux diff` before merging

## Key Commands

```bash
# Render templates and validate
task configure
task kubernetes:kubeconform

# Check Flux status
flux get kustomizations
flux get helmreleases
flux diff kustomization <namespace>

# Find resources
rg --files -g"helmrelease.yaml" kubernetes/apps
rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps
```

## Important Notes

- Never manually edit generated files under `kubernetes/apps/*/app/`
- Always use `task configure` to render templates
- Placeholders must be documented before use
- Storage (PVCs/NFS) must be explicitly defined
- Follow conventional commits: `chore(app): description`
