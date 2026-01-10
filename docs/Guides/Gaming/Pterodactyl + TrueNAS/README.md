# Pterodactyl Game Server Management: Panel + Wings on TrueNAS

Deploy Pterodactyl Panel on Kubernetes and Wings daemon on TrueNAS for self-hosted game server management.

---

## What You'll Learn

By the end of this guide, you will:

- Deploy Pterodactyl Panel on Kubernetes using GitOps
- Configure database (MariaDB) and cache (Dragonfly/Redis) backends
- Set up S3 backups via MinIO
- Deploy Wings daemon on TrueNAS using Docker
- Configure networking (DNS, port forwards) for external game server access
- Connect Wings to the Panel and create allocations

---

## Architecture Overview

```
                                    Internet
                                        │
                                        ▼
                              ┌─────────────────┐
                              │  UniFi Gateway  │
                              │   Port Forward  │
                              └────────┬────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            │                          │                          │
            ▼                          ▼                          ▼
    ┌───────────────┐         ┌───────────────┐         ┌───────────────┐
    │ Pterodactyl   │         │    Wings      │         │ Game Servers  │
    │    Panel      │◄───────►│  (TrueNAS)    │◄───────►│   (Docker)    │
    │  (Kubernetes) │         │   Port 8443   │         │ Ports 25565+  │
    └───────┬───────┘         └───────────────┘         └───────────────┘
            │
    ┌───────┴───────┐
    │               │
    ▼               ▼
┌────────┐    ┌──────────┐
│MariaDB │    │Dragonfly │
│  (DB)  │    │ (Cache)  │
└────────┘    └──────────┘
```

| Component | Location | Purpose |
|-----------|----------|---------|
| Pterodactyl Panel | Kubernetes | Web UI for managing game servers |
| Wings | TrueNAS (Docker) | Daemon that runs game server containers |
| MariaDB | Kubernetes | Database backend |
| Dragonfly | Kubernetes | Redis-compatible cache/session store |
| MinIO | TrueNAS | S3 backup storage |

---

## Prerequisites

Before starting, ensure you have:

- [ ] A working Kubernetes cluster with Flux GitOps
- [ ] MariaDB deployed in the `database` namespace
- [ ] Dragonfly (or Redis) deployed in the `database` namespace
- [ ] MinIO with a bucket for game server backups
- [ ] TrueNAS with Docker support
- [ ] A domain you control with DNS management (Cloudflare)
- [ ] UniFi or similar router for port forwarding

---

## Guide Structure

This guide is split into three parts:

1. **[Panel Deployment](./01-panel-deployment.md)** — Deploy Pterodactyl Panel on Kubernetes
2. **[Wings Setup](./02-wings-truenas.md)** — Deploy Wings daemon on TrueNAS with Docker
3. **[Eggs and Servers](./03-eggs-and-servers.md)** — Import game eggs and create servers

Start with Part 1, then proceed sequentially.

---

## Quick Reference

| Resource | URL/Value |
|----------|-----------|
| Panel URL | `https://pterodactyl.${SECRET_DOMAIN}` |
| Wings FQDN | `play.${SECRET_DOMAIN}` |
| Wings API Port | 8443 |
| Wings SFTP Port | 2022 |
| Game Ports | 25565-25600 |
| MariaDB Host | `mariadb.database.svc.cluster.local` |
| Dragonfly Host | `dragonfly.database.svc.cluster.local` |

---

## Troubleshooting Quick Links

- [Panel won't start](#panel-troubleshooting) — Database, Redis, or config issues
- [Wings won't connect](#wings-troubleshooting) — SSL certificates, DNS, or firewall
- [Game servers unreachable](#networking-troubleshooting) — Port forwarding or allocation issues
