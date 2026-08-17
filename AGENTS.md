# AI Assistant Configuration

This repository uses multiple AI coding assistants with shared context from a centralized documentation hub.

## 📚 Documentation Location

All AI assistant context is centralized in **[`docs/ai-context/`](docs/ai-context/)**:

- [README.md](docs/ai-context/README.md) - Overview and navigation
- [ARCHITECTURE.md](docs/ai-context/ARCHITECTURE.md) - GitOps architecture, key decisions, and constraints
- [DOMAIN.md](docs/ai-context/DOMAIN.md) - Business rules, entity relationships, and invariants
- [WORKFLOWS.md](docs/ai-context/WORKFLOWS.md) - Operational workflows and procedures
- [TOOLS.md](docs/ai-context/TOOLS.md) - Tool usage patterns and discovery commands
- [CONVENTIONS.md](docs/ai-context/CONVENTIONS.md) - Coding standards and project guidelines

This centralized approach provides:
- ✅ Single source of truth for all AI tools
- ✅ No duplication across tool-specific directories
- ✅ Easy updates - change once, all tools benefit
- ✅ Version controlled and team-friendly
- ✅ Future-proof for new AI assistants

## 📖 Read First

1. **[docs/ai-context/Ethos.md](docs/ai-context/Ethos.md)** - Documentation philosophy
2. **[docs/ai-context/ARCHITECTURE.md](docs/ai-context/ARCHITECTURE.md)** - System architecture
3. **[docs/ai-context/CONVENTIONS.md](docs/ai-context/CONVENTIONS.md)** - Coding standards

## ⚠️ Critical Invariants

### Capsule: GitOpsReconciliation

**Invariant**: Cluster state converges to match Git; Flux reverts manual changes.

### Capsule: MakejinjaTemplates

**Invariant**: Edit templates in `bootstrap/templates/`; don't edit generated files.

**CRITICAL**: NEVER run `task configure` - it is for initial bootstrap only. Edit both the template AND the generated output file manually when making changes.

### Capsule: SopsEncryption

**Invariant**: Secrets are SOPS-encrypted in Git; Flux decrypts at runtime.

### Capsule: AppTemplateChart

**Invariant**: Apps use `bjw-s/app-template` chart; vendor charts are exceptions.

## 🔌 MCP Server Configuration

Model Context Protocol (MCP) servers are configured in the root **[`.mcp.json`](.mcp.json)** file, which is shared across:
- ✅ VS Code MCP extensions
- ✅ Claude Code
- ✅ Any other tool supporting the `.mcp.json` standard

**Available MCP Servers:**
- **repoql** - Repository querying and code analysis
- **mermaid** - Validate and render Mermaid diagrams (via `@probelabs/maid-mcp`)

This provides a single source of truth for MCP server configuration across all compatible tools.

## 🤖 Tool-Specific Configurations

Each AI tool has its own configuration that references the centralized documentation:

### Claude Code
**Configuration:** [`.claude/CLAUDE.md`](.claude/CLAUDE.md)
- Imports files from `docs/ai-context/` using `@path/to/file.md` syntax
- Supports recursive imports up to depth 5
- MCP servers configured in root [`.mcp.json`](.mcp.json) (shared with VS Code)

### Cursor
**Configuration:** [`.cursor/rules/index.mdc`](.cursor/rules/index.mdc)
- References files from `docs/ai-context/` using `@path/to/file.md` syntax
- Supports pattern matching for path-specific rules
- MDC format with YAML frontmatter

### GitHub Copilot
**Configuration:** [`.github/copilot-instructions.md`](.github/copilot-instructions.md)
- References files from `docs/ai-context/` via markdown links
- No native import system, but reads referenced files
- YAML frontmatter for metadata

### Gemini Code Assist
**Configuration:** IDE-specific settings
- No repository-level configuration file
- Reads project files through IDE integration
- Can access `docs/ai-context/` content when needed

## 🔧 Adding New AI Tools

To add a new AI assistant to this repository:

1. Create the tool-specific configuration directory if needed (e.g., `.windsurf/`, `.aider/`)
2. Create a configuration file that references `docs/ai-context/` files using the tool's native mechanism
3. Add tool-specific optimizations or overrides as needed
4. Update this README to document the new tool's configuration
5. Add the tool's local settings to `.gitignore` if necessary

## 📝 Adding New Context

When adding new documentation for AI assistants:

1. Add or update markdown files in [`docs/ai-context/`](docs/ai-context/)
2. Tool-specific configs will automatically see the changes through their import mechanisms
3. Commit changes to version control
4. All team members and AI assistants benefit immediately

**Do not** create duplicate documentation in tool-specific directories (`.claude/`, `.cursor/`, `.codex/`, etc.). Always update [`docs/ai-context/`](docs/ai-context/) as the single source of truth.

## 🗂️ Legacy Directories

### `.codex/`
The `.codex/Homelab/` directory has been deprecated. All content has been moved to `docs/ai-context/`.

See [`.codex/README.md`](.codex/README.md) for migration details.

The `.codex/Guides/` directory remains active for project-specific tutorials that don't belong in the centralized documentation.

## 🎯 Quick Reference

### Repository Structure
This is a Kubernetes homelab managed using:
- **GitOps:** Flux automatically applies manifests from Git
- **Templates:** Taskfile + Makejinja render configurations
- **Immutable OS:** Talos for node management
- **Secrets:** Placeholders (`${SECRET_DOMAIN}`) resolved via ExternalSecrets

### Directory Structure
```
/home/gavin/home-ops/
├── docs/
│   └── ai-context/              # 📚 Single source of truth for AI context
│       ├── README.md
│       ├── ARCHITECTURE.md
│       ├── DOMAIN.md
│       ├── WORKFLOWS.md
│       ├── TOOLS.md
│       └── CONVENTIONS.md
│
├── .claude/
│   └── CLAUDE.md                # Imports from docs/ai-context/
│
├── .mcp.json                    # 🔌 MCP server config (shared: VS Code + Claude)
│
├── .cursor/
│   └── rules/
│       └── index.mdc            # References docs/ai-context/
│
├── .github/
│   └── copilot-instructions.md  # References docs/ai-context/
│
├── .codex/
│   ├── README.md                # Deprecation notice
│   └── Guides/                  # Project-specific guides (active)
│
├── kubernetes/
│   ├── apps/                    # Application manifests
│   ├── flux/                    # Flux configuration
│   └── templates/               # Reusable templates
│
├── bootstrap/                   # Makejinja templates (source)
├── .taskfiles/                  # Task modules
├── talosconfig/                 # Talos node configs
└── scripts/                     # Helper scripts
```

### Key Workflows

**Deploy New App:**
```bash
# 1. Create app directory structure
mkdir -p kubernetes/apps/<namespace>/<app>/app

# 2. Add manifests (kustomization.yaml, helmrelease.yaml, externalsecret.yaml)

# 3. Render and validate
task configure
task kubernetes:kubeconform
flux diff kustomization <namespace>

# 4. Create PR, merge, monitor
flux get helmrelease <name>
```

**Update Configuration:**
```bash
# 1. Edit templates or manifests
# 2. Render and validate
task configure
task kubernetes:kubeconform

# 3. Review and commit
git diff
git add .
git commit -m "chore(app): description"
```

### Essential Commands

```bash
# Render templates
task configure

# Validate manifests
task kubernetes:kubeconform

# Check Flux status
flux get kustomizations
flux get helmreleases

# Find resources
rg --files -g"helmrelease.yaml" kubernetes/apps
rg -n "\${SECRET_DOMAIN}" -g"*.yaml" kubernetes/apps
```

### Key Conventions

- **Commits:** Follow conventional commits (`chore(app): description`)
- **Secrets:** Use placeholders (`${SECRET_DOMAIN}`), never commit secrets
- **Storage:** Define explicitly in HelmRelease `persistence` sections
- **Images:** Pin with digest: `<tag>@sha256:<digest>` (see below)
- **Validation:** Always run `task configure` → `task kubernetes:kubeconform` → `flux diff`
- **PRs:** Include `flux diff` output, never push directly to `main`
- **Makejinja delimiters:** `#{var}#` not `{{var}}` (avoids Helm conflicts)
- **Gateway API routing:** Use `route` not `ingress` for main traffic
- **SOPS files:** End in `.sops.yaml`, encrypted before commit

### Container Image Tags

**Never use `latest` tag.** Always pin to a specific version with SHA256 digest.

**Finding the latest tag and digest:**
```bash
# List available tags for an image
crane ls <registry>/<image>

# Get the digest for a specific tag
crane digest <registry>/<image>:<tag>

# Example workflow:
crane ls mayanayza/netvisor-server
# Output: latest, v0.10.4, v0.10.3, ...

crane digest mayanayza/netvisor-server:v0.10.4
# Output: sha256:d65cb30d232119c811fddd21837a9ce305324663b279da4ff215e0199d82f93d
```

**Important:** Verify against the source repository releases, not just registry tags. Container registries may contain orphaned, pre-release, or test tags that were never officially released.

```bash
# Check official releases (works for most projects)
gh release list --repo <owner>/<repo> --limit 10

# For projects not on GitHub, check their source repo's releases page
```

**Resulting image reference:**
```yaml
image:
  repository: mayanayza/netvisor-server
  tag: v0.10.4@sha256:d65cb30d232119c811fddd21837a9ce305324663b279da4ff215e0199d82f93d
```

This ensures:
- Reproducible deployments (digest guarantees exact image)
- Clear version tracking (tag shows semantic version)
- No surprise updates from mutable tags like `latest`

### Commit Messages

Conventional commits: `type(scope): description`.

**Attribute AI assistance.** Anything built with an agent closes with:

```
Assisted-by: Claude Code (claude-opus-5)
Agentically-Engineered: https://nerdz.cloud/agentic-engineering
```

Name the model actually used — the trailer is a record of how the commit was
built, so a stale or guessed model id makes that record wrong. Add a human
`Co-Authored-By:` trailer as well when someone genuinely co-authored the change.

A `commit-msg` hook in [`.githooks/`](.githooks/) checks this. It does **not**
require attribution — a hook cannot tell whether an agent was involved, so
demanding the trailers would block hand-written work. It validates attribution
*when present*: both trailers together, a parenthesised model id, and the exact
URL. The hook is version-controlled and wired via `core.hooksPath`, so a fresh
clone needs `git config core.hooksPath .githooks` once.

Earlier guidance told agents to strip every trace of AI involvement. That is
**retired** — do not remove these trailers, and do not treat naming the
assistant as something to avoid. The point is transparency about process, not
decoration: see
[nerdz.cloud/agentic-engineering](https://nerdz.cloud/agentic-engineering).

For complete details, see the documentation in [`docs/ai-context/`](docs/ai-context/).
