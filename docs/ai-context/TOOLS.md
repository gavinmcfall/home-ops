# Tool Strategy for Homelab Exploration

**Purpose**: Use MCP servers and CLI tools to explore and manage the `~/home-ops` Kubernetes homelab. Treat the repo and cluster like a database: inventory structure first, then inspect specific resources.

---

## 🔌 MCP Servers Available

MCP (Model Context Protocol) servers extend AI assistant capabilities. Configuration in `.mcp.json`.

### Infrastructure & Cluster Management

| Server | Purpose | Auth/Config | Key Capabilities |
|--------|---------|-------------|------------------|
| **kubernetes** | K8s cluster operations | kubeconfig | Get/list resources, apply manifests, logs, exec, helm operations |
| **flux** | GitOps with Flux Operator | kubeconfig | Flux resources, reconciliation status, diff kustomizations |
| **talos** | Talos Linux cluster management | `~/.talos/config` | Node health, services, disks, etcd, logs, kubeconfig retrieval |
| **helm** | Helm package manager | - | Search repos, inspect charts, get values, list releases |

### Observability & Data

| Server | Purpose | Auth/Config | Key Capabilities |
|--------|---------|-------------|------------------|
| **grafana** | Grafana dashboards & alerts | `GRAFANA_URL`, token | Search dashboards, query datasources, manage alerts, incidents, oncall |
| **prometheus** | Prometheus metrics | `PROMETHEUS_URL` | Execute PromQL, list metrics, query ranges |
| **postgres** | PostgreSQL database | `POSTGRES_CONNECTION_STRING` | Query databases, inspect schemas, analyze queries |

### Development & Code

| Server | Purpose | Auth/Config | Key Capabilities |
|--------|---------|-------------|------------------|
| **github** | GitHub API integration | `GITHUB_PERSONAL_ACCESS_TOKEN` | Repos, issues, PRs, actions, code security, discussions, gists |
| **repoql** | Codebase semantic search | - | SQL queries over repo structure, semantic search, xray summaries |
| **filesystem** | Local file operations | - | Read/write files, directory listing |

### Web & External

| Server | Purpose | Auth/Config | Key Capabilities |
|--------|---------|-------------|------------------|
| **firecrawl** | Web scraping & extraction | `FIRECRAWL_API_KEY` | Scrape pages, crawl sites, extract structured data, search |
| **cloudflare-docs** | Cloudflare documentation | - (SSE) | Search Cloudflare docs |
| **cloudflare-dns-analytics** | DNS analytics | OAuth (browser) | DNS reports, zone settings, analytics |
| **cloudflare-graphql** | Cloudflare GraphQL API | OAuth (browser) | Generate and run GraphQL queries |

### Utilities

| Server | Purpose | Auth/Config | Key Capabilities |
|--------|---------|-------------|------------------|
| **shell** | Execute shell commands | `ALLOW_COMMANDS` env | Run allowed shell commands |
| **mermaid-validator** | Validate Mermaid diagrams | - | Validate and render diagrams to PNG/SVG |
| **eraser** | Eraser.io diagrams | `ERASER_API_KEY` | Create architecture diagrams |

---

## 🎯 MCP Server Details

### RepoQL (Codebase Intelligence)

**Binary**: `~/mcp/repoql`

Treat the repository as a queryable database using DuckDB-flavored SQL.

```sql
-- File inventory
SELECT * FROM xray_documents()

-- Semantic search for files
SELECT uri, score FROM file_search('auth', question := 'How does authentication work?', k := 10)

-- Search for functions/classes
SELECT uri, symbol, line_start FROM search('ProcessRequest', k := 10) WHERE scope = 'object'

-- Preview with context
SELECT * FROM snippet('file:///path/to/file.ts#line=42', 3)
```

**Key Functions**:
- `xray_documents()` - Inventory all files
- `file_search(keywords, question, k)` - Semantic file search
- `search(q, k)` - Search objects (functions, classes, headings)
- `snippet(uri, context_lines)` - Preview code with context

### Kubernetes MCP

**Install**: `npx kubernetes-mcp-server@latest`

**Toolsets**: `core`, `config`, `helm`

**Flags**:
- `--read-only` - Only expose read-only tools
- `--disable-destructive` - Disable destructive operations
- `--disable-multi-cluster` - Single cluster mode
- `--list-output yaml|table` - Output format

### GitHub MCP

**Binary**: `~/mcp/github-mcp-server`

**Toolsets** (enable via `--toolsets`):
- `context` - Repository context
- `repos` - Repository operations
- `issues` - Issue management
- `pull_requests` - PR operations
- `users`, `orgs` - User/org info
- `actions` - GitHub Actions
- `code_security`, `secret_protection`, `dependabot` - Security
- `notifications`, `discussions`, `gists` - Social
- `projects`, `labels`, `stargazers` - Project management

**Flags**:
- `--read-only` - Read-only mode
- `--toolsets=default,actions` - Enable specific toolsets
- `--dynamic-toolsets` - Enable dynamic tool loading

### Flux MCP

**Binary**: `flux-operator-mcp` (via brew)

Interacts with Flux GitOps resources in cluster.

**Usage**: Requires kubeconfig access. Use for:
- Checking reconciliation status
- Diffing kustomizations before apply
- Inspecting HelmReleases and Kustomizations

### Talos MCP

**Location**: `~/mcp/talos/` (Python venv)

**Requires**: `~/.talos/config` with valid cluster context

**Capabilities**:
- Cluster health and version info
- Node disk management
- Service status and logs
- etcd cluster inspection
- File system browsing on nodes
- Kubeconfig retrieval
- Resource queries (like `talosctl get`)

### Helm MCP

**Binary**: `~/mcp/mcp-helm`

**Mode**: `-mode=stdio` (default)

Query Helm repositories and charts without local Helm installation.

### Grafana MCP

**Binary**: `~/go/bin/mcp-grafana`

**Requires**: `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN`

**Tool Categories** (disable with `--disable-X`):
- `search` - Search dashboards
- `datasource` - Query datasources
- `dashboard`, `folder` - Dashboard management
- `alerting` - Alert rules and notifications
- `incident`, `oncall` - Incident management
- `prometheus`, `loki` - Direct metric/log queries
- `pyroscope` - Profiling
- `annotations` - Dashboard annotations

**Flags**:
- `--disable-write` - Read-only mode
- `--enabled-tools=search,prometheus` - Specific tools only

### Prometheus MCP

**Install**: `npx prometheus-mcp@latest stdio`

**Requires**: `PROMETHEUS_URL` (e.g., `http://localhost:9090`)

**Environment Variables**:
- `ENABLE_DISCOVERY_TOOLS` - Enable/disable discovery
- `ENABLE_INFO_TOOLS` - Enable/disable info tools
- `ENABLE_QUERY_TOOLS` - Enable/disable query tools

### PostgreSQL MCP

**Install**: `npx @henkey/postgres-mcp-server`

**Requires**: `--connection-string` or `POSTGRES_CONNECTION_STRING`

Format: `postgresql://user:pass@host:5432/database`

### Firecrawl MCP

**Install**: `npx firecrawl-mcp`

**Requires**: `FIRECRAWL_API_KEY` from https://firecrawl.dev

**Capabilities**:
- `scrape` - Extract content from pages (with JS rendering)
- `crawl` - Recursively crawl websites
- `map` - Discover all URLs on a site
- `search` - Search web content
- `extract` - LLM-powered structured data extraction

### Cloudflare MCP Servers

**DNS Analytics & GraphQL**: Use `mcp-remote` to connect to Cloudflare-hosted servers.

```json
{
  "cloudflare-dns-analytics": {
    "command": "npx",
    "args": ["-y", "mcp-remote", "https://dns-analytics.mcp.cloudflare.com/sse"]
  }
}
```

First use triggers OAuth authentication in browser.

---

## 🔧 CLI Tool Selection Matrix

For tasks not covered by MCP servers, use CLI tools directly:

| Question | Tool | Why |
|----------|------|-----|
| "Where is this service defined?" | `rg --files -g"helmrelease.yaml" kubernetes/apps` | Lists all HelmReleases |
| "Which manifests reference `${SECRET_DOMAIN}`?" | `rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps` | Finds placeholder usage |
| "What does Taskfile do for Kubernetes?" | Read `Taskfile.yaml` + `.taskfiles/Kubernetes.yaml` | Shows render/validation tasks |
| "How does Flux see this change?" | `flux diff kustomization <namespace>` | Simulates Flux apply |
| "Prove a claim with evidence" | Combine `rg`, file paths, line numbers | Evidence tables need explicit refs |

---

## 📁 Repository Inventory Commands

```bash
# List top-level context
ls bootstrap scripts talosconfig kubernetes/apps

# Show every HelmRelease + ExternalSecret
rg --files -g"helmrelease.yaml" kubernetes/apps
rg --files -g"externalsecret.yaml" kubernetes/apps

# Enumerate kustomizations (ensures Flux wiring)
rg --files -g"kustomization.yaml" kubernetes/apps

# Inspect Taskfile entry points
task --list | head -n 40
```

---

## 🧭 Placeholder & Pattern Discovery

```bash
# Domain placeholders
rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps

# Storage patterns
rg -n "existingClaim" -g"helmrelease.yaml" kubernetes/apps
rg -n "nfs:" -g"helmrelease.yaml" kubernetes/apps

# Flux dependencies
rg -n "dependsOn" -g"helmrelease.yaml" kubernetes/apps
```

---

## ⚙️ Task & Flux Commands

```bash
# Render and validate
task configure                 # renders manifests via makejinja
task kubernetes:kubeconform    # validates YAML before Flux

# Flux operations
flux diff kustomization <namespace> --path=kubernetes/apps/<namespace>
flux get helmrelease <name>
flux get kustomizations
flux reconcile kustomization <name>
```

Use `task` for reproducible operations and `flux` for source-of-truth validation. Avoid `kubectl apply`; Flux will revert drift.

---

## 🔐 Environment Variables Required

```bash
# GitHub
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."

# Observability
export PROMETHEUS_URL="http://localhost:9090"
export GRAFANA_URL="https://grafana.example.com"
export GRAFANA_SERVICE_ACCOUNT_TOKEN="..."

# Database
export POSTGRES_CONNECTION_STRING="postgresql://user:pass@localhost:5432/db"

# Web scraping
export FIRECRAWL_API_KEY="fc-..."

# Utilities
export ERASER_API_KEY="..."
export ALLOW_COMMANDS="echo,ls,cat"  # for shell MCP
```

---

## Evidence

| Claim | Source | Confidence | Details |
|-------|:------:|:----------:|---------|
| MCP servers configured in `.mcp.json` | `.mcp.json` | 🟢 | 17 servers configured |
| RepoQL provides codebase semantic search | `~/mcp/repoql`, `docs:///quickstart.md` | 🟢 | DuckDB SQL with semantic search |
| Flux MCP integrates with cluster | `flux-operator-mcp --help` | 🟢 | Uses kubeconfig, masks secrets |
| GitHub MCP has toolset selection | `~/mcp/github-mcp-server --help` | 🟢 | 15+ toolsets available |
| Grafana MCP has tool categories | `~/go/bin/mcp-grafana --help` | 🟢 | 15+ tool categories, disable flags |
