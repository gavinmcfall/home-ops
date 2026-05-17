# Observability audit — 2026-05-17

## What was checked

1. **Prometheus metric inventory** — dumped `/api/v1/label/__name__/values`, got 6,163 series across ~820 unique prefixes. Saved to `/tmp/obs-audit/all-metrics.txt` for the duration of the session (not persisted in repo).
2. **All deployed exporters** under `observability/exporters/` — confirmed series counts per family:

   | Exporter | Prefix | Series in Prometheus | Status |
   | --- | --- | ---: | --- |
   | intel-device-plugin-exporter | `igpu_*` | 21 | ✅ producing on all 3 stantons |
   | plex-exporter | `plex_*` | 6 | ✅ |
   | tautulli-exporter | `tautulli_*` | 9 | ✅ |
   | exportarr-sonarr | `sonarr_*` | 23 | ✅ |
   | exportarr-radarr | `radarr_*` | 18 | ✅ |
   | smartctl-exporter | `smartctl_*` | 21 | ✅ |
   | nut-exporter | `network_ups_tools_*` | 9 | ✅ |
   | speedtest-exporter | `speedtest_*` | 6 | ⚠️ scrape-stale (see fix) |
   | unpoller (UniFi) | `unpoller_*` | many | ✅ |
   | snmp-exporter | various | — | ✅ |
   | mariadb-exporter | `mysql_*` etc | — | ✅ |
   | blackbox-exporter | `probe_*` | — | ✅ |
   | graphite-exporter | `graphite_*` | — | ✅ |

3. **kube-state-metrics collector coverage** — found only `nodes`, `pods`, `deployments` enabled; every other resource family was absent from Prometheus.
4. **node-exporter coverage** — only 3/4 nodes had a pod running (stanton-01/02/03). pyro-01 was silent because its `nvidia.com/gpu=true:NoExecute` taint wasn't tolerated by the bundled chart.
5. **promtail coverage** — same gap on pyro-01.
6. **NVIDIA GPU metrics** — none present; no DCGM_FI_DEV_* / nvidia_gpu_* series despite the GTX 1080 Ti being exposed via NVIDIA device plugin on pyro-01.
7. **Per-node power telemetry** — probed Talos for IPMI: `/dev/ipmi0` does not exist and `/sys/class/ipmi` is empty on the MS-01 (Venus Series, board AHWSA). No RAPL series from kernel. Cluster has no smart PDU.
8. **kromgo nerdz.cloud queries** — all 22 added in commit `23ca505ab` verified live against Prometheus.

## What was fixed

### Commit 1 — `feat(kube-prometheus-stack): expand KSM collectors + tolerate GPU taint on node-exporter`

- `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`
- KSM collectors expanded from 3 → 17: added `persistentvolumeclaims`, `persistentvolumes`, `statefulsets`, `daemonsets`, `replicasets`, `services`, `endpoints`, `namespaces`, `jobs`, `cronjobs`, `ingresses`, `storageclasses`, `horizontalpodautoscalers`, `poddisruptionbudgets`.
- `prometheus-node-exporter.tolerations` set to `Exists` on both `NoSchedule` and `NoExecute` so the DaemonSet schedules onto pyro-01.

### Commit 2 — `feat(observability): deploy dcgm-exporter for pyro-01 GPU metrics`

- New HelmRepository `nvidia-dcgm` → `https://nvidia.github.io/dcgm-exporter/helm-charts` (wired into `kubernetes/flux/repositories/helm/kustomization.yaml`).
- New HelmRelease `dcgm-exporter` (chart 4.8.2) under `kubernetes/apps/observability/exporters/dcgm-exporter/`.
- Node affinity restricts to `nvidia.com/gpu="true"` (only pyro-01 today).
- Tolerates `nvidia.com/gpu:NoExecute` and `node-role.kubernetes.io/control-plane:NoSchedule`.
- Runs with `runtimeClassName: nvidia`. SYS_ADMIN capability NOT added — GTX 1080 Ti (Pascal, sm_6.1) does not support DCGM_FI_PROF_* metrics, so the standard counters (temp / power / SM-util / MEM-util / clocks / ECC) are all we get. Saves the privilege cost.
- Image pinned to `nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2-distroless@sha256:60d3b00ac80b4ae77f94dae2f943685605585ad9e92fdccda3154d009ae317cc` (per CLAUDE.md rule 4).
- ServiceMonitor enabled, 30s interval.

### Commit 3 — `feat(promtail): tolerate GPU taint so logs ship from pyro-01`

- `kubernetes/apps/observability/promtail/app/helmrelease.yaml` — same toleration block as node-exporter.

### Commit 4 — `feat(kromgo): observability-audit additions + speedtest staleness fix`

- `kubernetes/apps/observability/kromgo/app/resources/config.yaml`
- Fixed: `speedtest_download_mbps`, `speedtest_upload_mbps`, `speedtest_ping_ms` wrapped in `last_over_time(…[2h])`. The scrape is hourly, but the Prometheus default `query.lookback-delta` of 5 minutes means instant queries see a fresh sample for only 5/60 minutes — kromgo was returning EMPTY for 92 % of every hour. The 2 h window gives a safe overlap.
- Added 25 new queries (see "New kromgo queries" below).

## New metrics now available in Prometheus

After KPS reconciles (≤30 min from push):

- `kube_persistentvolumeclaim_*` (status_phase, resource_requests_storage_bytes, info, labels)
- `kube_persistentvolume_*` (info, capacity_bytes, status_phase)
- `kube_statefulset_*` (replicas, status_replicas_ready, status_observed_generation)
- `kube_daemonset_*` (status_number_ready, status_desired_number_scheduled, status_number_unavailable)
- `kube_replicaset_*`
- `kube_service_*` (info, spec_type)
- `kube_endpoint_*` (info, address_available)
- `kube_namespace_*` (created, status_phase)
- `kube_job_*` (status_active, status_succeeded, status_failed, complete, failed)
- `kube_cronjob_*` (info, next_schedule_time, status_active)
- `kube_ingress_*` (info, path)
- `kube_storageclass_info`
- `kube_horizontalpodautoscaler_*`
- `kube_poddisruptionbudget_*`

After dcgm-exporter reconciles + the pod starts on pyro-01:

- `DCGM_FI_DEV_GPU_TEMP` — die temperature (°C)
- `DCGM_FI_DEV_GPU_UTIL` — SM utilisation %
- `DCGM_FI_DEV_MEM_COPY_UTIL` — memory copy engine utilisation %
- `DCGM_FI_DEV_POWER_USAGE` — instantaneous power (W)
- `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_FB_FREE`, `DCGM_FI_DEV_FB_TOTAL` — framebuffer MiB
- `DCGM_FI_DEV_SM_CLOCK`, `DCGM_FI_DEV_MEM_CLOCK` — clocks MHz
- `DCGM_FI_DEV_ECC_*` — ECC counters (1080 Ti has ECC disabled, will report zeros)
- ~30 others from `default-counters.csv`

After node-exporter reconciles on pyro-01:

- All `node_*` series (CPU, memory, network, disk, hwmon, etc.) for `10.90.3.111:9100`
- Recording rules `instance:node_cpu_utilisation:rate5m{instance="10.90.3.111:9100"}` etc. fill in next eval cycle.

## New kromgo queries

| Name | Query | Purpose |
| --- | --- | --- |
| `cluster_pvc_bound` | `sum(kube_persistentvolumeclaim_status_phase{phase="Bound"})` | Tier 4 |
| `cluster_pvc_pending` | …`{phase="Pending"}` with color thresholds | flag stuck PVCs |
| `cluster_pvc_lost` | …`{phase="Lost"}` | red on >0 |
| `cluster_pv_count` | `count(kube_persistentvolume_info)` | rough volume count |
| `cluster_storageclass_count` | `count(kube_storageclass_info)` | sanity |
| `cluster_statefulsets_ready` / `_desired` | KSM aggregates | Tier 3 |
| `cluster_daemonsets_ready` / `_desired` | KSM aggregates | Tier 3 |
| `cluster_jobs_running` / `_failed` | KSM aggregates | Tier 3 |
| `cluster_cronjobs_count` | KSM count | Tier 3 |
| `cluster_services_count` | KSM count | Tier 3 |
| `cluster_namespaces_count` | KSM count | Tier 3 |
| `flux_helmreleases_ready` / `_total` / `_failing` | from `gotk_resource_info{customresource_kind="HelmRelease"}` | Tier 5 |
| `flux_kustomizations_ready` / `_total` / `_failing` | same pattern for `Kustomization` | Tier 5 |
| `intel_igpu_package_power_avg` / `_total` | `igpu_power_package` aggregates (W) | iGPU + Plex transcode load |
| `intel_igpu_video_busy_max` | `max(igpu_engines_video_0_busy)` | "is something transcoding now?" |
| `nvidia_gpu_temp_c` | `max(DCGM_FI_DEV_GPU_TEMP)` OR vector(0) | pyro-01 GPU temp |
| `nvidia_gpu_util_pct` | `max(DCGM_FI_DEV_GPU_UTIL)` | SM util |
| `nvidia_gpu_power_watts` | `sum(DCGM_FI_DEV_POWER_USAGE)` | board power |
| `nvidia_gpu_mem_used_mb` / `_free_mb` | `sum(DCGM_FI_DEV_FB_USED|FREE)` | VRAM |
| `node_power_est_stanton01` / `_stanton02` / `_stanton03` / `_pyro01` | total UPS power × per-node CPU utilisation share | proxy for per-node draw — see "What's still open" |

All wrap `OR vector(0)` where the underlying source can be transiently absent (dcgm-exporter restart, GPU idle, etc.) so the dashboard stays green instead of dropping the badge.

## What's still open / out of scope

- **Per-node power telemetry — true measurement.** The MS-01 (Venus Series, board AHWSA) does not expose IPMI/BMC to Talos (`/dev/ipmi0` absent, `/sys/class/ipmi` empty). No RAPL series. The added `node_power_est_*` queries are a CPU-weighted estimate from the aggregate UPS reading; they will mis-attribute idle baseline draw between nodes and undercount nodes doing GPU/IO-heavy work with low CPU. Documented in the kromgo config with a comment. The only true fix is a smart PDU (e.g. APC AP8959EU3) or a Shelly Plus 1PM per node — hardware buy, not a software change.
- **dcgm-exporter on Pascal.** GTX 1080 Ti returns `-1` for `DCGM_FI_PROF_*` profiling metrics. The chart's `arguments` are set to the default counters set only, so these never get queried — but if anyone adds a custom counters configmap, those entries will be empty.
- **Pod-resources socket on Talos.** dcgm-exporter mounts `/var/lib/kubelet/pod-resources` from the host to attribute GPU usage back to pods. Talos uses the standard kubelet path so this should work, but it has not been verified yet — if attribution is missing after the pod is up, that's the cause. The exporter still publishes GPU-wide metrics either way.
- **smartctl-exporter on pyro-01.** DaemonSet is 3/4 (missing pyro). Lower priority — pyro has a single SSD; not worth the toleration churn unless we start running storage-intensive workloads there.
- **Sparkline / range data (Tier 7).** Out of scope per audit brief. Two reasonable options when wanted: Grafana iframe embeds (cheapest), or a Prometheus range-query proxy alongside kromgo (more flexible).
- **NUT per-UPS labelling.** `network_ups_tools_*` returns 2 series per metric (jaeger + apc) — kromgo queries `min(...)` / `sum(...)` which works but loses the distinction. If the dashboard wants per-UPS, expose them as separate kromgo entries keyed on the `ups` label.
- **Speedtest scrape cadence vs sample size.** Hourly is fine for trends but a single sample is noisy. If averaged Mbps is wanted, add an `avg_over_time(...[24h])` companion query.
- **Pre-existing `task kubernetes:kubeconform` failure.** The unifi HTTPRoute hostname `unifi.${SECRET_DOMAIN}` fails the DNS pattern check because validation happens before Flux substitution. This is unrelated to this audit but worth fixing — it blocks the verify-gate hook for any home-ops commit and forces per-app validation. Options: pre-substitute via envsubst before kubeconform, exclude raw-substitution paths, or skip the HTTPRoute kind on that path.

## Recommended next steps for the nerdz.cloud team

1. **Wait for the next KPS reconcile** (≤30 min from push) before consuming the new kube-state-metrics families. Verify with:
   ```bash
   curl -sG --data-urlencode 'query=count(kube_persistentvolumeclaim_status_phase)' http://kromgo/api/...
   ```
2. **Verify dcgm-exporter** after the Flux reconcile:
   ```bash
   kubectl -n observability get pods -l app.kubernetes.io/name=dcgm-exporter -o wide
   kubectl -n observability logs ds/dcgm-exporter --tail=30
   curl -sG --data-urlencode 'query=DCGM_FI_DEV_GPU_TEMP' http://prom/api/v1/query
   ```
   If the pod crash-loops with "Could not initialize NVML" or similar, the `runtimeClassName: nvidia` + nvidia device plugin chain needs investigating (almost certainly device plugin / runtime mismatch).
3. **Build the per-node card row in the dashboard from existing recording rules:**
   - `instance:node_cpu_utilisation:rate5m{instance="<ip>:9100"}` — CPU %
   - `instance:node_memory_utilisation:ratio{instance="<ip>:9100"}` — Mem %
   - `node_filesystem_avail_bytes{mountpoint="/"}` / `node_filesystem_size_bytes` — root disk %
   - `node_hwmon_temp_celsius{chip=~"coretemp.*"}` — CPU temp
   - `node_time_seconds - node_boot_time_seconds` — uptime
   - `kube_pod_info{node="<name>"}` count — pods on node
   - `node_power_est_<nodename>` from kromgo — power estimate
4. **For Tier 5 (GitOps), the `flux_*` kromgo queries are ready now** — they read `gotk_resource_info`, which is already populated by the existing KSM customResourceState config.
5. **For Tier 7 (trends), pick either** an `iframe` Grafana embed of a curated row, or commission a tiny Prometheus range-query adapter — kromgo upstream has an open issue for this but it isn't shipped yet.

## Methodology notes (reusable)

- Prometheus instant query lookback default is **5 minutes**. Exporters that scrape less often than that (speedtest, snmp polling cycles, long-running probes) need `last_over_time(...[long-enough])` to surface in kromgo / Grafana single-stat panels. This bit us once already; worth checking other low-frequency exporters next time something looks "empty".
- The `gotk_resource_info` series produced by KSM's customResourceState is more useful than `gotk_reconcile_condition` for "how many Xs are ready" rollups — the latter has a `status="True"` label gotcha and is missing several conditions.
- `intel_gpu_*` is the wrong prefix to grep for the intel-device-plugin-exporter; it emits `igpu_*` (engines, frequency, power, IRQ). The audit brief had it wrong; the exporter has been working for 12+ days.
