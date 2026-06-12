# OpenTelemetry backbone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the central OTLP ingestion plane — an OpenTelemetry Collector
(contrib) backed by a dedicated InfluxDB 3 Enterprise on Ceph RGW — with three
access tiers, then prove it end-to-end by landing AI-CLI telemetry.

**Architecture:** Collector in `observability` receives OTLP (in-cluster / LAN
Cilium LB IP / off-LAN Cloudflare external gateway), bearer-auth on all tiers,
and exports metrics to InfluxDB 3 in `database`, which persists Parquet to a Ceph
RGW bucket. Traces/logs pipelines are written but stubbed.

**Tech Stack:** Flux + bjw-s `app-template` v4.4.0, official
`opentelemetry-collector` Helm chart (contrib image), InfluxDB 3 Enterprise
(`influxdb:3-enterprise`), Rook-Ceph RGW (`ObjectBucketClaim`), Cilium LB IPAM,
Gateway API (`external` gateway = Cloudflare tunnel), External Secrets +
1Password, Grafana.

**Reference spec:** `docs/infrastructure-roadmap/otel-telemetry-backbone.md`

> **Conventions confirmed from the repo (use these verbatim):**
> - Apps: `kubernetes/apps/<ns>/<app>/{ks.yaml, app/{helmrelease,kustomization,...}.yaml}`; each app's `ks.yaml` is registered in `kubernetes/apps/<ns>/kustomization.yaml`.
> - `ks.yaml`: `kustomize.toolkit.fluxcd.io/v1` Kustomization, `targetNamespace`, `sourceRef` GitRepository `flux-system`, `postBuild.substitute`.
> - HelmRelease via bjw-s `app-template` 4.4.0 (HelmRepository `bjw-s`); images pinned `tag@sha256:…`.
> - ExternalSecret: `external-secrets.io/v1`, `ClusterSecretStore onepassword-connect`, `dataFrom.extract.key`.
> - LB IP: `Service` annotation `io.cilium/lb-ipam-ips: ${VAR}`, var defined in `kubernetes/components/common/cluster-vars/cluster-settings.yaml`; pool `lb-pool` is `10.99.8.0/24`.
> - Ceph RGW S3 endpoint: `rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80`, region `us-east-1`, plain HTTP. OBC `storageClassName: ceph-bucket` emits a Secret (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) + ConfigMap (`BUCKET_NAME`/`BUCKET_HOST`) named after the OBC.
> - External (Cloudflare) routing = Gateway API `route` with `parentRefs: [{name: external, namespace: network, sectionName: https}]` + `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}`. Internal/LAN HTTP = `internal` gateway.
> - `${SECRET_DOMAIN}` is a cluster-wide postBuild substitution.

> **Verification model (GitOps, not unit tests):** each task renders locally with
> `kustomize build`, then is committed/pushed and reconciled with `flux reconcile`,
> then smoke-checked against live resources. There is no `pytest` here — "test
> fails / passes" maps to "manifest renders / reconciles / behaves".

---

## Task 0: Add the OpenTelemetry Helm repository

**Files:**
- Create: `kubernetes/flux/repositories/helm/opentelemetry.yaml`
- Modify: `kubernetes/flux/repositories/helm/kustomization.yaml`

- [ ] **Step 1: Pin the current chart version**

Run: `helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && helm repo update && helm search repo open-telemetry/opentelemetry-collector --versions | head -5`
Record the latest `opentelemetry-collector` chart version (used in Task 6). Do not guess it.

- [ ] **Step 2: Create the HelmRepository**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: opentelemetry
  namespace: flux-system
spec:
  interval: 1h
  url: https://open-telemetry.github.io/opentelemetry-helm-charts
```

- [ ] **Step 3: Register it** — add `- ./opentelemetry.yaml` to the `resources:` list in `kubernetes/flux/repositories/helm/kustomization.yaml` (keep alphabetical order: after `openebs.yaml`).

- [ ] **Step 4: Render**

Run: `kustomize build kubernetes/flux/repositories/helm | grep -A3 "name: opentelemetry"`
Expected: the HelmRepository renders.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/flux/repositories/helm/opentelemetry.yaml kubernetes/flux/repositories/helm/kustomization.yaml
git commit -m "feat(flux): add opentelemetry helm repository"
```

---

## Task 1: Ceph RGW bucket for InfluxDB 3 (ObjectBucketClaim)

**Files:**
- Create: `kubernetes/apps/database/influxdb3/app/objectbucketclaim.yaml`

(The rest of the `influxdb3` app files are created in later tasks; this task only adds the OBC so the bucket + its Secret/ConfigMap exist before InfluxDB needs them.)

- [ ] **Step 1: Create the OBC** (same pattern as `zot`)

```yaml
---
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: influxdb3
spec:
  bucketName: influxdb-telemetry
  storageClassName: ceph-bucket
```

- [ ] **Step 2: Note the generated artifacts** — once applied (Task 4), this yields:
  - Secret `influxdb3` with `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
  - ConfigMap `influxdb3` with `BUCKET_NAME` (= `influxdb-telemetry`) / `BUCKET_HOST`

  These are consumed by the InfluxDB HelmRelease in Task 3. No commit yet — committed together with Task 3.

---

## Task 2: InfluxDB 3 — PVC + ExternalSecret

**Files:**
- Create: `kubernetes/apps/database/influxdb3/app/pvc.yaml`
- Create: `kubernetes/apps/database/influxdb3/app/externalsecret.yaml`

- [ ] **Step 1: Create the WAL/cache PVC** (local hot tier; Parquet durability is in Ceph RGW)

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: influxdb3
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 20Gi
  storageClassName: ceph-block
```

> Confirm `ceph-block` is the cluster's RWO block StorageClass (`kubectl get storageclass`); adjust if it differs.

- [ ] **Step 2: Pre-create the 1Password item** — manually create a 1Password item `influxdb3` in the `cluster` vault with fields:
  - `INFLUXDB3_ENTERPRISE_LICENSE_EMAIL` = your at-home license email
  - `INFLUXDB3_ADMIN_TOKEN` = leave blank for now (filled in Task 4 after the token is generated)

- [ ] **Step 3: Create the ExternalSecret**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: influxdb3
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: influxdb3-secret
    template:
      engineVersion: v2
      data:
        INFLUXDB3_ENTERPRISE_LICENSE_EMAIL: "{{ .INFLUXDB3_ENTERPRISE_LICENSE_EMAIL }}"
  dataFrom:
    - extract:
        key: influxdb3
```

- [ ] **Step 4:** No commit yet — committed with Task 3.

---

## Task 3: InfluxDB 3 Enterprise HelmRelease

**Files:**
- Create: `kubernetes/apps/database/influxdb3/app/helmrelease.yaml`
- Create: `kubernetes/apps/database/influxdb3/app/kustomization.yaml`
- Create: `kubernetes/apps/database/influxdb3/ks.yaml`
- Modify: `kubernetes/apps/database/kustomization.yaml`

- [ ] **Step 1: Resolve the image digest** (do not invent it)

Run: `crane digest influxdb:3-enterprise` (or check Docker Hub tag `3-enterprise`).
Use the result as `tag: 3-enterprise@sha256:<digest>` below.

- [ ] **Step 2: Create the HelmRelease**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/common-4.4.0/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app influxdb3
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 4.4.0
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
  values:
    controllers:
      influxdb3:
        type: statefulset
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: docker.io/library/influxdb
              tag: 3-enterprise@sha256:REPLACE_WITH_DIGEST_FROM_STEP_1
            args:
              - serve
              - --node-id=influxdb3-0
              - --object-store=s3
              - --data-dir=/var/lib/influxdb3
              - --http-bind=0.0.0.0:8181
              - --aws-endpoint=http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
              - --aws-default-region=us-east-1
              - --aws-allow-http
            env:
              INFLUXDB3_BUCKET: influxdb-telemetry
              AWS_ALLOW_HTTP: "true"
            envFrom:
              # OBC-generated creds (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
              - secretRef:
                  name: influxdb3
              # License email
              - secretRef:
                  name: influxdb3-secret
            probes:
              liveness: &probes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: &port 8181
                  initialDelaySeconds: 30
                  periodSeconds: 10
              readiness: *probes
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 100m
                memory: 512Mi
              limits:
                memory: 4Gi
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile: { type: RuntimeDefault }
    service:
      app:
        controller: influxdb3
        ports:
          http:
            port: *port
    persistence:
      data:
        existingClaim: influxdb3
        globalMounts:
          - path: /var/lib/influxdb3
```

> **Verify during impl:** the `--health`/`/health` endpoint path and the exact
> `serve` arg spelling against `influxdb3 serve --help` in the running image
> (`kubectl exec … -- influxdb3 serve --help`). The env-var equivalents
> (`INFLUXDB3_OBJECT_STORE`, `AWS_ENDPOINT`, etc.) may be used instead of args if
> cleaner — both are documented. Adjust before declaring the task done.

- [ ] **Step 3: Create the app kustomization**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./objectbucketclaim.yaml
  - ./pvc.yaml
  - ./externalsecret.yaml
  - ./helmrelease.yaml
```

- [ ] **Step 4: Create the ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app influxdb3
  namespace: &namespace database
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/database/influxdb3/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

- [ ] **Step 5: Register the app** — add `- ./influxdb3/ks.yaml` to `kubernetes/apps/database/kustomization.yaml` (match existing ordering).

- [ ] **Step 6: Render**

Run: `kustomize build kubernetes/apps/database/influxdb3/app`
Expected: OBC, PVC, ExternalSecret, HelmRelease all render with no errors.

- [ ] **Step 7: Commit** (Tasks 1–3 together — one coherent InfluxDB app)

```bash
git add kubernetes/apps/database/influxdb3 kubernetes/apps/database/kustomization.yaml
git commit -m "feat(database): InfluxDB 3 Enterprise on Ceph RGW"
```

---

## Task 4: Deploy & bootstrap InfluxDB 3

- [ ] **Step 1: Push & reconcile**

```bash
git push
flux reconcile kustomization cluster-apps --with-source
flux reconcile kustomization influxdb3 -n database
```

- [ ] **Step 2: Confirm the pod is healthy and writing to Ceph**

Run: `kubectl -n database get pods -l app.kubernetes.io/name=influxdb3`
Expected: `1/1 Running`.
Run: `kubectl -n database logs sts/influxdb3 | tail -30`
Expected: license accepted, object store initialised, HTTP server on `:8181`, no S3 errors.

- [ ] **Step 3: Generate the admin token**

Run: `kubectl -n database exec sts/influxdb3 -- influxdb3 create token --admin`
Copy the token. **Store it in the 1Password `influxdb3` item as `INFLUXDB3_ADMIN_TOKEN`.**

- [ ] **Step 4: Surface the token via ExternalSecret** — add to the `externalsecret.yaml` template data:
```yaml
        INFLUXDB3_ADMIN_TOKEN: "{{ .INFLUXDB3_ADMIN_TOKEN }}"
```
Commit:
```bash
git add kubernetes/apps/database/influxdb3/app/externalsecret.yaml
git commit -m "feat(database): surface InfluxDB 3 admin token"
git push && flux reconcile kustomization influxdb3 -n database
```

- [ ] **Step 5: Create the databases**

```bash
TOKEN=$(kubectl -n database get secret influxdb3-secret -o jsonpath='{.data.INFLUXDB3_ADMIN_TOKEN}' | base64 -d)
# 730d retention cap on dev-telemetry (measure-first safety cap on Ceph growth)
kubectl -n database exec sts/influxdb3 -- influxdb3 create database dev-telemetry --retention-period 730d --token "$TOKEN"
kubectl -n database exec sts/influxdb3 -- influxdb3 create database app-metrics --retention-period 730d --token "$TOKEN"
```

> **Verify during impl:** the exact retention flag spelling (`--retention-period`
> vs `--retention`) against `influxdb3 create database --help` in the running
> image; set the 730d cap per the spec. If the flag differs, use the correct one
> — do not skip the cap.

- [ ] **Step 6: Smoke write + read** (line protocol via the v2-compatible write API → SQL read)

```bash
kubectl -n database exec sts/influxdb3 -- sh -c \
 'influxdb3 write --database dev-telemetry --token '"$TOKEN"' "smoke,src=plan value=1"'
kubectl -n database exec sts/influxdb3 -- influxdb3 query --database dev-telemetry --token "$TOKEN" \
 "SELECT * FROM smoke"
```
Expected: the row comes back. InfluxDB 3 is live on Ceph RGW.

---

## Task 5: OTel Collector — ExternalSecret (tokens)

**Files:**
- Create: `kubernetes/apps/observability/otel-collector/app/externalsecret.yaml`

- [ ] **Step 1: Generate a bearer token & store it** — create a random token (`openssl rand -hex 32`) and store both it and the InfluxDB admin token in a 1Password item `otel-collector` (vault `cluster`): fields `OTEL_BEARER_TOKEN`, `INFLUXDB3_TOKEN` (= the admin token from Task 4, or a dedicated write token created via `influxdb3 create token`).

- [ ] **Step 2: Create the ExternalSecret**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: otel-collector
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: otel-collector-secret
    template:
      engineVersion: v2
      data:
        OTEL_BEARER_TOKEN: "{{ .OTEL_BEARER_TOKEN }}"
        INFLUXDB3_TOKEN: "{{ .INFLUXDB3_TOKEN }}"
  dataFrom:
    - extract:
        key: otel-collector
```

- [ ] **Step 3:** No commit yet — committed with Task 6.

---

## Task 6: OTel Collector HelmRelease (contrib) + config

**Files:**
- Create: `kubernetes/apps/observability/otel-collector/app/helmrelease.yaml`
- Create: `kubernetes/apps/observability/otel-collector/app/kustomization.yaml`
- Create: `kubernetes/apps/observability/otel-collector/ks.yaml`
- Modify: `kubernetes/apps/observability/kustomization.yaml`

- [ ] **Step 1: Create the HelmRelease** (official chart, contrib image, inline config; chart version from Task 0)

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app otel-collector
spec:
  interval: 30m
  chart:
    spec:
      chart: opentelemetry-collector
      version: REPLACE_WITH_VERSION_FROM_TASK_0
      sourceRef:
        kind: HelmRepository
        name: opentelemetry
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  values:
    mode: deployment
    replicaCount: 1
    image:
      repository: otel/opentelemetry-collector-contrib
    command:
      name: otelcol-contrib
    extraEnvs:
      - name: OTEL_BEARER_TOKEN
        valueFrom:
          secretKeyRef:
            name: otel-collector-secret
            key: OTEL_BEARER_TOKEN
      - name: INFLUXDB3_TOKEN
        valueFrom:
          secretKeyRef:
            name: otel-collector-secret
            key: INFLUXDB3_TOKEN
    ports:
      otlp:
        enabled: true
        containerPort: 4317
        servicePort: 4317
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        protocol: TCP
    config:
      extensions:
        bearertokenauth:
          scheme: Bearer
          token: ${env:OTEL_BEARER_TOKEN}
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
              auth:
                authenticator: bearertokenauth
            http:
              endpoint: 0.0.0.0:4318
              auth:
                authenticator: bearertokenauth
      processors:
        memory_limiter:
          check_interval: 5s
          limit_percentage: 80
          spike_limit_percentage: 25
        resource:
          attributes:
            - key: deployment.environment
              value: homelab
              action: upsert
        batch: {}
      exporters:
        influxdb:
          endpoint: http://influxdb3.database.svc.cluster.local:8181
          token: ${env:INFLUXDB3_TOKEN}
          org: telemetry
          bucket: dev-telemetry
          metrics_schema: telegraf-prometheus-v2
      service:
        extensions: [bearertokenauth]
        pipelines:
          metrics:
            receivers: [otlp]
            processors: [memory_limiter, resource, batch]
            exporters: [influxdb]
          # traces:  STUBBED — wired to Tempo in spec 3
          # logs:    STUBBED — stays on promtail/Loki
```

> **Verify during impl:** the contrib `influxdb` exporter's mapping to InfluxDB 3
> — confirm `bucket` maps to the v3 *database* `dev-telemetry` and that `org` is
> accepted/ignored, against the exporter README for the chart's collector version.
> Adjust `bucket`/`org`/`metrics_schema` if the README differs. Confirm the chart
> key names (`ports`, `extraEnvs`, `command.name`) against the chart version's
> `values.yaml` from Task 0.

- [ ] **Step 2: Create the app kustomization**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./helmrelease.yaml
```

- [ ] **Step 3: Create the ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app otel-collector
  namespace: &namespace observability
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: influxdb3
      namespace: database
  path: ./kubernetes/apps/observability/otel-collector/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

- [ ] **Step 4: Register** — add `- ./otel-collector/ks.yaml` to `kubernetes/apps/observability/kustomization.yaml`.

- [ ] **Step 5: Render & deploy**

Run: `kustomize build kubernetes/apps/observability/otel-collector/app`
Then commit, push, reconcile:
```bash
git add kubernetes/apps/observability/otel-collector kubernetes/apps/observability/kustomization.yaml
git commit -m "feat(observability): OTel Collector (contrib) → InfluxDB 3"
git push && flux reconcile kustomization cluster-apps --with-source && flux reconcile kustomization otel-collector -n observability
```

- [ ] **Step 6: Verify pod + config**

Run: `kubectl -n observability get pods -l app.kubernetes.io/name=otel-collector`
Expected: `1/1 Running`.
Run: `kubectl -n observability logs deploy/otel-collector | grep -i "Everything is ready\|influxdb\|error"`
Expected: collector started, OTLP receivers listening, no exporter errors.

---

## Task 7: LAN tier — Cilium LoadBalancer IP

**Files:**
- Modify: `kubernetes/components/common/cluster-vars/cluster-settings.yaml`
- Modify: `kubernetes/apps/observability/otel-collector/app/helmrelease.yaml`

- [ ] **Step 1: Pick a free LB IP** — list what's in use:
```bash
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' | sort
```
Choose a free address in `10.99.8.0/24`. Add to `cluster-settings.yaml`:
```yaml
  OTEL_COLLECTOR_LBIP: "10.99.8.x"   # the chosen free IP
```

- [ ] **Step 2: Add a LoadBalancer service** to the collector HelmRelease values (additional service alongside the default ClusterIP):

```yaml
    service:
      lan:
        enabled: true
        type: LoadBalancer
        annotations:
          io.cilium/lb-ipam-ips: ${OTEL_COLLECTOR_LBIP}
        ports:
          - name: otlp
            port: 4317
            targetPort: 4317
            protocol: TCP
          - name: otlp-http
            port: 4318
            targetPort: 4318
            protocol: TCP
```

> **Verify during impl:** the chart's schema for declaring an *extra* service
> (`service:` vs `additionalService`/`extraServices`) for this chart version.
> The collector keeps its default ClusterIP for in-cluster + as the HTTPRoute
> backend; this LB service is purely the LAN entry point.

- [ ] **Step 3: Commit & reconcile**
```bash
git add kubernetes/components/common/cluster-vars/cluster-settings.yaml kubernetes/apps/observability/otel-collector/app/helmrelease.yaml
git commit -m "feat(observability): expose OTel Collector on LAN via Cilium LB IP"
git push && flux reconcile kustomization otel-collector -n observability
```

- [ ] **Step 4: Verify the LB IP is assigned**
Run: `kubectl -n observability get svc | grep otel-collector`
Expected: a LoadBalancer service with `EXTERNAL-IP = ${OTEL_COLLECTOR_LBIP}`.

---

## Task 8: Off-LAN tier — Cloudflare external HTTPRoute

**Files:**
- Create: `kubernetes/apps/observability/otel-collector/app/httproute.yaml`
- Modify: `kubernetes/apps/observability/otel-collector/app/kustomization.yaml`

- [ ] **Step 1: Create the external HTTPRoute** (OTLP/HTTP `:4318` only — no gRPC externally)

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: otel-collector
  annotations:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: external
      namespace: network
      sectionName: https
  hostnames:
    - "otel.${SECRET_DOMAIN}"
  rules:
    - backendRefs:
        - name: otel-collector       # ClusterIP service
          port: 4318
```

> **Verify during impl:** the in-cluster service name the chart creates for the
> HTTP port (it may be `otel-collector` or `otel-collector-opentelemetry-collector`)
> via `kubectl -n observability get svc`; set `backendRefs.name`/`port` to the
> ClusterIP service exposing 4318.

- [ ] **Step 2: Register** — add `- ./httproute.yaml` to the app `kustomization.yaml` resources.

- [ ] **Step 3: Cloudflare Access (manual, Gavin)** — in Cloudflare Zero Trust, create a self-hosted Access application for `otel.${SECRET_DOMAIN}` with a **service-token** policy; generate a service token (Client ID + Secret). This is the off-LAN machine credential. *(Account-scoped Cloudflare token per the per-account rule; this step is done in the Cloudflare dashboard/API, not the repo.)*

- [ ] **Step 4: Commit & reconcile**
```bash
git add kubernetes/apps/observability/otel-collector/app/httproute.yaml kubernetes/apps/observability/otel-collector/app/kustomization.yaml
git commit -m "feat(observability): expose OTel Collector off-LAN via Cloudflare"
git push && flux reconcile kustomization otel-collector -n observability
```

- [ ] **Step 5: Verify DNS + Access**
Run: `dig +short otel.${SECRET_DOMAIN}` → resolves to the Cloudflare tunnel target.
Run: `curl -s -o /dev/null -w "%{http_code}" https://otel.${SECRET_DOMAIN}/v1/metrics` → expect `403` (Cloudflare Access blocks unauthenticated), confirming the edge gate is active.

---

## Task 9: End-to-end smoke per tier

- [ ] **Step 1: In-cluster** — run a throwaway generator pod against the ClusterIP:
```bash
kubectl -n observability run otlpgen --rm -it --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest -- \
  metrics --otlp-endpoint otel-collector.observability.svc.cluster.local:4317 \
  --otlp-header "authorization=Bearer <OTEL_BEARER_TOKEN>" --otlp-insecure --duration 5s
```
Then confirm rows landed:
```bash
kubectl -n database exec sts/influxdb3 -- influxdb3 query --database dev-telemetry --token "$TOKEN" \
  "SELECT count(*) FROM gen"
```
Expected: non-zero count.

- [ ] **Step 2: LAN** — repeat from a LAN host pointing at `http://${OTEL_COLLECTOR_LBIP}:4318` (OTLP/HTTP) with the `Authorization: Bearer` header; confirm rows land. (Wrong/missing token → `401`.)

- [ ] **Step 3: Off-LAN** — from off-LAN, POST OTLP/HTTP to `https://otel.${SECRET_DOMAIN}/v1/metrics` with both the `CF-Access-Client-Id`/`CF-Access-Client-Secret` headers and the `Authorization: Bearer` header; confirm rows land. Missing CF headers → `403` at the edge; missing bearer → `401` at the collector.

---

## Task 10: Grafana — InfluxDB 3 (SQL) datasource

**Files:**
- Modify: the Grafana datasources config (`kubernetes/apps/observability/grafana/app/helmrelease.yaml` — locate the existing `datasources` block or sidecar configMap)

- [ ] **Step 1: Inspect the current datasource wiring**
Run: `grep -rn "datasources\|InfluxDB\|influxdb" kubernetes/apps/observability/grafana/`
Determine whether datasources are inline in the HelmRelease or provisioned via labelled ConfigMaps (sidecar).

- [ ] **Step 2: Add an InfluxDB datasource in SQL/FlightSQL mode** pointing at InfluxDB 3, following whichever pattern Step 1 found. Key fields: type `influxdb`, the v3 SQL query language, URL `http://influxdb3.database.svc.cluster.local:8181`, database `dev-telemetry`, token auth via the secret.

> **Verify during impl:** the exact Grafana InfluxDB datasource JSON for v3 SQL
> (product/query-language fields) against current Grafana + InfluxDB 3 docs; v3
> uses SQL, not Flux. Token supplied via `secureJsonData`.

- [ ] **Step 3: Commit & reconcile**, then in Grafana confirm the datasource saves & "Test" passes and a sample `SELECT` against `dev-telemetry` returns the smoke rows.

---

## Task 11: First real load — point an AI CLI at the collector

- [ ] **Step 1: Configure Claude Code OTLP export** on the workstation/devpod env:
```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://${OTEL_COLLECTOR_LBIP}:4318   # LAN; or the in-cluster svc from the devpod
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <OTEL_BEARER_TOKEN>"
```
> Verify the current Claude Code telemetry env-var names against the Claude Code
> monitoring docs before relying on them.

- [ ] **Step 2: Run a short Claude Code session**, then confirm native metrics arrive:
```bash
kubectl -n database exec sts/influxdb3 -- influxdb3 query --database dev-telemetry --token "$TOKEN" \
  "SELECT * FROM \"claude_code.token.usage\" ORDER BY time DESC LIMIT 5"
```
Expected: token/cost rows present (exact measurement names per Claude Code's OTLP schema).

- [ ] **Step 3: Repeat for Codex CLI and Gemini CLI** using each tool's OTLP env knobs (verify each tool's telemetry docs). Confirm rows land tagged by tool/source.

---

## Task 12: Documentation & wrap-up

- [ ] **Step 1: Update the spec** with any field corrections discovered during impl (image digest, exporter mapping, chart keys) so the doc matches reality.
- [ ] **Step 2: Update** `.claude/session-journal.md` (Completed entry) and the infrastructure-roadmap `README.md` if it indexes items.
- [ ] **Step 3: Final commit**
```bash
git add docs/infrastructure-roadmap/otel-telemetry-backbone.md .claude/session-journal.md
git commit -m "docs(observability): reconcile OTel backbone spec with built reality"
```
- [ ] **Step 4: Open the home-ops PR** for `worktree-otel-life` → `main`.

---

## Notes / manual prerequisites (Gavin)

- **InfluxDB 3 Enterprise at-home license key** — email signup; the email goes in the 1Password `influxdb3` item (Task 2).
- **Cloudflare Access application + service token** for `otel.${SECRET_DOMAIN}` (Task 8) — done in Cloudflare Zero Trust.
- **A free LB IP** in `10.99.8.0/24` (Task 7).

## Out of scope (later specs)

Tempo + app instrumentation (spec 3), website exposure (spec 2), B2 cold-archive
lifecycle, retiring the WSL2 script (self-retires this weekend), retiring
kube-prometheus-stack (never).
