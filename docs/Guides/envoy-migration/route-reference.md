# Envoy Route Reference

Source example: `/home/gavin/cloned-repos/homelab-repos/Kashalls/infrastructure/kubernetes/apps/entertainment/sonarr/app/helmrelease.yaml`.

```yaml
values:
  route:
    app:
      hostnames: ["{{ .Release.Name }}.ok8.sh"]
      parentRefs:
        - name: internal
          namespace: networking
          sectionName: https
      rules:
        - backendRefs:
            - identifier: app
              port: *port
```

Key takeaways:
- The route definition lives under the HelmRelease `values` and mirrors the service name/port exposed by the chart (`backendRefs.identifier` matches the service key).
- `hostnames` drive Envoy Gateway HTTPRoute host matching; template expressions leverage `.Release.Name` to keep hostnames consistent.
- `parentRefs` point at the Envoy Gateway (`internal/networking/https` in this example). Each route must reference the correct Gateway and TLS listener section.
- `rules` include one or more `backendRefs`, allowing multiple services/ports if needed; each reference can reuse Helm anchors such as `*port` for consistency.
- Additional annotations (not shown above) can be added per route as needed (see Sonarr example in source file) without leaving the HelmRelease.
- Every migration should ensure probes, services, and persistence definitions remain untouched—only ingress → route conversions move.
