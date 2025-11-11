# Workloads Using the `tailscale` Ingress Class

22 HelmReleases currently set `values.ingress.tailscale.*` inside this repo. Every one of them will need an alternative once we remove `Ingress` objects entirely. Host patterns below come directly from each chart so we can reproduce them when wiring Envoy + Tailscale services.

| Namespace | App | File | Tailnet Host Template | Notes |
| --- | --- | --- | --- | --- |
| `home-automation` | `teslamate` | `apps/home-automation/teslamate/app/helmrelease.yaml` | `{{ .Release.Name }}` | Also serves `teslamate.${SECRET_DOMAIN}` over LAN. |
| `cortex` | `whisper` | `apps/cortex/whisper/app/helmrelease.yaml` | `whisper` | Explicit `&tailscale-host` anchor; wants short name only. |
| `cortex` | `open-webui` | `apps/cortex/open-webui/app/helmrelease.yaml` | `chat` | Host differs from release name. |
| `downloads` | `autobrr` | `apps/downloads/autobrr/app/helmrelease.yaml` | `{{ .Release.Name }}` | Standard pattern. |
| `downloads` | `bazarr` | `apps/downloads/bazarr/app/helmrelease.yaml` | `{{ .Release.Name }}` | Anchor `&app` reused throughout file. |
| `downloads` | `dashbrr` | `apps/downloads/dashbrr/app/helmrelease.yaml` | `{{ .Release.Name }}` | Both LAN + tailnet share host. |
| `downloads` | `kapowarr` | `apps/downloads/kapowarr/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `metube` | `apps/downloads/metube/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `prowlarr` | `apps/downloads/prowlarr/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `qbittorrent` | `apps/downloads/qbittorrent/app/helmrelease.yaml` | `qb` | Host intentionally shortened; keep alias. |
| `downloads` | `radarr` | `apps/downloads/radarr/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `radarr-uhd` | `apps/downloads/radarr-uhd/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `readarr` | `apps/downloads/readarr/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `sabnzbd` | `apps/downloads/sabnzbd/app/helmrelease.yaml` | `sab` | Differing internal/external hostnames. |
| `downloads` | `sonarr` | `apps/downloads/sonarr/app/helmrelease.yaml` | `{{ .Release.Name }}` | Example HTTPRoute already exists here. |
| `downloads` | `sonarr-foreign` | `apps/downloads/sonarr-foreign/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `sonarr-uhd` | `apps/downloads/sonarr-uhd/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `downloads` | `whisparr` | `apps/downloads/whisparr/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `home` | `filebrowser` | `apps/home/filebrowser/app/helmrelease.yaml` | `{{ .Release.Name }}` |  |
| `home` | `homepage` | `apps/home/homepage/app/helmrelease.yaml` | `{{ .Release.Name }}` | Tailscale ingress that triggered this effort. |
| `home` | `paperless` | `apps/home/paperless/app/helmrelease.yaml` | `{{ .Release.Name }}` | Applies to main Paperless UI. |
| `home` | `paperless-ai` | `apps/home/paperless/paperless-ai/helmrelease.yaml` | `{{ .Release.Name }}` | Shares namespace/app chart but separate release. |

Use this table as the canonical checklist when porting tailnet exposure to the new Envoy-based design. Anything missing here still needs a discovery pass before we can remove the `tailscale` ingress class entirely.
