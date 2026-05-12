# Infrastructure Roadmap

12-month plan for home infrastructure redundancy, monitoring, and upgrades.
Triggered May 2026 by a fibre cut taking the house offline — exposed how
brittle the single-point-of-failure dependencies are across power and internet.

**Status**: Planning phase. No procurement decisions finalised.

---

## Scope

Five workstreams. Power and the electrification questions are tightly coupled
because they jointly determine the solar payback model.

1. **Power redundancy** — Battery backup (Powerwall, BYD, or portable system),
   possibly solar. Eliminate per-device UPSes.
2. **Energy electrification** — Replace gas califont with heat pump water
   heater (HPWH), replace gas cooktop with induction. Goal: disconnect gas
   reticulation entirely once the last gas appliance is gone.
3. **Internet redundancy** — 5G failover via UniFi U5G Max Outdoor + One NZ
   SIM, terminated into UDM Pro WAN2.
4. **Networking upgrades** — TBD scope. Likely candidates: more deliberate
   VLAN segmentation, additional PoE budget, possible 10GbE between rack
   and key APs.
5. **Compute upgrades** — TBD scope. Likely candidates: cluster node
   additions, NAS/storage expansion, dedicated game server hardware.

---

## Constraints

- **Move horizon**: 3–4 years. Anything installed needs to either pay back
  within that window, or add to sale price, or be transportable.
- **Single-phase** electrical supply (TBC at switchboard inspection).
- **No current desire to install solar unless payback proves out** — driven
  by the move horizon.
- **Gas currently in use** for water heating (califont) and cooking.

---

## Current state (May 2026)

| Layer | Today |
|---|---|
| ISP | Bigpipe fibre (IPv4 only, no IPv6 since 2018) |
| Edge | UDM Pro, all-UniFi switches/APs (US-24-250W, US-48, U6 Lite ×3) |
| Cluster | 3-node MS-01 Talos (stanton-01/02/03), Thunderbolt ring, Cilium + BGP |
| Storage | Rook-Ceph on cluster + Dell R730 TrueNAS for NFS/backup |
| Power | Grid only, 2× Eaton 5S 850 UPSes |
| Gas | Reticulated — califont + cooktop |
| Smart meter | Installed ~Nov 2025, retailer = Contact Energy |
| Monitoring | Prometheus, Grafana, Home Assistant, TeslaMate, NUT |

---

## Phase plan (rough)

### Phase 1 — Internet failover

Get 5G failover online so the next fibre cut doesn't take the house offline.

- [ ] Confirm U5G-Max-Outdoor availability with GoWifi NZ (preferred) or PB Tech
- [ ] Order U5G-Max-Outdoor (~NZD $934 from PB Tech, equivalent from GoWifi)
- [ ] Acquire One NZ business/M2M SIM (data-only plan)
- [ ] Mount U5G-Max-Outdoor on roof, run Cat6 to rack
- [ ] Adopt into UniFi controller, configure WAN2 failover priority
- [ ] Tune WAN failover ping interval (default is sluggish)
- [ ] Set WAN2 traffic policy: failover-only, block bulk traffic (Plex,
      Jellyfin, qBittorrent) from cellular path
- [ ] Test failover: pull WAN1, validate cutover and service continuity

**Risk**: U5G Max Outdoor isn't formally certified for NZ carriers (US only).
Hardware supports all NZ-relevant bands (B1/B3/B7/B28, n78). Validate during
install; fallback is Peplink BR1 Pro 5G + Poynting antenna if it doesn't
attach cleanly.

### Phase 2 — Power monitoring foundation (parallel with Phase 1)

Start collecting data we'll need for battery sizing and solar feasibility.

- [ ] Add `ha-contact-energy` HACS integration to home-ops repo via init
      container → Contact API into HA
      (see [`contact-energy.md`](./contact-energy.md))
- [ ] Verify Contact data flowing into HA Energy Dashboard
- [ ] Pipe HA energy data through to Prometheus → Grafana
- [ ] Switchboard inspection: confirm phase config (single vs 3-phase),
      main breaker rating
- [ ] Roof feasibility: orientation, available m², shading
- [ ] Pull NUT historical data: current UPS load profile, what's protected
      today, typical draw
- [ ] TeslaMate query: home-charging schedule and kWh per session
- [ ] Outage history: NUT events, Northpower outage notifications
- [ ] Gather last 12 months of gas bills

### Phase 3 — Solar + battery feasibility model

The decision gate. Build a model with real data and quotes, then decide
go/no-go on solar + which battery architecture.

- [ ] Site visits + quotes from 2–3 NZ solar installers
- [ ] Quote from HPWH installer for califont replacement
- [ ] Quote for induction cooktop install
- [ ] TOU tariff comparison: Octopus NZ vs Contact Hour Power vs Electric
      Kiwi vs Flick — does switching retailer change the maths meaningfully?
- [ ] Build payback model in spreadsheet:
  - Solar generation forecast (installer-provided)
  - Battery sized for self-consumption maximisation
  - Pre + post-electrification consumption forecast
  - 5–10 year payback projection across scenarios
- [ ] **Decision gate**:
  - Payback ≤ 5 years → Phase 4a (full package: solar + battery +
    electrification, fixed install)
  - Payback 5–7 years → judgment call (partial breakeven + sale-price uplift)
  - Payback > 7 years → Phase 4b (portable battery for resilience only,
    electrify only what makes standalone sense)

### Phase 4a — Full package install (if Phase 3 goes "yes solar")

- [ ] Installer selected, contract signed
- [ ] Solar PV install (panels + inverter)
- [ ] Powerwall 3 or BYD HVS install (likely whole-house given solar
      changes self-consumption maths)
- [ ] Califont → HPWH swap
- [ ] Gas cooktop → induction swap
- [ ] Gas reticulation disconnect (kills standing charge)
- [ ] **Bundle CT-clamp monitoring** (Shelly Pro 3EM or similar) into install
- [ ] Commission + grid-tie
- [ ] Retire per-device UPSes incrementally
- [ ] Monitoring integration: Powerwall/inverter data → HA → Prometheus → Grafana

### Phase 4b — Portable backup only (if Phase 3 goes "no solar")

- [ ] Select portable system (EcoFlow Delta Pro Ultra + Smart Home Panel
      most likely)
- [ ] Critical-loads sub-panel install (electrician)
- [ ] System install + commissioning
- [ ] **CT-clamp added at same time** (sparky's already in the board)
- [ ] Retire per-device UPSes incrementally
- [ ] Monitoring integration into HA + Prometheus

### Phase 5 — Networking & compute (months 7–12)

To be scoped. Initial candidates:

- Networking: rack-to-AP backhaul upgrades, additional PoE switch capacity,
  dedicated management VLAN cleanup
- Compute: cluster node additions, NAS/storage tier expansion, possible
  dedicated game server hardware

---

## Open decisions

| # | Decision | Status | Notes |
|---|---|---|---|
| 1 | Solar yes/no | Gated on Phase 3 model | Depends on payback maths after electrification + TOU tariff selected |
| 2 | Battery architecture: whole-house vs critical-loads | Gated on #1 | If solar yes → whole-house likely; if no → critical-loads |
| 3 | Battery product: Powerwall vs BYD vs Sonnen vs EcoFlow Delta Pro Ultra | Gated on #1, #2 | Fixed install if solar; portable if not |
| 4 | Electrify gas appliances | Open, likely yes | HPWH almost certainly worth it standalone; cooktop is preference-driven |
| 5 | 5G modem: U5G Max Outdoor vs Peplink BR1 Pro 5G | Leaning U5G | NZ carrier cert risk; pragmatic plan is buy U5G, fallback to Peplink if it doesn't attach |
| 6 | Stay on Contact Energy or switch retailer | Open | Octopus NZ may give better TOU + buy-back if solar happens |
| 7 | Stay on Bigpipe or switch ISP | Open | Bigpipe = no IPv6, but otherwise fine. 2degrees / Voyager would give IPv6 if that matters |

---

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-11 | Track project in `home-ops` repo as markdown | GitOps fits existing workflow; version controlled |
| 2026-05-11 | Project covers 5 workstreams over ~12 months | Triggered by fibre cut + general infrastructure resilience goals |
| 2026-05-11 | Use `ha-contact-energy` HACS integration for smart meter data | Native HA → Prometheus path; avoids manual CSV workflow. Upstream archived Oct 2024 — pin to commit `16826d2b82efb294e33f48f70647d21f551b6bf1`; underlying Python library still maintained, fallback documented in PR |
| 2026-05-11 | Defer CT-clamp install until battery install | Free incremental scope when sparky is already in switchboard |
| 2026-05-11 | Add electrification (HPWH + induction) as in-scope workstream | Required to make solar payback maths viable; standalone payback also reasonable |
| 2026-05-11 | Solar decision deferred to Phase 3 model | Need real consumption + quote data before committing |

---

## Data to gather

- [ ] Contact Energy: ~6 months of hourly consumption data (via integration in Phase 2)
- [ ] Gas: last 12 months of bills (kWh equivalent + standing charges)
- [ ] Switchboard: phase config, main breaker rating
- [ ] Roof: orientation, dimensions, shading
- [ ] NUT: current protected loads + draw
- [ ] TeslaMate: home charging patterns + monthly kWh
- [ ] One NZ: M2M / business SIM plan options and pricing
- [ ] Lines company: outage history for the area

---

## References

- HA Contact Energy integration: https://github.com/codyc1515/ha-contact-energy
- Contact Energy Python lib: https://pypi.org/project/contact-energy-nz/
- UniFi U5G Max Outdoor (PB Tech NZ): https://www.pbtech.co.nz/product/NETUBI260206/Ubiquiti-UniFi-U5G-Max-Outdoor-5G-Outdoor-Gateway
- UniFi 5G/LTE backup best practices: https://help.ui.com/hc/en-us/articles/29887153953559-UniFi-5G-and-LTE-Backup-Best-Practices
- Peplink BR1 Pro 5G (Powertec NZ, fallback): https://powertec.co.nz/peplink-br1-pro-5g-includes-1-year-primecare/
- Reclaim Energy CO2 HPWH: https://reclaimenergy.com.au/
