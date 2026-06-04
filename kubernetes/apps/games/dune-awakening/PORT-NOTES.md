# Dune Awakening — porting snapetech's compose to k8s (findings)

> Honest assessment after reading snapetech/DuneAwakeningSelfHost `compose.yaml`
> + `.env.example`. The DRAFT `app/helmrelease.yaml` is grounded in this but is
> **not deployable yet** — see "What's still needed". Not wired into Flux.

## What snapetech's compose actually is

Not a tidy image set — an **operational harness** around the Funcom images:

- Game-server containers run **`/workspace/scripts/run_server_safe.sh`**, not the
  image's own entrypoint. The repo is bind-mounted (`.:/workspace:ro`).
- **Vendor binaries** (`rg`, `busybox`, `jq`, `curl`) are mounted into the
  containers from `./vendor/bin/*` → the Funcom images are minimal/distroless and
  the wrapper scripts need a userland.
- Game config is injected as **command-line `-ini:` args** (not env), e.g.
  `-ini:engine:[FuncomLiveServices]:ServiceAuthToken=${FLS_SECRET}`,
  `-ini:game:[DuneDatabaseInterfacePSQL]:DatabaseHost=postgres:5432`,
  `-ExternalAddress=${EXTERNAL_ADDRESS}`, `-MultiHome=$POD_IP`, `-RMQGameTlsEnabled=true`.
- **game-rmq needs TLS** (mounts `ca.crt`/`server.crt`/`server.key`); exposes AMQPS on 31982.
- Helper jobs: **db-init** (`bootstrap_db.py`) and **rmq-auth-shim** (`rmq_auth_shim.py`,
  talks to `text-router:8080`).
- The `.env` also carries a large amount that is **snapetech-specific and NOT needed**:
  postgres streaming replication + failover, Landsraad goal/reveal/coriolis watchdogs,
  binary/pak patches, an admin web panel, ~40 maps in TLS-recreate lists, etc.

## Core services (the minimal viable subset)

| Service | Image | Notes |
|---|---|---|
| postgres | `igw-postgres:17.4-alpine-fc-13` | db `dune`, user `dune`, pw `${POSTGRES_DUNE_PASSWORD}`, super pw |
| admin-rmq | `seabass-server-rabbitmq:${TAG}` | `RmqTlsEnabled=false`, cache auth backend |
| game-rmq | `seabass-server-rabbitmq:${TAG}` | `RmqTlsEnabled=true`, AMQPS 31982 — **needs cert** |
| db-init | `seabass-server-db-utils:${TAG}` | Job: `bootstrap_db.py` (after postgres) |
| rmq-auth-shim | `seabass-server-db-utils:${TAG}` | needs `text-router`; mgmt user/pass |
| text-router | `seabass-server-text-router:${TAG}` | http :8080 |
| director | `seabass-server-bg-director:${TAG}` | `--RMQGameHostname game-rmq --RMQGamePort 5672 …` |
| gateway | `seabass-server-gateway:${TAG}` | player-facing |
| game-server (per map) | `seabass-server:${TAG}` | `run_server_safe.sh` + `-ini:` args; `WORLD_*` env |

Service topology (compose uses a fixed bridge 172.31.240.0/24; in k8s use DNS):
`postgres:5432`, `admin-rmq:5672`, `game-rmq:5672`, `text-router:8080`.

Key env: `FLS_SECRET` (Funcom token), `EXTERNAL_ADDRESS` (your public IPv4),
`POD_IP` (downward API → `-MultiHome`), `WORLD_NAME/WORLD_UNIQUE_NAME/WORLD_REGION/WORLD_DATACENTER_ID`,
`POSTGRES_DUNE_PASSWORD`, `POSTGRES_SUPER_PASSWORD`, `RMQ_HTTP_TOKEN_AUTH_SECRET`.

Maps (~40 in `.env`): `survival` (Hagga Basin), `deep-desert`, `overmap`, `arrakeen`,
`harko-village`, many dungeons/ecolabs/overland/faction-outposts. **Start with `survival` only.**

## What's still needed to finish the port (the real blockers)

1. **The wrapper scripts.** `run_server_safe.sh`, `bootstrap_db.py`, `rmq_auth_shim.py`
   and the rabbitmq `config/*.conf` live in snapetech's repo, not the compose. Either
   (a) vendor them as ConfigMaps, or (b) inspect the Funcom images (once in zot) to find
   the **native entrypoint** and drive it directly, skipping snapetech's bash glue.
2. **Vendor userland.** Decide how the minimal images get `rg/jq/curl/busybox` — init
   that copies them in, or a small overlay image.
3. **game-rmq TLS.** cert-manager Certificate → mount ca/cert/key.
4. **The exact `-ini:` arg list** for the game server (the compose anchors show the shape;
   the full list needs the run script).

## Recommended path (decide depth)

- **Option A — Port the harness:** pull snapetech's `scripts/` + `config/`, reproduce the
  needed pieces as ConfigMaps. Most likely to actually boot; larger effort; inherits their glue.
- **Option B — Native minimal:** after images land in zot, `skopeo`/`crane` inspect
  `seabass-server` to recover its real entrypoint + required flags, then drive the Funcom
  binary directly with our own minimal `-ini:` args — cleaner, no bash harness, but requires
  reverse-engineering the image.

Either way, **images-in-zot (image-sync) comes first** — Option B literally needs them, and
Option A still needs them to run.
