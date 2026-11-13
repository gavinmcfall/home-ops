"""Generate .github/flate/supply.yaml: placeholder `cluster-secrets` for every namespace.

Reads KEY NAMES only from the SOPS files (values there are encrypted and are never read or written).
flate cannot decrypt SOPS, so Kustomization postBuild.substituteFrom needs stand-in values offline.
"""
import pathlib
import sys

import yaml

root = pathlib.Path(sys.argv[1])
keys: set[str] = set()
for f in (
    root / "kubernetes/flux/vars/cluster-secrets.sops.yaml",
    root / "kubernetes/components/common/cluster-vars/cluster-secrets.sops.yaml",
):
    doc = yaml.safe_load(f.read_text(encoding="utf-8"))
    keys |= set((doc.get("stringData") or doc.get("data") or {}).keys())


def placeholder(key: str) -> str:
    if key == "SECRET_DOMAIN":
        return "example.com"
    if key.endswith("_IP"):
        return "192.0.2.1"
    if "EMAIL" in key:
        return "nobody@example.com"
    if key in ("LATITUDE", "LONGITUDE"):
        return "0"
    return "placeholder"


namespaces = sorted({p.name for p in (root / "kubernetes/apps").iterdir() if p.is_dir()} | {"flux-system"})

header = """\
---
# Placeholder Secrets supplied to flate for offline rendering. NOT real values.
#
# Every Flux Kustomization substitutes variables from a `cluster-secrets`
# Secret in its own namespace (kubernetes/components/common/cluster-vars).
# Those are SOPS-encrypted, and flate cannot decrypt them, so without stand-ins
# `${SECRET_DOMAIN}` and friends render as empty and some charts fail their
# schema. This file gives flate a value for each key.
#
# Generated from the key NAMES in the two cluster-secrets.sops.yaml files and
# the namespace folders under kubernetes/apps. Regenerate when a key or a
# namespace is added:  task kubernetes:flate-supply
"""
docs = []
for ns in namespaces:
    docs.append(
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": "cluster-secrets", "namespace": ns},
            "stringData": {k: placeholder(k) for k in sorted(keys)},
        }
    )
out = root / ".github/flate/supply.yaml"
out.parent.mkdir(parents=True, exist_ok=True)
body = "---\n".join(yaml.safe_dump(d, sort_keys=False) for d in docs)
out.write_text(header + body, encoding="utf-8", newline="\n")
print(f"wrote {out} with {len(docs)} namespaces and {len(keys)} keys")
