---
description: Sectioned rollout plan for app-template 4.6.2 to 5.3.0 together with postgres-init 17 to 18.7.0, ordered by a runtime dependency map so nearly every app restarts once, in controlled groups.
tags: [app-template, bjw-s, postgres-init, renovate, rollout, dependency-map, plan]
audience: { human: 55, agent: 45 }
purpose: { north-star: 0, gestalt: 0, reference: 20, research: 15, design: 5, plan: 60, flow: 0, findings: 0, concepts: 0, high-agency-process: 0, low-agency-process: 0 }
---

# Plan: app-template 4.6.2 → 5.3.0 and postgres-init 17 → 18.7.0

Status: **proposed, nothing started.** Written 2026-11-16 from a read-only survey of the repo and cluster.

Renovate raised this as one PR ([#3096](https://github.com/gavinmcfall/home-ops/pull/3096)) touching about 117 HelmReleases. Merged as it stands, every app-template pod restarts at once and four apps lose access to the Kubernetes API. This plan lands the same change in sections.

## What changes

**app-template 5.0** changes the rendered output of every release:

- `automountServiceAccountToken` flips from `true` to `false`.
- Every release gets its own ServiceAccount, named after the release, in place of `default`.
- So **every app-template pod restarts once**, and a pod that reads the mounted token loses the Kubernetes API unless it opts back in.
- ServiceMonitor `jobLabel` becomes `app.kubernetes.io/name`. Two Prometheus `job` labels change: `mosquitto-exporter` → `mosquitto`, `qbittorrent-seedboxapi-metrics` → `qbittorrent`. Nothing in the repo uses the old names; Grafana dashboards outside git were not checked.
- ServiceAccount names that RBAC binds to do **not** change.
- Not relevant here: no release uses `rawResources` or chart NetworkPolicies.

**postgres-init 18.7.0** is the init container that creates each app's database and user. The script is unchanged; the image base moved to `postgres:18-alpine` and runs as `nobody`. bookorbit, immich and well-played already run this digest. A 17 client against an 18 server works today, so this half is tidy-up, done here because it costs no extra restart when it lands in the same commit as the chart bump.

## Apps that must opt back in to the API token

Add `defaultPodOptions.automountServiceAccountToken: true` in the **same commit** as that app's chart bump.

| Release | Why |
|---|---|
| `database/dragonfly-operator` | ClusterRoleBinding; leader-election leases |
| `downloads/dashbrr` | lists and watches Services |
| `home/homepage` | `mode: cluster` Kubernetes widgets |
| `observability/gatus` | k8s-sidecar watches ConfigMaps in all namespaces |
| `games/dune-awakening` | shelved; set on the `game-survival` controller when it returns |

`observability/kait` already sets it. Ruled out: kromgo, development-container, kometa, discord-exporter. No live RoleBinding names a `default` ServiceAccount.

## How it is split

Each 4.x HelmRelease pins `chart.spec.version` itself, so a section is the set of files whose version line moves. Each section is a **hand-made PR**: the version bump plus the automount and postgres-init edits for the apps in it. #3096 shrinks on each rebase and closes after the last section. `observability/ipmi-exporter` (4.4.0, outside #3096) is bumped by hand in section 2.

Seven releases already run 5.3.0 here: cross-seed, immich, spyglass, kait, ntfy, ntfy-alertmanager, kopia.

## Dependency map

Numbers in brackets are how many other releases depend on that one.

- **Foundations, not app-template and not touched:** CloudNativePG clusters, the dragonfly instance, mariadb, the envoy gateways, external-secrets, Prometheus.
- **Platform pieces that are app-template:** onepassword-connect (91, through ExternalSecrets), cloudflared (30 external routes), pocket-id (20 OIDC clients).
- **Tier 0 providers:** plex (13), qbittorrent (13), sabnzbd (8), influxdb (7), smtp-relay (6), mosquitto (3), flaresolverr (3).
- **Tier 1:** prowlarr (10), tautulli, paperless, audiobookshelf, oauth2-proxy, teslamate, vitals ingesters, OIDC clients.
- **Tier 2:** sonarr and radarr variants, lidarr, calibre-web-automated, lighthouse, homepage, paperless-ai, paperless-gpt.
- **Tier 3 (leaves):** bazarr variants, seerr, kometa, recyclarr, unpackerr, exportarr, notifiarr, dashbrr, cross-seed.

The arr → prowlarr/qbittorrent/sabnzbd edges are inferred (those URLs live in secrets). The rest come from env, config and service hostnames.

## Sections

`*` = postgres-init bump in the same commit. `^` = add the automount line in the same commit.

| # | Section | Releases | If it goes wrong |
|---|---|---|---|
| 1 | Canary (5) | speedtest-exporter, maloja, atuin\*, dashbrr\*^, recyclarr | five unimportant apps |
| 2 | Observability and vitals (23) | exporters, kromgo, notifiarr, redisinsight, unpoller, gatus\*^, ipmi-exporter, vitals influxdb and ingesters, telegraf | status page, dashboards, health data |
| 3 | Shared services (4) | mosquitto, influxdb3, dragonfly-operator^, smtp-relay | MQTT clients reconnect; mail; cache operator |
| 4 | Home, games, cortex, home-automation, storage (30 live) | homepage^, paperless\* with paperless-ai and paperless-gpt, linkwarden\*, manyfold\*, romm\*, livingdex\*, teslamate\*, home-assistant, pelican, bookstack, affine, searxng and the rest | household apps |
| 5a | Media: downloads (27 live) | prowlarr\*, sonarr\*/radarr\*/bazarr\* variants, lidarr\*, autobrr\*, suwayomi\*, tranga\*, qbittorrent, sabnzbd, bindery, shelfmark, unpackerr and the rest | downloading |
| 5b | Media: entertainment (15 live) | plex, tautulli, kometa, seerr, audiobookshelf, bookorbit, kavita, jelu, navidrome, tdarr, wizarr and the rest | playback and reading |
| 6a | Platform helpers | echo-server, cloudflare-ddns, irqbalance, zot | low |
| 6b | Ingress, alone | cloudflared | **all external access** |
| 6c | Secrets, alone | onepassword-connect | every ExternalSecret refresh |
| 7a | Auth, alone | pocket-id\* | **every OIDC login** |
| 7b | Auth, alone | oauth2-proxy | lighthouse |

Smallest blast radius first. Ingress, secrets and auth are last and each alone, so nothing else is in flight if one misbehaves.

### Verification

Every section: each HelmRelease Ready at 5.3.0, each pod Ready, and `scripts/cluster-gate.sh` ALL-PASS before the next section.

| # | Specific checks |
|---|---|
| 1 | atuin `init-db` log ends "Update User Privileges"; dashbrr discovers Services with no 403 |
| 2 | gatus sidecar still loads endpoints; Prometheus targets up; fresh points in the vitals InfluxDB |
| 3 | `up{job="mosquitto"}`; dragonfly-operator holds its lease, no "forbidden"; home-assistant, teslamate and telegraf reconnect to MQTT; a test mail goes through |
| 4 | homepage cluster widgets populate; paperless login via pocket-id; romm and pelican answer |
| 5a | `up{job="qbittorrent"}`; prowlarr syncs indexers to the arr apps |
| 5b | a Plex stream plays; tautulli connected; `rollout restart` plex-exporter, which crash-loops after Plex restarts |
| 6b | an external-only URL answers through Cloudflare, resolved via public DNS |
| 6c | ClusterSecretStore Ready; a forced ExternalSecret refresh succeeds |
| 7a | an OIDC login on immich completes |
| 7b | lighthouse loads through the proxy |

### Timing

VolSync backups run at :00, :05 and :10 of every hour and through hours 00, 06, 12 and 18 UTC. Sections merge outside those windows. pocket-id backs up at :00, so 7a goes mid-hour.

### Rollback

Revert that section's PR. Every HelmRelease has `upgrade.remediation.strategy: rollback`, so a failed upgrade returns to 4.6.2 by itself. Neither change touches stored data.

## After the last section

- Remove `"/postgres-init/"` from the "Skip major updates for stateful databases" rule in `.renovaterc.json5`.
- Confirm #3096 closed itself.
- Decide on manifests for apps that are not deployed (dune-awakening, development-container, nerdz-landing, discord-exporter, soularr, peertube): bump with their section or leave.

## Not verified

- That one commit carrying both changes causes exactly one restart per app (expected, not tested).
- The 5.x ServiceAccount template was not read line by line; behaviour is from the upgrade guide and the live `ntfy` release.
- Whether any app on the `default` ServiceAccount reads the token without RBAC. None found in the manifests.
- Grafana dashboards outside git for the two renamed `job` labels.

## Sources

- [app-template 4 → 5 upgrade guide](https://bjw-s-labs.github.io/helm-charts/docs/app-template/upgrades/4-to-5/)
- [common 5.0.0 release notes](https://github.com/bjw-s-labs/helm-charts/releases/tag/common-5.0.0)
- [home-operations postgres-init](https://github.com/home-operations/containers/tree/main/apps/postgres-init)
