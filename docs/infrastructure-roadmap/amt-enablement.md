# Intel AMT / vPro enablement — stantons

Enable Intel Active Management Technology on stanton-0[1-3] for genuine
out-of-band management (remote KVM, remote BIOS, remote power, SOL).

Part of the [infrastructure roadmap](./README.md) — sits alongside the
JetKVM-based out-of-band path. AMT is the firmware-native fallback if the
JetKVM hardware ever fails or gets repurposed.

## ⚠️ Before starting

**This is NOT a per-node power-telemetry play.** Researched 2026-05-17 across
the Virtualization Howto MS-01 write-up, the Space Terran step-by-step,
the pcfe.net sensor blog, and the Intel AMT sensor spec: the MS-01 firmware
does not appear to expose `CIM_NumericSensor` instances with `BaseUnits=7`
(watts). Per-node wattage is being solved separately via the JetKVM DC
Power Control extension (see the observability audit and the JetKVM
exporter plan).

This plan is **purely for ops capability**: KVM/power/BIOS access when SSH
is dead. Talos has no SSH, so AMT is materially useful for recovery
scenarios (stuck Talos upgrade, corrupted boot, network misconfig, etc).

## Why

Recovery is currently:

- TrueNAS Citadel and the JetKVMs cover remote KVM + remote power for the
  stantons. But that's two extra physical layers — if Citadel is down,
  JetKVMs can be unreachable; if a JetKVM has its own issue, no fallback.
- AMT is firmware-level — survives almost everything short of mainboard
  failure.
- Provides a "the JetKVM died and I'm not home" recovery path.

Secondary value:

- Remote BIOS access (change boot order, toggle hardware, update without a
  monitor) is currently a "go physically touch the rack" task.
- SOL pre-OS console — useful for early Talos boot diagnosis.

## Constraints

- AMT binds to the **i226-LM** port (leftmost of the two 2.5G RJ45 ports),
  NOT the X710 10G. Cabling layout must include the i226-LM in the cluster
  LAN.
- Known gotcha (multiple Proxmox forum reports): the i226-LM can intercept
  DHCP Offer packets and mistake them for AMT telegrams. Need to plan
  network design so this doesn't conflict.
- BIOS visit per node — drain workload first, sequential not parallel.
- Static IPs required for AMT (the Space Terran guide warns DHCP "produced
  mixed results"). That's 3 new IPs on the 10.90.3.0/24 management subnet.

## Approach

Two-phase: provision one node as a probe, then roll to the rest.

### Phase 1: Probe (stanton-03 — least disruptive)

1. Drain stanton-03 via `kubectl drain` + Ceph pre-flight.
2. Reboot, `DEL` at boot.
3. BIOS Setup → set BIOS admin password (prerequisite for MEBx visibility).
4. MEBx submenu → default password `admin` → set complex password
   (uppercase + special + numbers required by firmware).
5. `Intel(R) AMT Configuration` → enable.
6. `Network Setup`:
   - "Network Access State" = `Active Network`
   - FQDN setting = `Dedicated`
7. `TCP/IP Settings` → `Wired LAN IPV4 Configuration`:
   - Disable DHCP
   - Static IP `10.90.3.103` reserved range +offset (e.g. `10.90.3.203`)
   - Netmask `/24`, gateway `10.90.3.254`
8. Disable ASPM in both SA-PCIE and PCH-PCIE settings (required for AMT
   stability per Space Terran guide).
9. Save + exit, reboot.
10. Verify ports 16992/16993 are reachable:
    ```bash
    nc -zv -w2 10.90.3.203 16992 16993
    ```
11. Sensor enumeration (confirms our assumption is correct):
    ```bash
    wsman enumerate http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_NumericSensor \
      -h 10.90.3.203 -P 16992 -u admin -p '<mebx-password>' \
      | grep -E 'ElementName|SensorType|CurrentReading|BaseUnits'
    ```
    Expected: temperature + fan sensors only, no `BaseUnits=7` (watts).
    If watts appear, this becomes a metrics play too — revisit the plan.
12. Smoke test from MeshCommander or MeshCentral: connect KVM, send a
    power-reset, confirm BIOS access works.
13. Uncordon stanton-03.

### Phase 2: Roll to stanton-01 and stanton-02

Repeat steps 1-12 with appropriate static IPs. Suggested mapping:

| Node | OS IP | AMT IP |
|---|---|---|
| stanton-01 | 10.90.3.101 | 10.90.3.201 |
| stanton-02 | 10.90.3.102 | 10.90.3.202 |
| stanton-03 | 10.90.3.103 | 10.90.3.203 |

### Phase 3: Wire up management surface

Pick one (not exclusive):

- **MeshCommander** (desktop, one-shot installs). Lightweight, no server.
- **MeshCentral** (containerised, accessible via Cloudflare tunnel /
  Tailscale). Centralised view of all 3 nodes, audit logs, scriptable.

If choosing MeshCentral, it lives in `home-automation` or `network`
namespace, gets the standard internal-gateway routing pattern, secret in
1Password for the AMT admin passwords.

## Changes

This plan is **infrastructure work, not repo work** — no Kubernetes
manifests change. The only repo artefacts are:

1. This document (already created).
2. Updated `~/home-ops/docs/ai-context/NETWORKING.md` with the 3 AMT IPs
   once provisioned (so future-Claude/Gavin knows what's listening on
   `10.90.3.20X:16992`).
3. UDM Pro reservation: 3 entries in the DHCP scope to keep the AMT IP
   range out of the DHCP pool (e.g. exclude `10.90.3.200-210`).
4. (Optional) MeshCentral HelmRelease if Phase 3 picks that path.

## Fallback plan

If AMT provisioning fails on any stanton (firmware bug, ME unresponsive),
the existing JetKVM coverage stays as the OOB path. No regression — AMT
is purely additive.

If the i226-LM DHCP-eating gotcha manifests (LAN devices unable to get
DHCP leases on the i226-LM port after AMT enable), worst case is to
disable AMT on that node and stick with JetKVM, OR reconfigure to use
the i226-LM exclusively for AMT and route OS traffic over the X710.

## When to do this

**Not urgent.** The JetKVM coverage is the primary OOB path. This plan
exists as a documented "second redundancy layer" follow-up — schedule
during a non-critical window with no concurrent dependencies (no Ceph
rebalance, no Talos upgrade, no network changes).

Estimated time: 15-20 minutes per node including drain/reboot cycles.
Total: ~1 hour for all three with verification.

## References

- [Step-by-Step Guide: Enabling Intel® vPro™ on Your Minisforum MS-01](https://spaceterran.com/posts/step-by-step-guide-enabling-intel-vpro-on-your-minisforum-ms-01-bios/) — the MS-01-specific guide that informed the BIOS steps above
- [This Made My Mini PC Home Lab Feel Enterprise Grade: Intel vPro with AMT](https://www.virtualizationhowto.com/2026/02/this-made-my-mini-pc-home-lab-feel-enterprise-grade-intel-vpro-with-amt/) — practical feature inventory
- [Intel AMT Sensors and Sensor Events reference](https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/WordDocuments/sensorsandsensorevents.htm) — what CIM_NumericSensor types AMT spec supports
- [Proxmox forum: i226-V interface DHCP issues on MS-01](https://forum.proxmox.com/threads/minisforum-ms-01-i226-v-interface-low-and-asymmetrical-network-speeds-compared-to-link-level-service.169825/) — the DHCP-eating gotcha
- Local memory: `[[reference-ms01-amt-vs-ipmi]]` and the observability audit `docs/observability-audit-2026-05.md`
