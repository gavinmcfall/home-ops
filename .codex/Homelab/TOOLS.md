# Tool Guidance for Claude/Codex

## Search Strategy
- **Directories first**: list `bootstrap/`, `talosconfig/`, `kubernetes/apps`, `scripts/`, and `Taskfile.yaml` before deep dives.
- **Placeholders**: `rg -n "\$\{SECRET_DOMAIN\}" -g"*.yaml" kubernetes/apps` shows every ingress reference that needs substitution.
- **HelmRelease focus**: read `kubernetes/apps/games/romm/app/helmrelease.yaml` for examples of values, mounts, and placeholder usage.

## Command Patterns
```bash
rg -n "helmrelease" kubernetes/apps/games/romm/app/helmrelease.yaml
rg -n "SECRET_DOMAIN" -g"*.yaml" kubernetes/apps
task configure        # renders templates
task kubernetes:kubeconform
flux diff kustomization games --path=kubernetes/apps/games/romm/app
```

## Tool Selection
- Use `rg` for concept or placeholder discovery, `sed -n` for targeted sections, and `cat` for templates.
- No external repos are referenced; keep all operations within `/home/gavin/home-ops`.

## Evidence
| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| Placeholder strategy uses `${SECRET_DOMAIN}` | `kubernetes/apps/games/romm/app/helmrelease.yaml:90-100` | 🟢 | Ingress host uses `${SECRET_DOMAIN}`. |
| Taskfile commands exist locally | `Taskfile.yaml` | 🟢 | Tasks like `task configure`, `task kubernetes:kubeconform` defined. |
