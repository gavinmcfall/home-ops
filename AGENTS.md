# Repository Guidelines

## Project Structure & Module Organization
- `kubernetes/` holds manifests; apps live in `kubernetes/apps/<namespace>/<app>` with `ks.yaml` and an `app/` folder for Helm, secrets, and kustomizations.
- `kubernetes/flux/` carries Flux config, repositories, and `vars/` for shared settings and SOPS-wrapped secrets.
- `bootstrap/` stores Makejinja templates rendered by `task configure`; treat it as source for generated manifests.
- `.taskfiles/` extends the root `Taskfile.yaml` with automation modules; `scripts/` keeps helper tooling such as `kubeconform.sh`.

## Build, Test, and Development Commands
- `direnv allow .` loads the environment defined in `.envrc`.
- `task workstation:venv` provisions the Python virtualenv used by Makejinja.
- `task init` seeds `config.yaml`; run `task configure` to render manifests and rewrap secrets.
- `task kubernetes:kubeconform` mirrors the CI validation locally.
- `task flux:apply path=home/bookstack` builds a single app with Flux before deploying.

## Coding Style & Naming Conventions
- Formatting is governed by `.editorconfig` (2-space indent, LF) and `.prettierrc` (no tabs); shell and Python scripts use 4 spaces.
- Keep directories lowercase-hyphenated and align manifests under `app/` folders with `kustomization.yaml`, `helmrelease.yaml`, and `externalsecret.yaml` where applicable.
- Default workloads to the `bjw-s/app-template` Helm chart; use vendor charts only when they stay minimally opinionated and align with shared values.
- Shared settings belong in `kubernetes/flux/vars/*.yaml`; encrypted files must end in `.sops.yaml`.
- Scripts should remain POSIX-friendly bash and start with `#!/usr/bin/env bash`.
- Pin images as `<tag>@<digest>`: `crane ls ghcr.io/home-operations/sonarr` → `4.0.15`; `crane digest ghcr.io/home-operations/sonarr:4.0.15` → `sha256:ca6c735014bdfb04ce043bf1323a068ab1d1228eea5bab8305ca0722df7baf78`.

## Testing Guidelines
- Run `task kubernetes:kubeconform` before PRs; CI enforces the same check.
- For Helm edits, dry-run with `flux diff kustomization <name> --path kubernetes/apps/<namespace>/<app>` to inspect drift.
- After templates change, rerun `task configure`, review the diff, then `task sops:encrypt`.

## Commit & Pull Request Guidelines
- Use conventional commits like `chore(bookstack): enable oidc`; keep type lowercase and scope specific.
- Always branch from `main` and open a PR; never push directly (Codex included).
- Group related manifest changes per commit; avoid mixing secret re-encrypts with logic updates.
- PRs must list impacted apps, link issues, and attach `flux diff` or UI screenshots.
- Include kubeconform or automation output for reviewers.

## Secrets & Configuration Tips
- Guard `age.key` and `kubeconfig`; rotations stay manual—do not regenerate Age or shared secrets.
- Keep `.envrc`/`config.yaml` edits uncommitted—promote shared values via `bootstrap/templates`.
- App-specific secrets live in each `externalsecret.yaml`; only cluster env vars belong in Flux `vars/`; leave Age and other root secrets untouched.
