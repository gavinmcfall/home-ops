# Envoy Route Migration Workspace

This folder captures the working knowledge for moving from Kubernetes Ingress resources to Envoy Gateway routes.

- [Migration Plan](plan.md) – Namespace-by-namespace strategy, execution order, and operational checklist.
- [Namespace Index](indexes/namespace-index.md) – High-level folder structure showing namespaces, child directories, and top-level files.
- [App Directory Index](indexes/app-directory-index.md) – Detailed listing of every `app` directory and its files/subfolders.
- [Ingress File Index](indexes/ingress-index.md) – Known ingress manifests that must be folded into HelmReleases.
- [Envoy Route Reference](route-reference.md) – Canonical route block lifted from the Sonarr example to guide future edits.

Follow the documents above in order: review the indexes, apply the plan, and model new routes after the reference implementation.
