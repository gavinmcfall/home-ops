---
description: Plan for taking the three Sonarr instances from 4.0.20 to v5, and the finding that no stable v5 release exists yet.
tags: [sonarr, arr, postgres, cnpg, upgrade, plan]
audience: { human: 50, agent: 50 }
purpose: { north-star: 0, gestalt: 0, reference: 10, research: 20, design: 5, plan: 65, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: Sonarr 4.0.20 → v5

Covers [#2819](https://github.com/gavinmcfall/home-ops/pull/2819) (`ghcr.io/home-operations/sonarr 4.0.20 ➔ 5.0.0`).

## The finding that gates this plan

**Sonarr v5 has no stable release.** 📄 Every `v5.0.0.x` tag on the upstream repository is marked `prerelease=true` — the most recent being `v5.0.0.2742` — while the newest non-prerelease tag is `v4.0.20.3014`. 📚 The v5 release bodies are auto-generated changelogs: they state no breaking changes, no migration notes, no minimum requirements, and no downgrade or PostgreSQL guidance.

So merging #2819 would move **three production instances** onto a prerelease train, against a schema migration with no documented rollback. That is the whole reason this is a plan and not a merge.

The recommendation is therefore: **wait for a stable v5.0.0 and a migration note, then execute the stages below.** Everything else here is preparation that holds regardless of when that happens.

## Scope

**Covers:**
- `sonarr`, `sonarr-foreign` and `sonarr-uhd` from `4.0.20` to a stable v5
- The PostgreSQL schema migration for each instance's own database
- Re-verifying the consumers that talk to Sonarr's API

**Does not cover:**
- Radarr, Lidarr, Bazarr or Prowlarr, which version independently
- The CNPG Postgres image itself ([#2831](https://github.com/gavinmcfall/home-ops/pull/2831) — commented there; it needs the cluster `imageName` moved in the same change, which rolls every database)

## Enables

- Unblocks the Sonarr line, which Renovate will keep raising
- Removes the last `type/major` app PR from the queue once done

## Prerequisites

- **A stable, non-prerelease v5 release**, and ideally an upstream migration note. This is the gate; nothing below should start without it.
- A verified restore point for each of the three Sonarr databases. These are Postgres-backed, not SQLite: 📄 each instance carries an `init-db` init container (`ghcr.io/home-operations/postgres-init:17.6.0`) and `SONARR__POSTGRES__{HOST,PORT,MAINDB,PASSWORD}` in `sonarr-secret`, so the state lives in CNPG, not in the config PVC. A PVC snapshot alone does **not** protect this data.
- A recorded inventory of each instance's API consumers (see Done Criteria).
- Confirmation of what `ghcr.io/home-operations/sonarr:5.0.0` actually wraps — whether it tracks a prerelease build or waits for stable. The upstream tag state above is about Sonarr itself, not this image.

## North Star

All three Sonarr instances run a stable v5, each against its own migrated database, with series/episode/queue data intact, and every downstream consumer — metrics, request management, indexer and post-processing integrations, dashboards — still functioning.

## Stages

### Stage 1 — Inventory the blast radius

Sonarr is not a leaf. Before changing it, enumerate what calls its API, because an API change in a major version breaks callers silently rather than loudly.

Known candidates in this repo: `observability/exportarr-sonarr` (metrics), `downloads/prowlarr`, `downloads/cross-seed`, `downloads/tqm`, `downloads/bazarr` + `bazarr-foreign` + `bazarr-uhd`, `downloads/dashbrr`, `entertainment/seerr`, `observability/notifiarr`, and the `gethomepage.dev/widget.*` annotations on the Sonarr routes.

- The inventory shall record, per consumer, how it authenticates and which endpoints it uses, so each can be re-checked after the upgrade.

### Stage 2 — Prove the migration on one instance

`sonarr-foreign` or `sonarr-uhd` is the right first subject — same code path, smaller consequence than the primary.

- One instance shall be upgraded first, and its migration observed in the logs before the others are touched.
- When the migration completes, the instance shall serve `/ping` and its series list shall be intact.
- If the migration fails, then the database shall be restored from its verified restore point before any retry — not the PVC.

**Gate:** chosen instance healthy on v5, data intact, its consumers re-checked.

### Stage 3 — Remaining instances

- The other two instances shall be upgraded only after the first is confirmed good, each with its own database migration.

### Stage 4 — Re-verify consumers

- Each consumer from the Stage 1 inventory shall be confirmed working, not assumed.
- `exportarr-sonarr` shall still export metrics; dashboards fed by it shall still populate.

## Done Criteria

### Application state
- Each of the three instances shall report `Ready` and respond on `/ping` (📄 the existing liveness/readiness probe path).
- Each instance's series, episode and queue data shall be present after migration.
- The `SONARR__AUTH__METHOD: External` arrangement shall continue to work, so access control is unchanged.

### Database
- Each instance shall have migrated its own database; no instance shall share another's.
- If a schema migration partially applies, then recovery is a database restore — treat the migration as one-way.

### Integrations
- Every consumer identified in Stage 1 shall be verified working after the upgrade.
- When `exportarr-sonarr` scrapes a v5 instance, it shall return metrics rather than errors.

### Version hygiene
- The running image shall be a stable v5 release, not a prerelease.
- 📄 `SONARR__UPDATE__BRANCH: develop` is set on all three instances. Where that branch selection no longer matches the intended release train under v5, it shall be corrected rather than left stale.

## Constraints

- **Do not merge #2819 while every upstream v5 tag is a prerelease.** This is the binding constraint.
- **One instance at a time.** Three simultaneous schema migrations against the same Postgres cluster gives three failures and no attribution.
- **Database first, PVC second.** The protective artefact for these apps is the CNPG backup, not the config volume. A plan that only snapshots PVCs has not protected Sonarr.
- **Do not combine with the CNPG Postgres image bump** (#2831). Migrating a schema while the database engine image is also rolling is two variables at once.
- **Treat the migration as irreversible.** Nothing upstream documents a v5→v4 downgrade, so rollback means restore.

## References

- 📄 `kubernetes/apps/downloads/sonarr/app/helmrelease.yaml` — image pin, `init-db`, `SONARR__*` env; `sonarr-foreign` and `sonarr-uhd` mirror it
- 📄 `sonarr-secret` keys — `INIT_POSTGRES_*` and `SONARR__POSTGRES__*`, confirming Postgres-backed state
- 📚 [Sonarr releases](https://github.com/Sonarr/Sonarr/releases) — check for a non-prerelease v5.0.0 before starting
- 📚 [home-operations containers](https://github.com/home-operations/containers) — the image this repo actually consumes
- Plan: `rook-ceph-1.21-upgrade-plan.md`, `talos-1.13-upgrade-plan.md` — unrelated, but all three compete for the same maintenance attention

**Error policy:** a failed migration is a restore, not a retry. Stop at the first instance that fails, restore its database, and do not proceed to the remaining instances.
