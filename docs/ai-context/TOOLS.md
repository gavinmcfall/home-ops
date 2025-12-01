---
description: Tool strategy covering MCP servers, CLI commands, and exploration patterns
tags: ["RepoQL", "MermaidValidation", "TaskfileCLI", "FluxCLI", "KubectlCLI"]
audience: ["LLMs", "Humans"]
categories: ["Reference[100%]", "Tools[95%]"]
---

# Tool Strategy

**Principle**: Query before reading. Use structured tools to understand scope, then drill down.

---

## MCP Servers

Configured in `.mcp.json`:

### RepoQL

**Purpose**: Query the codebase as a database using SQL.

**Key Functions**:
```sql
-- File inventory
SELECT * FROM xray_documents()

-- Semantic search
SELECT uri, score FROM file_search('helm template', question := 'How do apps get deployed?', k := 10)

-- Object search (functions, classes)
SELECT uri, symbol, line_start FROM search('HelmRelease', k := 10) WHERE scope = 'object'

-- Preview with context
SELECT * FROM snippet('file:///path/to/file.yaml#line=42', 3)
```

**Use For**:
- Understanding repository structure before reading files
- Finding patterns across multiple files
- Semantic search when you don't know exact names

### Mermaid Validator

**Purpose**: Validate and auto-fix Mermaid diagrams.

**Use For**:
- Validating diagrams in documentation
- Auto-fixing syntax errors before commit

---

## CLI Tools

### Taskfile

**Location**: `Taskfile.yaml`, `.taskfiles/`

| Command | Purpose |
|---------|---------|
| `task configure` | Render templates + encrypt + validate |
| `task kubernetes:kubeconform` | Validate YAML schemas |
| `task kubernetes:resources` | List cluster resources |
| `task kubernetes:sync-secrets` | Force secret sync |
| `task kubernetes:network ns=X` | Debug networking |
| `task flux:bootstrap` | Initial Flux setup |
| `task flux:apply path=X` | Apply specific app |
| `task flux:reconcile` | Force reconciliation |
| `task flux:hr-restart` | Restart failed releases |
| `task sops:encrypt` | Encrypt SOPS files |

### Flux CLI

| Command | Purpose |
|---------|---------|
| `flux get kustomizations` | List all kustomizations |
| `flux get helmreleases -A` | List all HelmReleases |
| `flux get helmrelease <name> -n <ns>` | Check specific release |
| `flux reconcile kustomization <name>` | Force sync |
| `flux logs` | View controller logs |

### kubectl

| Command | Purpose |
|---------|---------|
| `kubectl get pods -A` | List all pods |
| `kubectl logs -n <ns> <pod>` | View pod logs |
| `kubectl describe hr <name> -n <ns>` | HelmRelease details |
| `kubectl get events -A --sort-by=.lastTimestamp` | Recent events |

---

## Discovery Patterns

### Understanding the repository

```bash
# Via RepoQL
xray detail=headline pattern=**/*.md limit=100

# Via CLI
task --list  # See available tasks
ls kubernetes/apps/  # See namespaces
ls kubernetes/apps/<namespace>/  # See apps in namespace
```

### Finding an app

```bash
# Via RepoQL
SELECT uri FROM file_search('prowlarr', question := NULL, k := 10)

# Via CLI
find kubernetes/apps -name "helmrelease.yaml" | xargs grep -l "prowlarr"
```

### Checking deployment status

```bash
# Flux status
flux get hr prowlarr -n downloads

# Pod status
kubectl get pods -n downloads -l app.kubernetes.io/name=prowlarr

# Events
kubectl get events -n downloads --field-selector involvedObject.name=prowlarr
```

### Debugging a failure

```bash
# 1. Check HelmRelease status
flux get hr <name> -n <namespace>

# 2. View Flux logs
kubectl logs -n flux-system deploy/helm-controller | grep <name>

# 3. Check pod events
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=<name>

# 4. View pod logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<name>
```

---

## Quick Reference

### When to use what

| Task | Tool |
|------|------|
| Understand repo structure | RepoQL `xray_documents()` |
| Find specific pattern | RepoQL `file_search()` or `grep` |
| Read a file | `Read` tool or `cat` |
| Validate YAML | `task kubernetes:kubeconform` |
| Check cluster state | `flux get` / `kubectl get` |
| Debug app | `kubectl logs` / `kubectl describe` |
| Force deployment | `task flux:reconcile` |
| Render templates | `task configure` |

---

## Environment Setup

Required for full functionality:

```bash
# Kubeconfig for cluster access
export KUBECONFIG=~/home-ops/kubeconfig

# SOPS age key for secret decryption
export SOPS_AGE_KEY_FILE=~/home-ops/age.key

# Or use direnv (recommended)
direnv allow .
```

---

## Evidence

| Claim | Source | Confidence |
|-------|--------|------------|
| RepoQL and Mermaid MCP servers configured | `.mcp.json` | Verified |
| Taskfile commands available | `Taskfile.yaml`, `.taskfiles/` | Verified |
| Flux CLI patterns | `.taskfiles/Flux/Taskfile.yaml` | Verified |
