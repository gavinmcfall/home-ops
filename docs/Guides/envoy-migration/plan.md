# Envoy Route Migration Plan

References: [Namespace Index](indexes/namespace-index.md), [App Directory Index](indexes/app-directory-index.md), [Ingress File Index](indexes/ingress-index.md), and the [Envoy Route Reference](route-reference.md).

## Goals
- Replace every `Ingress` object with an Envoy Gateway `route` definition that lives inside the corresponding HelmRelease.
- Preserve existing service exposure details (hosts, tls secrets, annotations) while aligning with the Sonarr reference implementation.
- Keep work isolated on branch `envoy-route-migration`, formatting YAML with `kustomize cfg fmt` only.

## Constraints & Guardrails
- Tackle one namespace at a time; do not interleave changes across namespaces in a single commit cycle.
- Respond in chat when each namespace is complete so it can be reviewed before moving on to the next one.
- Avoid reading or modifying files outside the namespace currently in scope to reduce merge risk.
- Remove legacy Ingress manifests entirely once their logic is represented by a route block.
- Run `kustomize cfg fmt` inside the namespace folder after each namespace migration to avoid toolchain drift.

## Phase 1 – Stand-alone Ingress Manifests
Focus first on directories that contain discrete `*ingress*.yaml` files (see [Ingress File Index](indexes/ingress-index.md)). This phase establishes the migration pattern before tackling HelmRelease-managed ingress blocks.

| Order | Namespace | Files / Apps | Considerations |
| --- | --- | --- | --- |
| 1 | entertainment | `pasta/app/ingress.yaml` alongside `pasta/app/helmrelease.yaml` | Simple HTTP ingress mapped to `pasta` Service; convert HelmRelease to include `values.route` and delete `ingress.yaml`. |
| 2 | flux-system | `webhooks/app/github/ingress.yaml` | Webhook receiver must remain compatible with GitHub IPs; ensure `parentRefs` point at internal gateway and preserve path routing. |
| 3 | observability | `grafana/app/tailscale-ingress.yaml` | Uses `tailscale` ingress class today; replicate hostnames (`grafana`) and any TLS expectations via Envoy route + parentRef to Tailscale listener (if available) or internal gateway. |
| 4 | network | `external-services/app/{proxmox,truenas,unifi,voron}.yaml` | Each file bundles Service + EndpointSlice + probable Ingress; once inspected, move host exposure into a tenant HelmRelease (or lightweight chart) so routes can exist within Helm context. |
| 5 | rook-ceph | `rook-ceph/cluster/objectstore-ingress.yaml` | Integrate objectstore exposure into the rook-ceph HelmRelease (or adjunct values file) before removing the ingress manifest. |

Each row will be executed sequentially: update HelmRelease with `values.route`, remove the ingress file, run `kustomize cfg fmt`, then `git status` to verify before advancing.

## Phase 2 – HelmRelease-managed Ingress Blocks
After standalone files are gone, iterate through namespaces whose HelmRelease charts expose services via `values.ingress`. The [App Directory Index](indexes/app-directory-index.md) lists every `app` directory; namespaces with multiple HTTP apps should be converted in the following order to minimize blast radius:

1. **downloads** – Apps: `autobrr`, `bazarr`, `dashbrr`, `flaresolverr`, `kapowarr`, `metube`, `prowlarr`, `qbittorrent`, `radarr`, `radarr-uhd`, `readarr`, `recyclarr`, `sabnzbd`, `sonarr`, `sonarr-foreign`, `sonarr-uhd`, `unpackerr`, `whisparr`. Many already have Tailscale + homepage annotations; convert each HelmRelease’s `values.ingress` block into `values.route` mirroring the Sonarr example.
2. **entertainment** – Apps: `audiobookshelf`, `calibre-web`, `fileflows`, `jellyfin`, `kavita`, `overseerr`, `peertube`, `plex` (and sub-apps), `stash`, `tautulli`, `wizarr`. Handle namespace after `downloads` to reuse patterns for media services.
3. **home / home-automation** – Apps (per [index](indexes/app-directory-index.md)): `atuin`, `bookstack`, `filebrowser`, `homepage`, `linkwarden`, `manyfold`, `paperless` (+ sub apps), `searxng`, `smtp-relay`, `thelounge`, `home-assistant`, `n8n`, `teslamate`. Many rely on TLS + auth integrations; ensure Envoy routes honor existing annotations (homepage widgets, OAuth, etc.).
4. **observability** (remaining apps), **network** (controllers like oauth2-proxy), **cortex**, **security**, **database**, **plane**, **storage**, **volsync-system**, **home** sub-apps, etc. Continue namespace-by-namespace using the same flow: inspect `helmrelease.yaml` for `ingress`, replace with `route`, verify services/annotations, then format.

For each namespace in this phase:
- Inspect every HelmRelease listed in the index for `values.ingress` or similar fields.
- Port hostnames, TLS secrets, annotations, and backend service references into a `values.route` block that mirrors the reference document.
- Remove the old `values.ingress` stanza entirely to prevent duplicate exposure.
- Re-run `kustomize cfg fmt` within the namespace directory and re-`git status` before moving on.

## Operational Checklist Per Namespace
1. Ensure working tree is clean; create/switch to `envoy-route-migration` before editing the first namespace.
2. Copy or template the route structure from [route-reference.md](route-reference.md), adjusting `hostnames`, `parentRefs`, and `backendRefs` as needed.
3. Delete or comment out (then remove) legacy Ingress manifests/blocks once the route is present.
4. Execute `kustomize cfg fmt <namespace path>` to normalize YAML.
5. Record notes on edge cases (custom annotations, TLS secrets, non-HTTP protocols) to feed into subsequent namespaces.
6. Commit namespace-specific changes (if desired) or keep staged until final review, but never mix multiple namespaces in a single change set.

Following this plan keeps the migration organized, auditable, and aligned with the Envoy Gateway model demonstrated by the Sonarr example.
