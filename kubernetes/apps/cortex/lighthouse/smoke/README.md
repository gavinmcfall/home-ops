# Lighthouse heavy-tier smoke fixtures

Reference artifacts for the first heavy-tier image-gen smoke. **Not a Flux
resource** — this `smoke/` dir is outside the Flux Kustomization path
(`../app`), so nothing here is applied to the cluster.

## `workshop-prompt.json`

A minimal SDXL text2img graph with a **`DistributedCollector`** node (so the
master delegates the render to a GPU worker rather than running it CPU-only),
wrapped in the ComfyUI-Distributed **`POST /distributed/queue`** envelope
(`enabled_worker_ids` + `delegate_master`). Validated against the licence-gate
logic with the mounted allowlist: all nodes allowlisted, references
`sd_xl_base_1.0.safetensors` (registry: commercial-OK), commercial job
**allowed**.

> The collector node is why this targets `/distributed/queue`, not `/prompt`: a
> plain `/prompt` runs the whole graph on the CPU-only master. Both endpoints are
> licence-gated by the proxy.

Use it to drive the first end-to-end render through the deployed surface:

```bash
# Through the OIDC-gated proxy (browser session / forwarded id_token):
curl -sS https://lighthouse.nerdz.cloud/distributed/queue \
  -H "Authorization: Bearer <id_token>" \
  -H "Content-Type: application/json" \
  --data @workshop-prompt.json

# The proxy rewrites SaveImage filename_prefix to "<user>/workshop", forwards to
# the orchestrator-only ComfyUI master, which delegates the render to a worker
# and collects the result back; the master's SaveImage writes to /output/<user>/.
```

Pre-conditions: cluster deployed (lighthouse-impl merged to main), the model
present on the workers, and the workers awake. The real curated App Mode
workflows are exported from running ComfyUI later (cluster-deploy-contract open
item #6) — this is only a smoke starter.
