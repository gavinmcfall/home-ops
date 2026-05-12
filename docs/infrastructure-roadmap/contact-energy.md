# Home Assistant — Contact Energy smart meter integration

Adds the [`ha-contact-energy`](https://github.com/codyc1515/ha-contact-energy)
HACS integration to Home Assistant via an init container, so smart meter data
from Contact Energy flows into HA → Prometheus → Grafana without manual HACS
clicks or CSV exports.

Part of the [infrastructure roadmap](./README.md) **Phase 2: Power monitoring
foundation**.

## ⚠️ Upstream status — read before merging

**The upstream `codyc1515/ha-contact-energy` repository was archived on
8 October 2024 by the original author and is read-only.** The last meaningful
commit is `16826d2b82efb294e33f48f70647d21f551b6bf1` (30 January 2024).

This means:

- ✅ It still works (last community confirmation Sep 2024, and the API surface
  is Contact's own mobile-app API — they maintain it for their own product).
- ✅ The underlying Python library `contact-energy-nz` on PyPI (by
  `tkhadimullin`, a separate author) is still actively maintained and tracks
  API changes.
- ❌ No further development from upstream. If Contact materially changes their
  API, the integration will break until someone forks and patches it.

**Acceptable for the use case** because (a) data isn't safety-critical,
(b) Contact's portal CSV export remains a manual fallback, and (c) the worst
case is we rewrite the integration ourselves using `contact-energy-nz`
directly (see Fallback plan below).

## Why

A smart meter (installed Nov 2025) is collecting consumption data, but it's
invisible to the homelab. Contact's "My Account" portal has no official CSV
export. The community has built a Python lib + HACS integration that use
Contact's mobile-app API — that gives us:

- Hourly historical data (24 points/day, back to meter install date —
  ~6 months)
- Daily-updating ongoing consumption (24–48 hr delay from meter — the most
  recent 1–2 days will read as zero until Contact's API catches up)
- Flow into HA Energy Dashboard, Prometheus exporters, and Grafana dashboards
- Foundation for the solar / battery feasibility model (Phase 3)
- Bonus: the gas contract is visible via the same auth path (`STANDARD METER`
  on the natural-gas ICP). Not wired up in this PR, but useful for the
  Phase 3 electrification baseline.

Verified against the live account 2026-05-12: auth ✓, smart meter discoverable
✓, hourly data returned for a day older than the reporting lag.

## Approach

GitOps-friendly: init container clones the integration into
`/config/custom_components/contact_energy` before HA starts. No HACS UI
clicks, no manual config copying. Pinned to the last-known-good commit SHA
rather than `main` (which is moot since upstream is archived).

## Changes

### 1. `kubernetes/apps/home-automation/home-assistant/app/helmrelease.yaml`

Add an `initContainers` block under `controllers.home-assistant` that pulls
the integration on every pod start.

Key bits:

- Uses `docker.io/alpine/git`, pinned by tag + multi-arch manifest-list digest
- Clones to `/tmp`, then copies to `/config/custom_components/` on the
  shared config PVC
- Idempotent via a `.pinned-sha` marker file — only re-installs when the
  pinned commit changes or `FORCE_UPDATE=true`
- **Pinned to commit `16826d2b82efb294e33f48f70647d21f551b6bf1`** (last
  upstream commit before archival)
- Runs as the same UID/GID as the app container (568); matches the existing
  pod's security profile — no root override needed

### 2. Post-deploy step *(documented, not automated)*

Once the pod restarts and integration code is present:

1. Settings → Devices & Services → Add Integration → "Contact Energy"
2. Enter Contact account email + password
3. Integration backfills historical data automatically (takes a few minutes)
4. Sensors appear under `sensor.contact_energy_*`

Credentials are stored in HA's encrypted secret storage, not in this repo.

## Validation

After Flux applies and pod restarts:

```bash
# Verify init container completed
kubectl logs -n home-automation deploy/home-assistant -c init-contact-energy

# Verify integration files are in place
kubectl exec -n home-automation deploy/home-assistant -- \
  ls -la /config/custom_components/contact_energy

# After UI config, check Energy dashboard for consumption data
```

Expected sensors:

- `sensor.contact_energy_usage_kwh` — main consumption (uncharged + paid)
- `sensor.contact_energy_free_kwh` — free hours of power if on relevant plan
- `sensor.contact_energy_dollars_*` for cost equivalents

Consumption sensors need to be added to the HA Energy Dashboard manually
(Settings → Dashboards → Energy → Add grid consumption).

## Fallback plan (if upstream breaks)

If Contact changes their API and the integration stops working:

**Option A — Build a fresh HA custom component on `contact-energy-nz`.**
The integration we're pinning to does *not* use this library — it vendors
its own sync `requests`-based client. So this fallback is a from-scratch
rebuild, not a swap. The library wraps the same API and is actively
maintained. ~200–300 lines of Python.

**Option B — Run a sidecar Python script** that uses `contact-energy-nz`
to fetch data and push to MQTT or InfluxDB directly. Bypasses HA's custom
component model entirely. Smaller and simpler than Option A but loses HA
Energy Dashboard native integration.

**Option C — Manual CSV from Contact's portal**. Annoying but always works.
Acceptable if Phase 3 feasibility model is the only consumer and we just
need a one-off data dump.

Decision deferred until/unless it actually breaks.

## Rollback

Remove the `initContainers` block from the HelmRelease. The
`/config/custom_components/contact_energy` directory will persist on the PVC
but HA will ignore it once the config entry is also removed via UI. To fully
clean:

```bash
kubectl exec -n home-automation deploy/home-assistant -- \
  rm -rf /config/custom_components/contact_energy
```

## Notes

- Pinning to a specific commit SHA means Renovate is unnecessary here —
  upstream isn't moving. Add a custom manager back if/when we move to an
  actively maintained fork.

## Related

- Roadmap: [`./README.md`](./README.md)
- Upstream (archived): https://github.com/codyc1515/ha-contact-energy
- Python lib (active fallback): https://pypi.org/project/contact-energy-nz/
- Pinned commit: https://github.com/codyc1515/ha-contact-energy/commit/16826d2b82efb294e33f48f70647d21f551b6bf1
