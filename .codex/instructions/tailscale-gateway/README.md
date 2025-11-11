# Tailscale Gateway Workspace

This folder captures the working notes for removing legacy Tailscale ingresses and wiring the tailnet into Envoy Gateway + HTTPRoutes.

- `network-index.md` – inventory of everything under `kubernetes/apps/network` with current exposure details.
- `tailscale-scope.md` – workloads that currently rely on the `tailscale` ingress class and what they need from the new stack.
- `design.md` – evaluation of integration options plus the recommended architecture (Envoy Gateway + Tailscale service exposure).
- `tasks.md` – concrete next actions, prerequisites, and blockers to track progress.

Start with the network index to understand today’s moving pieces, review the scope list to gauge blast radius, then follow the design + tasks documents while implementing changes.
