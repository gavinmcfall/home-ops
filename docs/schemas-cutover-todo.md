# Schema cutover — followups

Tracking what's left after the `kubernetes-schemas.nerdz.cloud` → `k8s-schemas.home-operations.com` cutover.

## NFD (node-feature-discovery)

Three files now point at a 404 upstream URL:

- `kubernetes/apps/kube-system/node-feature-discovery/features/intel-gpu.yaml`
- `kubernetes/apps/kube-system/node-feature-discovery/features/eaton.yaml`
- `kubernetes/apps/kube-system/node-feature-discovery/features/nvidia-gpu.yaml`

NFD has never been published in `home-operations/k8s-schemas`. Open a PR adding it:

- Path: `sources/kubernetes-sigs/node-feature-discovery/vendir.yml`
- Type: `git` (NFD releases ship a Helm chart asset, not a CRDs-only YAML)
- Source: `https://github.com/kubernetes-sigs/node-feature-discovery`
- Tag: latest stable (currently `v0.18.3`)
- Include path: `deployment/base/nfd-crds/nfd-api-crds.yaml`

Once the source merges and the release workflow republishes, validation for these three files starts working with no further changes — the URL is already correct.

## Verify after upstream republish

```sh
for u in nfd.k8s-sigs.io/nodefeaturerule_v1alpha1.json; do
  curl -s -o /dev/null -w "%{http_code} $u\n" "https://k8s-schemas.home-operations.com/$u"
done
```

Should return `200`. Delete this file when it does.
