# Domain Docs Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the repo-scoped `domain-docs` skill and use it to seed five domain doc sets under `docs/domains/`.

**Architecture:** A skill at `.claude/skills/domain-docs/` reads `domains.yaml`, extracts facts from `kubernetes/apps/` manifests, and renders three zoned markdown files per domain. Generated zones are rebuilt every run; curated zones are preserved; `decisions.md` is append-only. Every diagram passes a visual render-and-inspect loop before shipping.

**Tech Stack:** Markdown + YAML; `npx -y @mermaid-js/mermaid-cli` for diagram rendering; bash/yq for verification checks. No compiled code, no test framework — verification is executable checks (grep/diff/render) defined per task.

**Spec:** `docs/superpowers/specs/2026-08-15-domain-docs-skill-design.md`

## Global Constraints

- Generated facts come ONLY from files under `kubernetes/apps/` (+ `flux/` if needed); `kubectl` may verify, never source.
- Tables: fixed columns per template; rows sorted alphabetically by app name.
- Mermaid: stable node IDs = app names; ≤12 nodes; every new/changed diagram is rendered to PNG in the scratchpad, visually inspected (edge crossings, label overlap, orphans, orientation), max 3 fix iterations, then simplify.
- Cleanup: all render artifacts (`.mmd`, `.png`) deleted at end of run; `git status` must show no strays.
- Doc frontmatter per `docs/ai-context/README.md` standard (description, tags, audience, categories).
- Commit messages: conventional commits, must NOT contain the words "claude" or "anthropic" (commit-msg hook blocks them); no Co-Authored-By trailers.
- Zone markers exactly: `<!-- generated:start section=NAME -->` / `<!-- generated:end -->` / `<!-- curated -->` … `<!-- /curated -->`.

---

### Task 1: Skill scaffold — SKILL.md

**Files:**
- Create: `.claude/skills/domain-docs/SKILL.md`

**Interfaces:**
- Produces: the process contract every later task follows (modes, extraction recipe, zone semantics, mermaid loop, cleanup). Tasks 4–7 execute this skill's instructions literally.

- [ ] **Step 1: Write SKILL.md**

````markdown
---
name: domain-docs
description: Generate, update, and audit per-domain docs (docs/domains/) from kubernetes manifests. Use when creating a domain doc set, refreshing docs after cluster changes, or checking for doc drift. Modes: create <domain>, update <domain|all>, audit.
---

# Domain Docs

Produce structurally identical, manifest-accurate domain documentation.
Spec: `docs/superpowers/specs/2026-08-15-domain-docs-skill-design.md`.

## Inputs

- `domains.yaml` (this directory) — the ONLY source of domain membership.
- `kubernetes/apps/<ns>/<app>/` — the ONLY source of generated facts.
  Read per app: `ks.yaml` (Flux Kustomization: dependsOn, components),
  `app/helmrelease.yaml` (chart, image, env, route, persistence),
  `app/*.yaml` (externalsecret, pvc, httproute if split out).
- `templates/` (this directory) — structure of every output file.

## Membership resolution

`namespaces` minus `exclude` plus `include` (entries are `<ns>/<app>` paths).
An app may appear in multiple domains; each mention links to the owning
domain's context.md for depth. Any app under a registry-claimed namespace
that resolves to no domain → drift report. Never guess membership.

## Zone semantics

- `<!-- generated:start section=NAME -->` … `<!-- generated:end -->`:
  owned by this skill. Fully overwritten every update. Never hand-edit.
- `<!-- curated -->` blocks and anything outside markers: NEVER modified
  by update. Audit may flag stale references; only a human deletes.
- `decisions.md`: append-only. Never regenerate, reorder, or rewrite
  existing entries.

## Determinism rules

1. Fixed table columns (defined in templates); rows sorted alphabetically by app.
2. Facts traceable to a file; use repo-relative links.
3. No free prose in generated zones — template sentence patterns only.
4. Identical facts must render identical output (stable diagram node
   IDs = app names, alphabetical edge ordering).

## Modes

### create <domain>
1. Verify `docs/domains/<domain>/` does not exist (else use update).
2. Resolve membership; read each member's manifests; build the facts set.
3. Instantiate all three templates; fill generated zones.
4. Seed curated zones from raw material named in the registry `seeds:` key
   (if any) — mark seeded prose with `<!-- seeded: review -->` for human review.
5. Run the mermaid loop (below) for every diagram.
6. Cleanup. Report: files written, seeds flagged, drift found.

### update <domain>|all
1. Re-extract facts; rebuild every generated zone in place.
2. Do not touch curated zones or decisions.md.
3. Re-run mermaid loop ONLY for diagrams whose generated source changed.
4. Cleanup. Report a drift summary (what changed since last run).

### audit  (read-only — no file writes, no cleanup needed)
Report, per domain: unmapped apps in claimed namespaces; registry entries
whose `kubernetes/apps/` path is gone; curated-zone references to
apps/routes/paths that no longer exist; decisions.md entries with dead
repo links (tag `[stale-reference]`); generated zones that differ from a
fresh extraction (stale docs).

## Mermaid render-and-inspect loop (MANDATORY for every new/changed diagram)

1. Write the mermaid block to `<scratchpad>/<domain>-<diagram>.mmd`
   (never inside the repo).
2. `npx -y @mermaid-js/mermaid-cli -i <file>.mmd -o <file>.png -b white`
3. Read the PNG. VISUALLY verify (image eyes, not code eyes):
   - no removable edge crossings; no label overlap; no orphan nodes;
   - orientation fits (LR pipelines, TB hierarchies); ≤12 nodes.
4. Fail → adjust source (direction, subgraphs, ordering) → re-render.
   Max 3 iterations, then simplify the diagram.
5. Style per `docs/ai-context/mermaid-diagram-guide.md`.

## Cleanup (MANDATORY last step of create/update)

Delete every `.mmd`/`.png` render artifact from the scratchpad. Run
`git status` — no stray files in the repo. A run is not complete until
both hold.

## Decision capture (any session, any time)

When a notable choice lands during cluster work (app selection,
architecture, routing pattern), append an entry to the owning domain's
`decisions.md` in the same PR — newest first, format per the template.
This skill never mines history retroactively; the whys accumulate as a
side effect of work.
````

- [ ] **Step 2: Verify skill frontmatter parses and markers are consistent**

Run: `yq --front-matter=extract '.name, .description' .claude/skills/domain-docs/SKILL.md`
Expected: `domain-docs` and the description line, no YAML error.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/domain-docs/SKILL.md
git commit -m "feat(skills): domain-docs skill process definition"
```

### Task 2: Registry — domains.yaml

**Files:**
- Create: `.claude/skills/domain-docs/domains.yaml`

**Interfaces:**
- Consumes: membership resolution rules from Task 1.
- Produces: the five domain definitions used by Tasks 4–7. Keys: `domains.<name>.{title, namespaces, exclude, include, seeds}`.

- [ ] **Step 1: Write domains.yaml** (membership drafted from the live tree listing of `kubernetes/apps/`; every path below existed on 2026-08-15)

```yaml
# Domain membership registry — the only source of truth for docs/domains/.
# Resolution: namespaces minus exclude plus include. Paths are <ns>/<app>.
# Apps in a claimed namespace that resolve to no domain appear in `task audit` drift.
domains:
  downloads:
    title: Downloads Infrastructure
    namespaces: [downloads]
    exclude:
      # media-type-specific apps documented in their consuming domain:
      - downloads/arr-codec-tagger   # media
      - downloads/bazarr             # media
      - downloads/bazarr-foreign     # media
      - downloads/bazarr-uhd         # media
      - downloads/bindery            # reading
      - downloads/kapowarr           # reading
      - downloads/lidarr             # music (no domain yet — intentional drift)
      - downloads/lncrawl            # reading
      - downloads/radarr             # media
      - downloads/radarr-uhd         # media
      - downloads/recyclarr          # media
      - downloads/rom-ingest         # games (no domain yet — intentional drift)
      - downloads/shelfmark          # reading
      - downloads/sonarr             # media
      - downloads/sonarr-foreign     # media
      - downloads/sonarr-uhd         # media
      - downloads/soularr            # music (no domain yet — intentional drift)
      - downloads/suwayomi           # reading
      - downloads/tranga             # reading
    include: []
    seeds: []
  media:
    title: Movies & TV
    namespaces: []
    include:
      - downloads/arr-codec-tagger
      - downloads/bazarr
      - downloads/bazarr-foreign
      - downloads/bazarr-uhd
      - downloads/radarr
      - downloads/radarr-uhd
      - downloads/recyclarr
      - downloads/sonarr
      - downloads/sonarr-foreign
      - downloads/sonarr-uhd
      - entertainment/plex
      - entertainment/seerr
      - entertainment/tautulli
      - entertainment/wizarr
    exclude: []
    seeds: [docs/Guides/plex-arr-monitoring-stack.md]
  reading:
    title: Books, Audiobooks, Comics & Manga
    namespaces: []
    include:
      - downloads/bindery
      - downloads/kapowarr
      - downloads/lncrawl
      - downloads/shelfmark
      - downloads/suwayomi
      - downloads/tranga
      - entertainment/audiobookshelf
      - entertainment/bookorbit
      - entertainment/kavita
      - entertainment/komf
      - entertainment/mangarr
      - home/calibre-web-automated
      - home/ebook-reconcile
    exclude: []
    seeds: [docs/ai-context/nerdz-reading-stack.md]
  auth:
    title: Authentication & Identity
    namespaces: [security]
    include: []
    exclude: []
    seeds:
      - docs/ai-context/NETWORKING.md
      - docs/Guides/Security/Pocket ID + Tailscale SSO/README.md
  observability:
    title: Observability
    namespaces: [observability]
    include: []
    exclude: []
    seeds:
      - docs/observability-audit-2026-05.md
      - docs/infrastructure-roadmap/otel-telemetry-backbone.md
```

- [ ] **Step 2: Verify every referenced path exists**

```bash
yq '.domains[].include[], .domains[].exclude[]' .claude/skills/domain-docs/domains.yaml \
  | sed 's|^|kubernetes/apps/|' | while read -r p; do [ -d "$p" ] || echo "MISSING: $p"; done
yq '.domains[].seeds[]' .claude/skills/domain-docs/domains.yaml \
  | while read -r p; do [ -f "$p" ] || echo "MISSING SEED: $p"; done
```
Expected: no output.

- [ ] **Step 3: PAUSE — human review gate.** Present the resolved membership per domain (and the intentional-drift list: lidarr, soularr, rom-ingest, plus unclaimed entertainment apps) to Gavin for approval before proceeding. Taxonomy is his call.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/domain-docs/domains.yaml
git commit -m "feat(skills): domain-docs registry with five seed domains"
```

### Task 3: Templates

**Files:**
- Create: `.claude/skills/domain-docs/templates/context.md`
- Create: `.claude/skills/domain-docs/templates/overview.md`
- Create: `.claude/skills/domain-docs/templates/decisions.md`

**Interfaces:**
- Consumes: zone marker syntax from Task 1 (Global Constraints).
- Produces: exact file structure for every `docs/domains/<domain>/` file. `{{placeholders}}` are filled by the skill at create/update time.

- [ ] **Step 1: Write templates/context.md**

````markdown
---
description: "{{title}} — LLM context: apps, routes, storage, flows"
tags: ["{{DomainCamel}}", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# {{title}} — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [{{app}}](../../../kubernetes/apps/{{ns}}/{{app}}) | {{ns}} | {{chart-or-image}} | {{host+gateway-or-none}} | {{pvc-class-size-or-none}} | {{volsync-or-none}} | {{es-store-or-none}} | {{dependsOn-or-none}} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

```mermaid
{{dataflow-diagram}}
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- {{other-domain}}: {{one-line-touchpoint-with-links}}
<!-- generated:end -->

<!-- curated -->
## Capsules

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
````

- [ ] **Step 2: Write templates/overview.md**

````markdown
---
description: "{{title}} — human overview: what it is, how it fits together, how to operate it"
tags: ["{{DomainCamel}}", "DomainDocs"]
audience: ["Humans"]
categories: ["Overview[100%]"]
---

# {{title}}

<!-- generated:start section=summary -->
{{one-paragraph-template-sentence-summary: "The {{title}} domain runs N apps across namespaces X, Y."}}

## Components

| App | What it does | UI |
|---|---|---|
| {{app}} | {{one-liner-from-headline}} | {{https-route-or-internal}} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## How It Fits Together

```mermaid
{{dataflow-diagram — same source as context.md}}
```
<!-- generated:end -->

<!-- curated -->
## Operating Notes

<!-- Human-authored: family workflows, runbook pointers, quirks. Skill never edits below. -->
<!-- /curated -->

## Related

- [Context (LLM)](context.md) · [Decisions](decisions.md)
````

- [ ] **Step 3: Write templates/decisions.md**

````markdown
---
description: "{{title}} — decision records: the whys behind this domain"
tags: ["{{DomainCamel}}", "Decisions"]
audience: ["LLMs", "Humans"]
categories: ["DecisionRecord[100%]"]
---

# {{title}} — Decisions

Append-only. Never regenerated. New entries at the top. Format:

## YYYY-MM-DD — Chose X over Y
**Why**: ...
**Alternatives rejected**: Y (reason), Z (reason)
**Links**: manifests / PRs / external docs
````

- [ ] **Step 4: Verify zone markers are balanced in all templates**

```bash
for f in .claude/skills/domain-docs/templates/*.md; do
  s=$(grep -c 'generated:start' "$f"); e=$(grep -c 'generated:end' "$f")
  [ "$s" = "$e" ] || echo "UNBALANCED: $f ($s start / $e end)"
done
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/domain-docs/templates/
git commit -m "feat(skills): domain-docs output templates"
```

### Task 4: Pilot — create downloads domain

**Files:**
- Create: `docs/domains/downloads/context.md`
- Create: `docs/domains/downloads/overview.md`
- Create: `docs/domains/downloads/decisions.md`

**Interfaces:**
- Consumes: SKILL.md `create` mode (Task 1), registry (Task 2), templates (Task 3).
- Produces: the reference example every later domain must structurally match.

- [ ] **Step 1: Run the skill's create mode for `downloads` exactly as written in SKILL.md** — resolve membership (downloads namespace minus 19 excludes ⇒ ~12 apps), read each app's `ks.yaml` + `app/*.yaml`, fill all generated zones in all three files.
- [ ] **Step 2: Mermaid loop** — build the data-flow diagram (expected shape: prowlarr → arr stack boundary; autobrr/cross-seed → qbittorrent; sabnzbd/qbittorrent/slskd → completed-downloads path; tqm/unpackerr as operators). Render, Read the PNG, fix, ≤3 iterations.
- [ ] **Step 3: Verify structure**

```bash
for f in docs/domains/downloads/{context,overview,decisions}.md; do [ -f "$f" ] || echo "MISSING $f"; done
grep -L 'generated:start' docs/domains/downloads/context.md docs/domains/downloads/overview.md
# apps table sorted check:
awk '/section=apps/,/generated:end/' docs/domains/downloads/context.md | grep -o '^\| \[[a-z0-9-]*\]' | sort -c && echo SORTED
```
Expected: no MISSING, no grep -L output, `SORTED`.

- [ ] **Step 4: Cleanup + verify** — delete scratchpad `.mmd`/`.png`; `git status` shows only the three new docs.
- [ ] **Step 5: Commit**

```bash
git add docs/domains/downloads/
git commit -m "docs(domains): seed downloads domain docs"
```

### Task 5: Idempotency test — update downloads

**Files:**
- Modify (expected: no change): `docs/domains/downloads/*.md`

**Interfaces:**
- Consumes: SKILL.md `update` mode; Task 4 output.
- Produces: proof the determinism rules hold (the spec's core promise).

- [ ] **Step 1: Add a curated marker sentinel** — insert one line of prose in each file's curated zone (e.g. "SENTINEL: curated content survives updates.").
- [ ] **Step 2: Run `update downloads` per SKILL.md** — full re-extraction, rebuild generated zones.
- [ ] **Step 3: Verify zero generated-zone diff and sentinel survival**

Run: `git diff --stat docs/domains/downloads/`
Expected: diffs ONLY from Step 1's sentinel lines; every generated zone byte-identical. If generated zones differ → fix the template/SKILL.md ambiguity that caused it (this is the escape-hatch trigger from the spec: recurring inconsistency ⇒ consider the yq facts-JSON script) and re-run until clean.
- [ ] **Step 4: Remove sentinels, cleanup artifacts, commit any skill fixes**

```bash
git add .claude/skills/domain-docs/ && git commit -m "fix(skills): tighten domain-docs determinism" # only if fixes were needed
git checkout docs/domains/downloads/ # discard sentinels if no other changes
```

### Task 6: Create remaining four domains

**Files:**
- Create: `docs/domains/{media,reading,auth,observability}/{context,overview,decisions}.md` (12 files)

**Interfaces:**
- Consumes: everything prior; Task 4's downloads docs as the structural reference.
- Produces: complete five-domain doc set.

- [ ] **Step 1: `create media`** — include-driven membership (14 apps). Diagram: request flow seerr → arrs → downloads-domain boundary (link, don't re-draw downloads internals) → plex; tautulli/wizarr as observers. Seed curated zones from `docs/Guides/plex-arr-monitoring-stack.md`, tagged `<!-- seeded: review -->`. Full mermaid loop + cleanup. Commit: `docs(domains): seed media domain docs`
- [ ] **Step 2: `create reading`** — 13 apps. Seed from `nerdz-reading-stack.md` (its genre-tree contract, metadata layers, and seed-safety rules go into curated zones and candidate decisions.md entries — flagged for review, not invented). Commit: `docs(domains): seed reading domain docs`
- [ ] **Step 3: `create auth`** — pocket-id + oauth2-proxy; integration section will reference most other domains (OIDC consumers). Diagram: TB auth flow per NETWORKING.md's model, ≤12 nodes. Commit: `docs(domains): seed auth domain docs`
- [ ] **Step 4: `create observability`** — 18 apps; if the data-flow diagram exceeds 12 nodes, split into metrics and logs/alerts diagrams per SKILL.md rule. Seed from the 2026-05 audit + otel backbone docs. Commit: `docs(domains): seed observability domain docs`
- [ ] **Step 5: Structural parity check across all five domains**

```bash
for d in downloads media reading auth observability; do
  for f in context overview decisions; do [ -f "docs/domains/$d/$f.md" ] || echo "MISSING $d/$f"; done
  grep -q 'section=apps' "docs/domains/$d/context.md" || echo "NO APPS ZONE: $d"
done
```
Expected: no output.

### Task 7: Audit mode shakedown + integration

**Files:**
- Modify: `docs/ai-context/README.md` (add docs/domains to the document map)
- Modify: `docs/ai-context/nerdz-reading-stack.md` (trim to a pointer at `docs/domains/reading/`)

**Interfaces:**
- Consumes: full doc set (Task 6); SKILL.md `audit` mode.
- Produces: first drift report; docs graph wired together.

- [ ] **Step 1: Run `audit` per SKILL.md.** Expected findings: intentional-drift apps (lidarr, soularr, rom-ingest; unclaimed entertainment/home/games apps under partially-claimed namespaces only — claimed namespaces are downloads, security, observability). Anything else found is a real bug: fix skill or registry, commit.
- [ ] **Step 2: Trim `nerdz-reading-stack.md`** — replace body with frontmatter + 3-line pointer to `docs/domains/reading/` (content now lives there; per spec the old file is raw material, superseded).
- [ ] **Step 3: Update `docs/ai-context/README.md` document map** — add a "Domain Docs" row set linking the five `docs/domains/<domain>/` sets and noting they are maintained by the `domain-docs` skill (run `update` after cluster changes, `audit` to check drift).
- [ ] **Step 4: Final repo hygiene** — scratchpad artifact sweep, `git status` clean except intended changes.
- [ ] **Step 5: Commit**

```bash
git add docs/ai-context/README.md docs/ai-context/nerdz-reading-stack.md
git commit -m "docs(domains): wire domain docs into ai-context map"
```

---

## Self-Review Notes

- Spec coverage: layout→T1/T3, registry→T2, zones→T1/T3/T5, determinism→T5, mermaid loop→T1/T4/T6, cleanup→every create/update task, modes→T1 (defined) T4/T5/T7 (exercised), seeding table→T2 `seeds:` + T6, decision capture convention→lives in SKILL.md (T1) and decisions.md template (T3), README/AGENTS integration→T7.
- Human gates: Task 2 Step 3 (taxonomy approval) is the only mid-plan pause; all other review happens at normal task boundaries.
