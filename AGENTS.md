# AI Assistant Configuration

This repository uses multiple AI coding assistants with shared context from a centralized documentation hub.

## 📚 Documentation Location

All AI assistant context is centralized in **[`docs/ai-context/`](docs/ai-context/)**:

- [README.md](docs/ai-context/README.md) - Overview and navigation
- [architecture.md](docs/ai-context/architecture.md) - GitOps architecture, key decisions, and constraints
- [domain.md](docs/ai-context/domain.md) - Business rules, entity relationships, and invariants
- [workflows.md](docs/ai-context/workflows.md) - Operational workflows and procedures
- [tools.md](docs/ai-context/tools.md) - Tool usage patterns and discovery commands
- [conventions.md](docs/ai-context/conventions.md) - Coding standards and project guidelines
- [flux-mcp.md](docs/ai-context/flux-mcp.md) - Flux MCP server guidelines and troubleshooting

This centralized approach provides:
- ✅ Single source of truth for all AI tools
- ✅ No duplication across tool-specific directories
- ✅ Easy updates - change once, all tools benefit
- ✅ Version controlled and team-friendly
- ✅ Future-proof for new AI assistants

## 🔌 MCP Server Configuration

Model Context Protocol (MCP) servers are configured in the root **[`.mcp.json`](.mcp.json)** file, which is shared across:
- ✅ VS Code MCP extensions
- ✅ Claude Code
- ✅ Any other tool supporting the `.mcp.json` standard

**Available MCP Servers:**
- **repoql** - Repository querying and code analysis
- **mermaid-validator** - Validate and render Mermaid diagrams
- **plantuml** - Generate PlantUML diagrams
- **eraser** - Create diagrams with Eraser.io (requires `ERASER_API_KEY`)

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
│       ├── architecture.md
│       ├── domain.md
│       ├── workflows.md
│       ├── tools.md
│       ├── conventions.md
│       └── flux-mcp.md
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
- **Images:** Pin with digest: `<tag>@<digest>`
- **Validation:** Always run `task configure` → `task kubernetes:kubeconform` → `flux diff`
- **PRs:** Include `flux diff` output, never push directly to `main`

For complete details, see the documentation in [`docs/ai-context/`](docs/ai-context/).
