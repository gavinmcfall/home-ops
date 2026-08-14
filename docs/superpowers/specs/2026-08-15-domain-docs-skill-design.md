---
description: Design for the domain-docs skill - repeatable generation and auditing of per-domain documentation from cluster manifests
tags: ["DomainDocs", "SkillDesign", "ZonedRegeneration", "MermaidInspection", "DriftAudit"]
audience: ["LLMs", "Humans"]
categories: ["Design[100%]", "Documentation[90%]"]
---

# Domain Docs Skill — Design

**Status**: Approved design, pending implementation plan
**Date**: 2026-08-15

## Problem

`docs/` has strong system-level docs (`ai-context/`) and ad-hoc topic guides (`Guides/`), but no consistent per-domain layer. Domain knowledge (what makes up the downloads stack, why the reading stack is shaped the way it is) lives in one-off files of varying quality. When the cluster changes, docs silently rot. Existing docs are raw material, not the golden example.

**Goal**: a skill that any Claude session can run to produce or update domain docs that are structurally identical, manifest-accurate, and cheap to keep current.

## Prior Art (researched 2026-08-15)

No community skill or tool generates re-runnable docs from a Flux/K8s repo. Closest: `helm-docs` (deterministic chart-scoped README generation) and one homelab `/doc-sync` command (drift verification of hand-written docs). Verdict: build custom, steal two patterns — **deterministic diffable output** and **audit as a first-class mode**.

## Decisions Locked

1. **Two tiers + whys per domain** — dense LLM context, human overview, and append-only decision records.
2. **Zoned regeneration** — generated zones rebuilt every run; curated zones preserved, only verified.
3. **Registry file** — `domains.yaml` is the deterministic source of domain membership. Unmapped apps are drift, not guesswork.
4. **Approach A** — Claude extracts facts from manifests live, constrained by strict templates. No extraction script unless runs prove inconsistent (designed escape hatch: yq → facts JSON, helm-docs pattern).
5. **Visual mermaid verification** — every generated/changed diagram is rendered to an image and visually inspected before the doc ships. Code inspection alone is insufficient.

## Layout

```
.claude/skills/domain-docs/
  SKILL.md              # process definition (modes, extraction, zones, mermaid loop)
  domains.yaml          # registry: domain -> namespaces/apps, cross-domain overrides
  templates/
    context.md          # tier 1 template
    overview.md         # tier 2 template
    decisions.md        # tier 3 template (seed skeleton only)

docs/domains/<domain>/
  context.md            # LLM-dense: facts + capsules
  overview.md           # human: narrative + diagrams + operations
  decisions.md          # append-only ADR-lite whys
```

## Registry: `domains.yaml`

```yaml
domains:
  downloads:
    title: Downloads Infrastructure
    namespaces: [downloads]
    exclude: []            # apps in the namespace that belong elsewhere
    include: []            # apps from other namespaces that belong here
  media:
    title: Movies & TV
    namespaces: [entertainment]
    include: [downloads/radarr, downloads/sonarr]   # example shape only
  # reading, auth, observability follow the same shape
```

Rules:
- Membership resolves in order: `namespaces` minus `exclude` plus `include`. `include`/`exclude` entries are `namespace/app` paths under `kubernetes/apps/`.
- An app may appear in multiple domains (e.g. qBittorrent in downloads and reading) — allowed, but each mention links to the owning domain's context for depth.
- `audit` reports any app under a registry-claimed namespace that resolves to no domain, and any registry entry whose manifest path no longer exists.

## Zone Convention

```markdown
<!-- generated:start section=apps -->
...rebuilt every update run, never hand-edit...
<!-- generated:end -->

<!-- curated -->
...human/session-authored, preserved verbatim on update...
```

- Generated zones are owned by the skill: full overwrite each `update`.
- Curated zones are never modified by `update`; `audit` checks them for references to apps/routes/paths that no longer exist and flags (never deletes).
- Content outside any marker is treated as curated.

## The Three Docs

### `context.md` (tier 1 — LLM)
Frontmatter per ai-context standard. Generated zones:
- **Apps table**: app, namespace, chart/image source, route + gateway (internal/external), storage (PVC class/size, VolSync yes/no), secrets source, dependencies (`dependsOn`).
- **Data flow**: one mermaid diagram of how data/requests move through the domain.
- **Integration points**: cross-domain touchpoints (e.g. downloads → media import paths).

Curated zones: capsules (Invariant/Example/Depth per `writing-capsules.md`), domain-specific gotchas.

### `overview.md` (tier 2 — human)
Generated skeleton: what the domain is, component list with one-liners, the same data-flow diagram (shared source, see Determinism), links to dashboards/UIs. Curated prose: how it fits family workflows, operational notes.

### `decisions.md` (tier 3 — whys)
Append-only. Entry format:

```markdown
## 2026-08-15 — Chose X over Y
**Why**: ...
**Alternatives rejected**: Y (reason), Z (reason)
**Links**: manifests, PRs, external docs
```

Never regenerated. `audit` flags entries referencing removed apps/routes as `[stale-reference]` in the drift report only.

## Determinism Rules

To keep re-runs diffable without an extraction script:
1. Tables have fixed columns defined in the template; rows sorted alphabetically by app name.
2. Facts come only from files under `kubernetes/apps/` (+ `flux/` where needed) — never from memory or live cluster state. `kubectl` is allowed only to *verify* a claim, never as a doc source.
3. Every generated fact must be traceable to a file path; the templates use repo-relative links.
4. No prose in generated zones beyond template-fixed sentence patterns.
5. Mermaid sources live in the doc; identical facts must produce an identical diagram (stable node IDs = app names, stable ordering).

## Mermaid Render-and-Inspect Loop (required, not optional)

For every diagram the skill creates or changes:
1. Extract the mermaid block to the scratchpad (never into the repo).
2. Render: `npx -y @mermaid-js/mermaid-cli -i <file>.mmd -o <file>.png -b white` (node 24 + npx confirmed on this box; first run downloads the CLI + headless chromium).
3. **Read the PNG and visually inspect** — this is an image-eyes check, not a syntax check:
   - No edge crossings that reordering/direction change would remove
   - No labels overlapping nodes or other labels
   - No orphan/floating nodes
   - Orientation fits content (LR for pipelines, TB for hierarchies)
   - ≤12 nodes; split the diagram if over
4. Fail any criterion → adjust the mermaid source (direction, subgraphs, node order) → re-render. Max 3 iterations, then simplify the diagram rather than ship a bad one.
5. Follow `docs/ai-context/mermaid-diagram-guide.md` for style; this loop adds visual verification on top.
6. **Cleanup (mandatory final step of every run)**: delete all render artifacts (`.mmd` extracts, PNGs) from the scratchpad. Render artifacts are verification throwaways — only the mermaid source in the doc is kept (GitHub renders it natively). A run is not complete until `git status` shows no stray artifacts in the repo.

## Modes

- **`create <domain>`** — scaffold all three files from templates, populate generated zones, seed curated zones from existing raw-material docs (flagged for review), run mermaid loop.
- **`update <domain>|all`** — rebuild generated zones, preserve curated, re-run mermaid loop only if a diagram's inputs changed, emit a drift summary.
- **`audit`** — read-only. Reports: unmapped apps, registry entries with missing manifests, curated-zone stale references, decisions entries with dead links, docs whose generated zones differ from a fresh extraction.

## Decision Capture

`SKILL.md` defines a lightweight convention any session can follow: when a notable choice is made during cluster work (app selection, architecture, routing pattern), append a `decisions.md` entry in the same PR. The skill itself does not mine history retroactively; seeding pulls known whys from existing docs and memory once, at `create` time.

## Seeding Plan (initial run order)

| Domain | Raw material |
|---|---|
| downloads | manifests; Guides scraps; usenet/indexer reference memory |
| media | manifests; `plex-arr-monitoring-stack.md` |
| reading | manifests; `ai-context/nerdz-reading-stack.md` (superseded by the new docs, then trimmed to a pointer) |
| auth | manifests; `NETWORKING.md` OIDC sections; Pocket ID guides |
| observability | manifests; `observability-audit-2026-05.md`; otel roadmap docs |

Existing files are inputs, not formats — content is re-shaped into the templates.

## Non-Goals

- Not a general-purpose docs generator for other repos (repo-scoped skill, versioned with home-ops).
- No CI automation in v1 (a Renovate-style scheduled `update` is a possible follow-up).
- No rewriting of `ai-context/` system docs; domain docs link to them.

## Open Questions (resolve during implementation)

1. Exact `include`/`exclude` membership shapes once real manifests are mapped — the example above is illustrative.

## Resolved Questions

- **Rendered PNGs**: throwaway verification artifacts, never committed. Mandatory cleanup step at the end of every run (2026-08-15, Gavin).
