---
description: Comparison of Outline and Anytype as self-hosted documentation platforms for a small collaborative group with AI tooling requirements
tags: [outline, anytype, wiki, documentation, self-hosted, knowledge-base]
audience: { human: 85, agent: 15 }
purpose: { research: 90, reference: 10 }
---

# Outline vs Anytype

Research for: Should we stick with Outline (already deployed), add Anytype alongside it, or switch entirely?

*Research date: 15 March 2026*

## Context

Outline is deployed and operational in the home-ops Kubernetes cluster with SSO (Pocket-ID), S3 (Rook-Ceph RGW), and PostgreSQL. ~38 documents migrated from Notion across 18 collections.

The platform serves 4-6 users (mix of technical and non-technical). AI tools must read/write the documentation: Claude Code (via MCP), OpenClaw (local LLM), and N8N (automation workflows).

Decision: Deploy Anytype alongside Outline for evaluation. Keep Outline as the shared team wiki. Trial Anytype for structured data, personal knowledge management, and native mobile use cases.

---

## Outline

### What It Is

A server-first team wiki built on Node.js, PostgreSQL, Redis, and S3-compatible storage. Markdown-native, real-time collaborative editing. Collections contain documents in a tree structure.

> [Outline GitHub](https://github.com/outline/outline) — 29k+ stars, active development since 2016, maintained by a small core team with SaaS revenue funding

### Collaboration

Real-time multi-user editing via WebSockets (Prosemirror + Y.js CRDTs). Inline threaded comments with resolution. Full document version history with diff and restore. Role-based permissions: Admin, Member, Viewer, Guest. Collection-level and document-level sharing. Public links with optional password protection.

### API and Integrations

Comprehensive JSON-RPC API covering documents (CRUD, search, move, archive), collections, users, groups, shares, attachments, and events. Webhooks for document and collection lifecycle events. Built-in Slack integration. OIDC/SAML/Google/Azure AD authentication.

> [Outline API Documentation](https://www.getoutline.com/developers) — official, maintained

**MCP Server:** A community MCP server exists (`huiseo/outline-wiki-mcp`).

> [Outline Wiki MCP on Glama](https://glama.ai/mcp/servers/@huiseo/outline-wiki-mcp) — community-maintained, not official

### Data Model

Documents in Collections. Documents are Markdown stored in PostgreSQL. Arbitrary nesting depth within collections. Templates supported as first-class objects. Simple tables (not databases). No structured data/relations/views. No object graph. No kanban/calendar views.

### Mobile

PWA only. No native iOS or Android apps. Limited offline support — requires server connection for most operations.

### Search

PostgreSQL full-text search (tsvector/tsquery). Respects permissions. Scoped to collection or workspace-wide. Adequate for small-to-medium instances.

### Self-Hosting

Standard stack: Node.js app + PostgreSQL + Redis + S3. Well-documented. Docker and Kubernetes friendly. Single-container app. Currently deployed in home-ops cluster via BJW-S app-template.

> [Outline Hosting Docs](https://docs.getoutline.com/s/hosting/doc/hosting-outline-nipGaCRBDu) — official

### Known Limitations

- No structured data/databases (most requested feature)
- No native mobile apps
- No plugin/extension system
- No offline-first capability
- Single workspace per instance
- SSO required (no username/password auth)
- BSL license (converts to Apache 2.0 after 3 years)

---

## Anytype

### What It Is

A local-first, end-to-end encrypted knowledge platform. Data lives on-device first, synced via the "Any-Sync" protocol (CRDT-based Merkle DAG). Object-graph data model with types, relations, and sets.

> [Anytype website](https://anytype.io/) — "A safe haven for digital collaboration"
> [AnyProto GitHub organization](https://github.com/anyproto) — open-sourced 2023, 7.2k stars on desktop client

### Key Repositories

| Repo | Purpose | Stars |
|------|---------|-------|
| [anytype-ts](https://github.com/anyproto/anytype-ts) | Desktop client (Electron) | 7,222 |
| [any-sync](https://github.com/anyproto/any-sync) | Sync protocol | 1,549 |
| [any-sync-dockercompose](https://github.com/anyproto/any-sync-dockercompose) | Official self-hosting Docker Compose | 800 |
| [anytype-kotlin](https://github.com/anyproto/anytype-kotlin) | Android client | 853 |
| [anytype-swift](https://github.com/anyproto/anytype-swift) | iOS client | 460 |
| [anytype-heart](https://github.com/anyproto/anytype-heart) | Shared middleware library (Go) | 374 |
| [anytype-mcp](https://github.com/anyproto/anytype-mcp) | Official MCP server | 335 |
| [anytype-api](https://github.com/anyproto/anytype-api) | API spec + developer portal | 90 |
| [anytype-cli](https://github.com/anyproto/anytype-cli) | Headless CLI for automation | 68 |
| [anytype-publish-server](https://github.com/anyproto/anytype-publish-server) | Read-only web publishing | 8 |

> All repos actively maintained, most updated within days of research date (March 2026)

### Collaboration

Spaces model — each space is a self-contained workspace shared with others. Permissions are space-level: Owner, Editor, Viewer. No per-object granular permissions. CRDT-based conflict resolution via Any-Sync. Real-time multiplayer is functional but newer than Outline's.

### API and Integrations

Anytype released a Local API in v0.46.x and has an official MCP server.

**Local API:**
- Runs on `localhost:31009` (desktop app) or `localhost:31010-31012` (CLI/headless mode)
- Binds to `127.0.0.1` by default
- **`anytype-cli` supports `--listen-address 0.0.0.0:31012`** for network access
- API key generated from desktop app settings or via CLI
- Supports: search, spaces, members, objects, lists, properties, tags, types, templates

> [Anytype Local API Docs](https://doc.anytype.io/anytype-docs/advanced/feature-list-by-platform/local-api) — official, v0.46.x
> [Anytype Developer Portal](https://developers.anytype.io/) — official
> [anytype-cli README](https://github.com/anyproto/anytype-cli) — documents `--listen-address` flag and remote access options

**Headless CLI:**
- `anytype-cli` runs Anytype as a headless server for automation/scripting
- Uses a dedicated **bot account** (not your personal account) — clean separation
- Can join spaces via invite links, create API keys, run as a system service
- Can be installed as a systemd user service for production use

> [anytype-cli GitHub](https://github.com/anyproto/anytype-cli) — official, MIT licensed, Go-based

**MCP Server:**
- Official: `@anyproto/anytype-mcp` (MIT licensed)
- Supports Claude Desktop, Cursor, Windsurf, Claude Code
- Features: global/space search, CRUD objects, properties, tags, types, templates
- Supports custom `ANYTYPE_API_BASE_URL` — can point at a remote CLI instance

> [anytype-mcp GitHub](https://github.com/anyproto/anytype-mcp) — official, MIT license
> [Reddit announcement](https://www.reddit.com/r/Anytype/comments/1kzs3ax/anytype_now_has_an_api_and_can_be_connected_to/) — 99 upvotes

**N8N/Automation:** The CLI with `--listen-address 0.0.0.0:31012` makes the API network-accessible. N8N can reach it via HTTP as a standard REST endpoint.

### Data Model

Object-graph, not document-tree:
- **Objects** — fundamental unit (pages, tasks, bookmarks, anything)
- **Types** — define what kind of object (Page, Task, Book, etc.)
- **Relations** — typed properties connecting objects (Due Date, Author, Tags)
- **Sets** — dynamic filtered views over objects (like Notion database views)
- **Collections** — manually curated groups

This enables Notion-like databases, knowledge graphs, and structured data. The tradeoff is a steeper learning curve.

### Mobile

Native iOS and Android apps. Offline-first by design — mobile apps work fully offline with sync on reconnect.

### Search

Local search on-device. No server-side search index.

### Self-Hosting (Sync Infrastructure)

Self-hosting Anytype means hosting the **sync relay**, not the app. Data lives on each user's device. Two deployment paths:

**Official (Docker Compose):**
6+ components: coordinator, sync-node, file-node, consensus-node, MongoDB, Redis, S3.

> [any-sync-dockercompose](https://github.com/anyproto/any-sync-dockercompose) — official

**Community All-in-One ([any-sync-bundle](https://github.com/grishy/any-sync-bundle)):**
Single container with embedded MongoDB and Redis. 800 stars, actively maintained (v1.3.1, Feb 2026). Two image variants:

| Image | Description |
|-------|-------------|
| `ghcr.io/grishy/any-sync-bundle:1.3.1-2026-02-16` | All-in-one (embedded MongoDB + Redis) |
| `ghcr.io/grishy/any-sync-bundle:1.3.1-2026-02-16-minimal` | Minimal (external MongoDB + Redis) |

- Only 2 ports: TCP 33010 (DRPC) + UDP 33020 (QUIC)
- BadgerDB as default local storage, optional S3
- Single env var to configure: `ANY_SYNC_BUNDLE_INIT_EXTERNAL_ADDRS`

> The minimal image can use Dragonfly (already in cluster) as the Redis backend — Dragonfly is 100% Redis API compatible.

**No web frontend.** Anytype has no browser-based UI. Users must install desktop (Electron) or mobile (iOS/Android) apps. The `anytype-publish-server` repo provides read-only web publishing of selected pages, but is not a full editor.

### Pricing

Free if self-hosted. No features gated. Paid plans only for Anytype's managed cloud sync (storage tiers).

> [Anytype Pricing](https://anytype.io/pricing/) — official
> [Reddit: "Anytype is and will remain free as long as you use your own backups"](https://www.reddit.com/r/Anytype/comments/14ecaxp/pricing/) — Anytype team member

### License

"Any Source Available License" (ASAL) for core repos — **not** OSI-approved open source. You can view, modify, self-host, but cannot build a competing commercial service. The MCP server and CLI are MIT licensed.

### Known Limitations

- No web frontend (app install required for all users)
- Space-level permissions only (no per-object access control)
- Steep learning curve (objects, types, relations, sets)
- ASAL license (not truly open source)
- Key-based identity (lose recovery phrase = lose data)
- Self-hosting sync layer adds operational complexity

---

## Comparison

| Dimension | Outline | Anytype |
|-----------|---------|---------|
| **Architecture** | Server-first (Node.js + PostgreSQL) | Local-first (on-device + sync relay) |
| **Data model** | Document tree (Collections > Docs) | Object graph (Types, Relations, Sets) |
| **Structured data** | No | Yes (Sets, Relations — Notion-like) |
| **Web access** | Yes — it IS a web app | No — app install required |
| **Real-time collab** | Mature (WebSocket, Y.js) | Newer (CRDT, Any-Sync) |
| **Permissions** | Role + collection + document level | Space-level only |
| **REST/HTTP API** | Network-accessible, comprehensive | Network-accessible via CLI `--listen-address` |
| **MCP server** | Community (`huiseo/outline-wiki-mcp`) | Official (`@anyproto/anytype-mcp`, MIT) |
| **N8N integration** | Direct REST API | Via CLI with network bind |
| **Mobile** | PWA only | Native iOS + Android |
| **Offline** | Minimal | Full (local-first) |
| **Encryption** | None at app level | E2E encrypted by default |
| **Self-host complexity** | Low (1 app + PG + Redis + S3) | Low-Medium (any-sync-bundle AIO + CLI) |
| **K8s support** | BJW-S Helm chart, deployed | No official Helm chart, but AIO container is deployable |
| **Non-technical users** | Open browser, type, done | Install app, learn object model |
| **Notion parity** | ~60% (no databases) | ~85% (databases, relations, views) |
| **License** | BSL 1.1 (-> Apache 2.0) | ASAL (custom, not OSI) |
| **Maturity** | ~10 years, stable | ~5 years public, fast-moving |
| **Longevity risk** | Low (SaaS revenue, standard stack) | Medium (VC-funded, complex stack) |

---

## Planned Deployment Architecture

```
Users (desktop + mobile apps)
         ↕ (Any-Sync protocol, TCP 33010 + UDP 33020)
    any-sync-bundle (AIO container, embedded MongoDB + Redis)
         ↕
    PVC for /data (BadgerDB local storage)

    anytype-cli (headless bot, --listen-address 0.0.0.0:31012)
         ↕ (HTTP API via K8s Service)
    N8N / Claude Code MCP / OpenClaw
```

Both Outline and Anytype run in the cluster. Different tools for different jobs:
- **Outline** — shared team wiki (browser-accessible, simple UX, recipes, runbooks, reference docs)
- **Anytype** — structured data, personal knowledge management, native mobile, databases

---

## Gaps

- **anytype-cli container image:** No official Docker image for the CLI. May need to build one or run the binary in a generic Go image.
- **any-sync-bundle in K8s:** Works as a Docker container but untested with BJW-S Helm chart. UDP port (QUIC) needs a Service with `protocol: UDP`.
- **Anytype collaboration maturity:** Space-level collaboration with 4-6 users is newer and less battle-tested than Outline's.
- **Publish server:** `anytype-publish-server` has minimal documentation (empty README). Unclear how mature or useful it is for read-only web access.

---

## Field Sentiment

> "It just works as a wiki. Clean, fast, collaborative." — Outline users on r/selfhosted

> "It's the closest thing to a local-first Notion replacement." — Anytype users on r/selfhosted

> "Outline is so simple to use that it requires no re-learning at all." — r/Anytype user comparing complexity

> [r/selfhosted: "is outline the best open source personal wiki for selfhosting?"](https://www.reddit.com/r/selfhosted/comments/1hygt0y/is_outline_the_best_open_source_personal_wiki_for/)

> [r/selfhosted: "Notion alternative: AppFlowy vs Outline vs Affine?"](https://www.reddit.com/r/selfhosted/comments/14s9d8j/notion_alternative_appflowy_vs_outline_vs_affine/)

> [r/selfhosted: "Which Note-Taking App: AppFlowy, Affine, or Anytype?"](https://www.reddit.com/r/selfhosted/comments/1hruk49/which_notetaking_app_do_you_recommend_appflowy/)
