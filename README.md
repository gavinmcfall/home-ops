<div align="center">

# Kubernetes Nerdz
<img src="https://raw.githubusercontent.com/gavinmcfall/home-ops/main/docs/src/assets/kubernetes.png" align="center" width="144px" height="144px"/>

### My Home Operations Repository :octocat:
_... managed with Flux, Renovate, Swearing and GitHub Actions_ 🤖

</div>

<div align="center">

[![Discord](https://img.shields.io/discord/673534664354430999?style=for-the-badge&label&logo=discord&logoColor=white&color=blue)](https://discord.gg/home-operations)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fonedr0p%2Fhome-ops%2Fmain%2Fkubernetes%2Fmain%2Fapps%2Ftools%2Fsystem-upgrade-controller%2Fplans%2Fserver.yaml&query=%24.spec.version&style=for-the-badge&logo=kubernetes&logoColor=white&label=%20)](https://k3s.io/)&nbsp;&nbsp;
[![Renovate](https://img.shields.io/github/actions/workflow/status/gavinmcfall/home-ops/renovate.yaml?branch=main&label=&logo=renovatebot&style=for-the-badge&color=blue)](https://github.com/gavinmcfall/home-ops/actions/workflows/renovate.yaml)

</div>

<div align="center">

[![Home-Internet](https://img.shields.io/uptimerobot/status/m796131834-31972b9c59792f91867b7e32?color=brightgreeen&label=Home%20Internet&style=for-the-badge&logo=ubiquiti&logoColor=white)](https://status.nerdz.cloud)&nbsp;&nbsp;
[![Status-Page](https://img.shields.io/uptimerobot/status/m796131761-b1397cce0713b97ac72919e8?color=brightgreeen&label=Status%20Page&style=for-the-badge&logo=statuspage&logoColor=white)](https://status.nerdz.cloud)&nbsp;&nbsp;
[![Alertmanager](https://img.shields.io/endpoint?url=https%3A%2F%2Fhealthchecks.io%2Fbadge%2F64bb3a96-bf19-4f71-8433-bcca27%2FjhXEym_b-2%2Falertmanager.shields?color=brightgreeen&label=Alertmanager&style=for-the-badge&logo=prometheus&logoColor=white)](https://status.nerdz.cloud)

</div>

## 📖 Overview

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Ansible](https://www.ansible.com/), [Terraform](https://www.terraform.io/), [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate), and [GitHub Actions](https://github.com/features/actions).

## ⛵ Kubernetes

There is a template over at [onedr0p/flux-cluster-template](https://github.com/onedr0p/flux-cluster-template) if you want to try and follow along with some of the practices I use here.

### Installation

My cluster is [k3s](https://k3s.io/) provisioned inside Proxox on VMs running Debian using the [Ansible](https://www.ansible.com/) galaxy role [ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s). This is a semi-hyper-converged cluster.

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches the clusters in my [kubernetes](./kubernetes/) folder (see Directories below) and makes the changes to my clusters based on the state of my Git repository.

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

| Device                      | Count | OS Disk Size      | Ram   | Operating System | Purpose                     |
|-----------------------------|-------|-------------------|-------|------------------|-----------------------------|
| Dell Poweredge R730         | 1     | 2x 2TB Raid1 ZFS  | 128GB | Proxmox          | Virtualization Host         |
| Unifi Dream Machine Pro     | 1     | -                 | -     |                  | Router / FW DHCP Main Lan   |
| Unifi US 24 250w PoE        | 1     | -                 | -     |                  | PoE for APs etc (1Gbe)      |
| Unifi US 48 G1              | 1     | -                 | -     |                  | Primary Switch (1Gbe)       |
| Unifi U6 Lite               | 3     | -                 | -     |                  | Wirless Access Points (PoE) |

### Virtual Machines

| Device                      | Count | OS Disk Size    | Data Disk Size             | CPU | Ram  | Operating System    | Purpose                              |
|-----------------------------|-------|-----------------|----------------------------|-----|------|---------------------|--------------------------------------|
| Arccorp, Crusader, Hurston  | 3     | 250GB SSD: VT-d | 2TB SSD: VT-d (rook-ceph)  | 12c | 24GB | Debian              | Kubernetes Masters                   |
| Stormwind                   | 1     | 40GB            | -                          | 02c | 02GB | Windows Server 2022 | DNS / DHCP                           |
| rclone-proxmox              | 1     | 08GB            | -                          | 01c | 01GB | Ubuntu (lxc)        | Sync Proxmox backups to Backblaze B2 |

## 🤝 Gratitude and Thanks

Thanks to all the people who donate their time in the [Home Operations](https://discord.gg/home-operations) and [TechnoTim](https://l.technotim.live/discord) Discord Communities for all of their support

---

## 📜 Changelog

See my _awful_ [commit history](https://github.com/gavinmcfall/home-ops/commits/main)

---

## 🔏 License

See [LICENSE](./LICENSE)
