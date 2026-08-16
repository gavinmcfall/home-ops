---
name: domain-docs
description: "Generate, update, and audit per-domain docs (docs/domains/) from kubernetes manifests. Use when creating a domain doc set, refreshing docs after cluster changes, or checking for doc drift. Modes: create <domain>, update <domain|all>, audit."
---

# Domain Docs

Produce structurally identical, manifest-accurate domain documentation.
Spec: `docs/superpowers/specs/2026-08-15-domain-docs-skill-design.md`.

## Inputs

- `domains.yaml` (this directory) — the ONLY source of domain membership.
- `kubernetes/apps/<ns>/<app>/` (+ `flux/` if needed) — the ONLY source of generated facts.
  Read per app: `ks.yaml` (Flux Kustomization: dependsOn, components),
  `app/helmrelease.yaml` (chart, image, env, route, persistence),
  `app/*.yaml` (externalsecret, pvc, httproute if split out).
- `templates/` (this directory) — structure of every output file.

## Membership resolution

`namespaces` minus `exclude` plus `include` (entries are `<ns>/<app>` paths).
An app may appear in multiple domains; each mention links to the owning
domain's context.md for depth. Any app under a registry-claimed namespace
that resolves to no domain → drift report. Never guess membership.

Membership is one member per leaf directory that contains its own `ks.yaml`
under a claimed namespace path — a grouping directory (e.g. `exporters/`)
is not itself a member, it enumerates its leaf children. `include`/`exclude`
entries are taken literally as written and may carry intermediate path
segments (e.g. `observability/exporters/blackbox-exporter`). The Apps table's
Namespace column reports the leaf's `ks.yaml` `spec.targetNamespace` (where
its resources actually land), which can differ from the claimed namespace the
directory lives under — membership still follows the owning directory, not
`targetNamespace`. The Apps table's DependsOn column is sourced from
`ks.yaml` `spec.dependsOn` only (Kustomization-level, Flux ordering); a
HelmRelease's own `spec.dependsOn` is a different, unrelated field and is
never surfaced in that column.

## One-liner descriptions

The overview.md Components "What it does" column must be deterministic —
resolve each app's one-liner via this precedence, stopping at the first hit:

1. `domains.yaml` → `<domain>.descriptions.<app>`, if the registry entry
   has a `descriptions:` map with this app as a key. Registry-authored text
   always wins.
2. The app's `gethomepage.dev/description` route annotation, used
   **verbatim** — no editorial extensions, no appended clauses. A
   commented-out annotation is not a source and does not count.
3. Fixed fallback string: `No description — add one to domains.yaml or a
   gethomepage annotation`.

Never invent or extend a one-liner outside this precedence.

## Integration Points direction

Direction is normative, not descriptive, so a fresh extraction is
deterministic regardless of which domain runs first. Every cross-domain
reference is extracted once, from the single manifest that carries it, and
rendered as two bullets:

- **Outbound** — filed in the domain whose app's own manifest holds the
  reference (env var, ExternalSecret template, `gethomepage.dev` annotation,
  `configMapGenerator` label, etc.) pointing at another domain's app.
  Label the bullet `<target-domain> (outbound): ...`.
- **Inbound** — filed in the target domain, mirroring the same fact so a
  reader of either domain's page sees the full picture. Label the bullet
  `<source-domain> (inbound): ...` and append `(see [<source> domain](../<source>/context.md))`.

Both bullets describe the same manifest — the one that carries the
reference — never a second, independently-derived source; the inbound
bullet restates the outbound bullet's fact, it does not re-derive it.
A `loki_rule: "true"` `configMapGenerator` label (a Loki alerting-rule
ConfigMap) counts as manifest evidence like any other cross-domain wiring —
model it uniformly wherever it appears, even if no in-repo consumer can be
confirmed for the label yet.

## Zone semantics

- `<!-- generated:start section=NAME -->` … `<!-- generated:end -->`:
  owned by this skill. Fully overwritten every update. Never hand-edit.
- `<!-- curated -->` … `<!-- /curated -->` blocks and anything outside markers: NEVER modified
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
   - orientation fits (LR pipelines, TB hierarchies); ≤12 app nodes
     (junction/data nodes don't count);
   - NO edge passes through or near a subgraph title. Titles render
     top-center, so any edge entering a subgraph from outside-above
     crosses them. Layout shifts between mermaid versions/renderers —
     a near-miss in mmdc is a collision in VS Code. Treat "close to
     the title" as a fail, not a pass.
4. Fail → restructure, in this order:
   - Nodes that receive edges from outside the box: unbox them — carry
     the grouping in classDef colors or `<br>` node-label suffixes
     instead of a titled subgraph.
   - N sources each feeding the same M targets: collapse the N×M edges
     through one small junction node (e.g. `fanout(("all M"))`, styled
     neutral, flagged as not-an-app in the GOTCHA comment).
   - Then direction/ordering tweaks. Max 3 iterations, then simplify.
5. Real-but-not-manifest-declared steps (manual workflows, suspended
   CronJobs) may appear as DASHED edges only, and the GOTCHA comment
   must name the provenance (the source doc or the manifest field that
   proves the dormancy). Solid edges stay manifest-evidenced.
6. Style per `docs/ai-context/mermaid-diagram-guide.md`.

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
