# soularr — PHASE 2 (not yet wired into Flux)

soularr bridges **Lidarr** and **slskd**: it reads Lidarr's "wanted" list and searches
Soulseek (via slskd) to fill the gaps automatically.

This directory is **intentionally NOT added** to `kubernetes/apps/downloads/kustomization.yaml`,
because soularr's `config.ini` needs API keys that don't exist until Lidarr and slskd are
deployed and configured. Enable it only after both are up.

## Enable checklist

1. Deploy Lidarr + slskd; complete their first-run setup.
2. Grab API keys:
   - Lidarr: Settings → General → API Key
   - slskd: Options → Security (or generate an API key in slskd config)
3. Create the secret config (SOPS-encrypted, do NOT commit plaintext):
   - Copy `app/config.ini.example` → `app/config.ini`, fill in the two API keys.
   - `kubectl create secret generic soularr-config --from-file=config.ini=app/config.ini --dry-run=client -o yaml > app/secret.sops.yaml`
   - `sops --encrypt --in-place app/secret.sops.yaml`
   - Add `./secret.sops.yaml` to `app/kustomization.yaml` resources.
4. **Pin the image digest** in `app/helmrelease.yaml` (currently a TODO — crane was unavailable when this was scaffolded):
   - `crane digest ghcr.io/mrusse08/soularr:latest` (or the docker.io/mrusse08/soularr equivalent)
5. Add `./soularr/ks.yaml` to `kubernetes/apps/downloads/kustomization.yaml`.
6. Validate (`task kubernetes:kubeconform`), commit, push.

## Notes

- Modelled as a **CronJob** (batch worker), not a long-running Deployment — soularr does a
  search pass then exits. Default schedule below is every 6h; tune to taste.
- In-cluster service DNS: Lidarr = `http://lidarr.downloads`, slskd = `http://slskd.downloads`.
- No one in the surveyed friend-repos runs soularr; this is our own addition, so treat the
  first deploy as experimental and watch the CronJob logs.
