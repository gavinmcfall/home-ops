# AI Context Documentation

This directory contains the single source of truth for AI assistant context across multiple tools (Claude Code, Cursor, GitHub Copilot, and Gemini).

## Navigation

### Core Documentation

- [architecture.md](architecture.md) - GitOps architecture, key decisions, and constraints
- [domain.md](domain.md) - Business rules, entity relationships, and invariants
- [workflows.md](workflows.md) - Operational workflows and procedures
- [tools.md](tools.md) - Tool usage patterns and discovery commands
- [conventions.md](conventions.md) - Coding standards and project guidelines

## Purpose

This centralized documentation:
- Eliminates duplication across `.claude/`, `.cursor/`, `.codex/`, and `.github/` directories
- Provides consistent context to all AI coding assistants
- Makes updates easier - change once, propagate to all tools
- Maintains version control and team collaboration

## Tool-Specific Configurations

Each AI tool references these files using their native import mechanism:

- **Claude Code**: `.claude/CLAUDE.md` imports files with `@docs/ai-context/filename.md`
- **Cursor**: `.cursor/rules/index.mdc` references files with `@docs/ai-context/filename.md`
- **GitHub Copilot**: `.github/copilot-instructions.md` links to files manually
- **Gemini**: Reads project files through IDE integration

## Adding New Context

When adding new documentation:
1. Create or update markdown files in this directory
2. Tool-specific configs will automatically see the changes through their import mechanisms
3. Commit changes to version control
4. All team members and AI assistants benefit immediately

## Structure Philosophy

This follows a living documentation pattern:
- **Architecture** - Why the system is designed this way
- **Domain** - What the business rules and invariants are
- **Workflows** - How to perform common operations
- **Tools** - Which commands to use for discovery and validation
- **Conventions** - Coding and project standards to follow
