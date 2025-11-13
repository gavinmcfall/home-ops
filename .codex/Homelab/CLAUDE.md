# Homelab Guidance for Claude/Codex

This folder holds the templates Claude or Codex should follow before touching the rest of the repository. Keep your answers scoped to what lives directly under `/home/gavin/home-ops`.

## Reading Order
1. Start with `README.md` to learn how the repo is structured, what components it owns, and how tasks are triggered from `.codex/Homelab` tooling.
2. Use `ARCHITECTURE.md` to understand the GitOps workflow (Flux + HelmRelease + Taskfile rendering), the Talos/bootstrap pattern, and the constraints that keep the public repo safe.
3. Consult `CONTRACTS.md` for the promises the repo makes to GitOps consumers (Flux intervals, placeholder handling, signal dashboards).
4. Study `DOMAIN.md` for invariants, state machines, and domain-specific vocabulary such as `${SECRET_DOMAIN}` or ROMM media mounts.
5. Keep `QUESTIONS.md` up to date with unknowns before asking the human to fill gaps.
6. Use `WORKFLOWS.md`, `TOOLS.md`, and `TEMPLATE_GUIDE.md` for the procedural guidance and placeholder substitution rules.

## Safety
- Everything referenced here must exist within `/home/gavin/home-ops`; any path outside (e.g., other repos) is off-limits.
- Replace real hostnames, IPs, or credentials with placeholders such as `${SECRET_DOMAIN}`, `${MEDIA_SERVER}`, or `${KUBE_NAMESPACE}`.
- When in doubt, cite files like `README.md`, `Taskfile.yaml`, or `kubernetes/apps/games/romm/app/helmrelease.yaml` to support statements.
