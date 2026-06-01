# Lighthouse heavy-tier smoke fixtures

Reference artifacts for the first heavy-tier image-gen smoke. **Not a Flux
resource** — this `smoke/` dir is outside the Flux Kustomization path
(`../app`), so nothing here is applied to the cluster.

## `workshop-prompt.json`

A minimal, standard SDXL text2img graph wrapped in the ComfyUI `POST /prompt`
envelope. Validated against the licence-gate logic (parse → node allowlist →
licence gate): all 7 nodes are on the built-in `DefaultAllowlist`, it references
`sd_xl_base_1.0.safetensors` (registry: commercial-OK), and a commercial job is
**allowed**.

Use it to drive the first end-to-end render through the deployed surface, e.g.:

```bash
# Through the OIDC-gated proxy (browser session / forwarded id_token):
curl -sS https://lighthouse.nerdz.cloud/prompt \
  -H "Authorization: Bearer <id_token>" \
  -H "Content-Type: application/json" \
  --data @workshop-prompt.json

# The proxy rewrites SaveImage filename_prefix to "<user>/workshop" and forwards
# to the orchestrator-only ComfyUI master, which delegates the render to a worker.
```

Pre-conditions: cluster deployed (lighthouse-impl merged to main), the model
present on the workers, and the workers awake. The real curated App Mode
workflows are exported from running ComfyUI later (cluster-deploy-contract open
item #6) — this is only a smoke starter.
