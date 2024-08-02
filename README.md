<div align="center">

# Kubernetes Nerdz

<img src="https://raw.githubusercontent.com/gavinmcfall/home-ops/main/docs/src/assets/logo.png" align="center" width="144px" height="144px"/>

### My Home Operations Repository :octocat:

_... managed with Flux, Renovate, Swearing and GitHub Actions_ 🤖

</div>

<div align="center">

[![Discord](https://img.shields.io/discord/673534664354430999?style=for-the-badge&label&logo=discord&logoColor=white&color=blue)](https://discord.gg/home-operations)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dkubernetes_version&style=for-the-badge&logo=kubernetes&logoColor=white&color=blue&label=%20)](https://www.talos.dev/)&nbsp;&nbsp;
[![Renovate](https://img.shields.io/github/actions/workflow/status/gavinmcfall/home-ops/renovate.yaml?branch=main&label=&logo=renovatebot&style=for-the-badge&color=blue)](https://github.com/gavinmcfall/home-ops/actions/workflows/renovate.yaml)

</div>

<div align="center">

[![Home-Internet](https://img.shields.io/uptimerobot/status/m796131834-31972b9c59792f91867b7e32?color=brightgreeen&label=Home%20Internet&style=for-the-badge&logo=ubiquiti&logoColor=white)](https://status.nerdz.cloud)&nbsp;&nbsp;
[![Status-Page](https://img.shields.io/uptimerobot/status/m796131761-b1397cce0713b97ac72919e8?color=brightgreeen&label=Status%20Page&style=for-the-badge&logo=statuspage&logoColor=white)](https://status.nerdz.cloud)&nbsp;&nbsp;
[![Alertmanager](https://img.shields.io/uptimerobot/status/m796147470-2b0eda86fc73e344c858b2ac?color=brightgreeen&label=Alertmanager&style=for-the-badge&logo=prometheus&logoColor=white)](https://status.nerdz.cloud)

</div>

<div align="center">

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo/)&nbsp;&nbsp;
[![Power-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.nerdz.cloud%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_power_usage&style=flat-square&label=Power)](https://github.com/kashalls/kromgo/)

</div>

## 📖 Overview

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Kubernetes](https://kubernetes.io/), [TalosCTL](https://www.talos.dev/v1.7/learn-more/talosctl/), [k9s](https://k9scli.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate), and [GitHub Actions](https://github.com/features/actions).

## ⛵ Kubernetes

If you want to try and follow along with how I built my cluster and with some of the practices I use please check out the amazing template here:

[![Flux Cluster Template](https://img.shields.io/badge/Cluster%20Template-1f6feb?style=for-the-badge)](https://github.com/onedr0p/cluster-template)
[![Flux Cluster Template Stars](https://img.shields.io/github/stars/onedr0p/cluster-template?style=for-the-badge&color=1f6feb)](https://github.com/onedr0p/cluster-template)

### Core Components

- [actions-runner-controller](https://github.com/actions/actions-runner-controller): Self-hosted Github runners.
- [cert-manager](https://github.com/cert-manager/cert-manager): Creates SSL certificates for services in my cluster.
- [cilium](https://github.com/cilium/cilium): Internal Kubernetes container networking interface.
- [cloudflared](https://github.com/cloudflare/cloudflared): Enables Cloudflare secure access to certain ingresses.
- [external-dns](https://github.com/kubernetes-sigs/external-dns): Automatically syncs ingress DNS records to a DNS provider.
- [external-secrets](https://github.com/external-secrets/external-secrets): Managed Kubernetes secrets using [1Password Connect](https://github.com/1Password/connect).
- [ingress-nginx](https://github.com/kubernetes/ingress-nginx): Kubernetes ingress controller using NGINX as a reverse proxy and load balancer.
- [rook](https://github.com/rook/rook): Distributed block storage for peristent storage.
- [sops](https://github.com/getsops/sops): Managed secrets for Kubernetes and Terraform which are commited to Git.
- [volsync](https://github.com/backube/volsync): Backup and recovery of persistent volume claims.

### Installation

My cluster is [Talos](https://www.talos.dev/) provisioned baremetal on [Minisform MS-01 12900H's](https://store.minisforum.com/products/minisforum-ms-01) utilizing [Thunderbolt Ring Networking](https://gist.github.com/gavinmcfall/ea6cb1233d3a300e9f44caf65a32d519) for [Rook Ceph](https://rook.io/)

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches the cluster in my [kubernetes](./kubernetes/) folder (see Directories below) and makes the changes to my clusters based on the state of my Git repository.

The way Flux works for me here is it will recursively search the `kubernetes/${cluster}/apps` folder until it finds the most top level `kustomization.yaml` per directory and then apply all the resources listed in it. That aforementioned `kustomization.yaml` will generally only have a namespace resource and one or many Flux kustomizations (`ks.yaml`). Under the control of those Flux kustomizations there will be a `HelmRelease` or other resources related to the application which will be applied.

[Renovate](https://github.com/renovatebot/renovate) watches my **entire** repository looking for dependency updates, when they are found a PR is automatically created. When some PRs are merged Flux applies the changes to my cluster.

### Directories

This Git repository contains the following directories under [Kubernetes](./kubernetes/).

```sh
📁 kubernetes
├── 📁 main            # main cluster
│   ├── 📁 apps           # applications
│   ├── 📁 bootstrap      # bootstrap procedures
│   ├── 📁 flux           # core flux configuration
│   └── 📁 templates      # re-useable components
```

### Infrastructure

This is a high level diagram of how my kubernetes infrastructure is setup
<img src="https://raw.githubusercontent.com/gavinmcfall/home-ops/main/docs/src/assets/Nerdz_Infrastructure_v1.png" align="center"/>

### Hardware

| Device                  | Count | OS Disk Size              | Ram   | Operating System | Purpose                                   |
| ----------------------- | ----- | ------------------------- | ----- | ---------------- | ----------------------------------------- |
| Dell Poweredge R730     | 1     | 2x 2TB Raid1 ZFS          | 128GB | Proxmox          | Virtualization Host                       |
| Minisform MS-01         | 3     | 1x 1TB M.2 + 1x1.98TB U.2 | 96GB  | TalosIS          | Kubernetes Nodes                          |
| Unifi Dream Machine Pro | 1     | -                         | -     | -                | Router / FW DHCP Main Lan                 |
| Unifi US 24 250w PoE    | 1     | -                         | -     | -                | PoE for APs etc (1Gbe)                    |
| Unifi US 48 G1          | 1     | -                         | -     | -                | Primary Switch (1Gbe)                     |
| Unifi U6 Lite           | 3     | -                         | -     | -                | Wirless Access Points (PoE)               |
| Eaton 5s 850 (510w)     | 1     | -                         | -     | -                | UPS for Servers                           |
| PiKVM 4 Plus            | 1     | -                         | -     | -                | IP KVM Interface                          |
| Ezcoo EZ-SW41HA-KVMU3P  | 1     | -                         | -     | -                | KVM Switch                                |
| Woieyeks HDMI Adapter   | 4     | -                         | -     | -                | 4K HDMI EDID Emulator Passthrough Adapter |

### Virtual Machines

| Device         | Count | OS Disk Size | Data Disk Size                                                | CPU | RAM  | Operating System    | Purpose                              |
| -------------- | ----- | ------------ | ------------------------------------------------------------- | --- | ---- | ------------------- | ------------------------------------ |
| Stormwind      | 1     | 40GB         | -                                                             | 02c | 02GB | Windows Server 2022 | DNS / DHCP                           |
| Citadel        | 1     | 32GB         | 2x 1.98TB U.2 SLOG, 1x 1.98TB U.2 Cache, 3x 22TB Disks ZFS X1 | 04c | 02GB | Windows Server 2022 | TrueNas Scale                        |
| rclone-proxmox | 1     | 08GB         | -                                                             | 01c | 01GB | Ubuntu (lxc)        | Sync Proxmox backups to Backblaze B2 |

## 🤝 Gratitude and Thanks

Thanks to all the people who donate their time in the [Home Operations](https://discord.gg/home-operations) and [TechnoTim](https://l.technotim.live/discord) Discord Communities for all of their support

---

## 📜 Changelog

See my _awful_ [commit history](https://github.com/gavinmcfall/home-ops/commits/main)

---

## 🔏 License

See [LICENSE](./LICENSE)
