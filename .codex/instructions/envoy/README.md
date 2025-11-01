# Envoy Gateway Migration Plan

This guide outlines the phased approach for moving the cluster from ingress-nginx to Gateway API + Envoy Gateway.

> **IaC-only reminder:** Every step is meant to be performed by editing the Git repo and letting Flux reconcile. Use kubectl exclusively for validation/observation.

- [`01-foundation.md`](./01-foundation.md) – install Envoy Gateway basics (GatewayClass, EnvoyProxy, Gateways).
- [`02-feature-parity.md`](./02-feature-parity.md) – map existing ingress behaviours to Envoy equivalents.
- [`03-route-migration.md`](./03-route-migration.md) – per-app route conversion and testing strategy.
- [`04-cutover-and-cleanup.md`](./04-cutover-and-cleanup.md) – traffic switch, monitoring, and decommissioning nginx.

Follow the documents sequentially; each section contains checklists and notes on potential pitfalls.
