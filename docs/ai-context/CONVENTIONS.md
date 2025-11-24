# Repository Conventions

## Project Structure & Module Organization
This repo is declarative-first: manifests live in `kubernetes/`, with each app under `kubernetes/apps/<namespace>/<app>` containing `ks.yaml` plus an `app/` folder for Helm charts, secrets, and kustomizations. Flux configuration resides in `kubernetes/flux/`, with shared values and SOPS-wrapped secrets inside `kubernetes/flux/vars/`. Templates in `bootstrap/` are rendered via Makejinja and treated as source; never edit generated output directly. Helper scripts stay in `scripts/`, and additional Task modules live under `.taskfiles/` to extend the root `Taskfile.yaml`.

## Build, Test, and Development Commands
Run `direnv allow .` once to load environment variables from `.envrc`. Use `task workstation:venv` to provision the Python virtualenv required by Makejinja tooling. `task init` seeds `config.yaml`; follow with `task configure` after editing templates so manifests regenerate and secrets rewrap. Validate manifests locally with `task kubernetes:kubeconform`, mirroring CI. Target a single deployment using `task flux:apply path=home/bookstack` (adjust the path per app) before reconciling in-cluster.

## Coding Style & Naming Conventions
Honor `.editorconfig` for 2-space indentation (4 spaces in bash/Python) and LF endings; Prettier enforces no tabs. Keep directory names lowercase-hyphenated. Default workloads to the `bjw-s/app-template` Helm chart, only deviating for minimal vendor charts. Enforce manifest triads—`kustomization.yaml`, `helmrelease.yaml`, `externalsecret.yaml`—inside each app folder. Pin container images as `<tag>@<digest>` using `crane ls` and `crane digest`.

## Testing Guidelines
Treat kubeconform as the baseline test: run `task kubernetes:kubeconform` before opening a PR. For Helm changes, execute `flux diff kustomization <name> --path kubernetes/apps/<namespace>/<app>` to inspect drift. After modifying Makejinja templates, rerun `task configure`, review the git diff, and finish with `task sops:encrypt` when secrets change.

## Commit & Pull Request Guidelines
Follow conventional commits such as `chore(bookstack): enable oidc`, keeping types lowercase and scopes app-specific. Branch from `main`, group related manifest changes per commit, and avoid mixing secret re-encrypts with logic updates. PRs should list impacted apps, link issues, include `flux diff` evidence or screenshots, and attach kubeconform output. Never push directly to `main`; rely on reviewed PRs.

## Security & Configuration Tips
Protect `age.key`, `kubeconfig`, and other root secrets; rotations remain manual. Do not commit `.envrc` or `config.yaml`—surface shared configuration through `bootstrap/templates`. App-specific credentials belong in each `externalsecret.yaml`, while cluster-wide settings sit in Flux `vars/`. Scripts must stay POSIX-friendly and start with `#!/usr/bin/env bash`.
