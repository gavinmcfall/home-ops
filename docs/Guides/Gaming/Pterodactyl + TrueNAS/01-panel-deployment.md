# Part 1: Deploying Pterodactyl Panel on Kubernetes

Deploy the Pterodactyl Panel using the bjw-s app-template Helm chart with GitOps.

---

## Step 1: Create the Database

Pterodactyl requires a MariaDB database. Add an init script to your MariaDB HelmRelease to create the database and user automatically.

**File: `kubernetes/apps/database/mariadb/app/helmrelease.yaml`**

Add to the `initdbScripts` section:

```yaml
initdbScripts:
  create-pterodactyl.sql: |
    CREATE DATABASE IF NOT EXISTS pterodactyl;
    CREATE USER IF NOT EXISTS 'pterodactyl'@'%' IDENTIFIED BY '${PTERODACTYL_MARIADB_PASSWORD}';
    GRANT ALL PRIVILEGES ON pterodactyl.* to 'pterodactyl'@'%';
    FLUSH PRIVILEGES;
```

> [!NOTE]
> Init scripts only run on first database initialization. If MariaDB is already deployed, you'll need to create the database manually:
> ```bash
> kubectl exec -it -n database mariadb-0 -- mysql -u root -p
> ```
> Then run the SQL commands above.

---

## Step 2: Create the Secret Store Entry

Add a secret to your secret manager (1Password, Vault, etc.) with the following fields:

| Field | Description | Example |
|-------|-------------|---------|
| `PTERODACTYL_APP_KEY` | Laravel encryption key | `base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `PTERODACTYL_MARIADB_PASSWORD` | Database password | (generate a strong password) |
| `MINIO_ACCESS_KEY` | MinIO access key for backups | (from MinIO) |
| `MINIO_SECRET_KEY` | MinIO secret key for backups | (from MinIO) |

> [!TIP]
> Generate the APP_KEY with: `echo "base64:$(openssl rand -base64 32)"`

---

## Step 3: Create the Directory Structure

```bash
mkdir -p kubernetes/apps/games/pterodactyl/app
```

---

## Step 4: Create the ExternalSecret

**File: `kubernetes/apps/games/pterodactyl/app/externalsecret.yaml`**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.nerdz.cloud/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pterodactyl
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: pterodactyl-secret
    template:
      engineVersion: v2
      data:
        # App
        APP_KEY: "{{ .PTERODACTYL_APP_KEY }}"
        APP_URL: https://pterodactyl.${SECRET_DOMAIN}
        APP_ENV: production
        APP_DEBUG: "false"
        APP_TIMEZONE: ${TIMEZONE}
        TRUSTED_PROXIES: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        CADDY_APP_URL: ":80"

        # Database
        DB_CONNECTION: mysql
        DB_HOST: mariadb.database.svc.cluster.local
        DB_PORT: "3306"
        DB_DATABASE: pterodactyl
        DB_USERNAME: pterodactyl
        DB_PASSWORD: "{{ .PTERODACTYL_MARIADB_PASSWORD }}"

        # Cache/Session/Queue via Redis (Dragonfly)
        CACHE_DRIVER: redis
        SESSION_DRIVER: redis
        QUEUE_CONNECTION: redis
        REDIS_HOST: dragonfly.database.svc.cluster.local
        REDIS_PORT: "6379"
        REDIS_PASSWORD: ""

        # S3 Backups (MinIO)
        APP_BACKUP_DRIVER: s3
        AWS_DEFAULT_REGION: us-east-1
        AWS_ACCESS_KEY_ID: "{{ .MINIO_ACCESS_KEY }}"
        AWS_SECRET_ACCESS_KEY: "{{ .MINIO_SECRET_KEY }}"
        AWS_BACKUPS_BUCKET: gameserver-backups
        AWS_ENDPOINT: http://citadel.internal:9000
        AWS_USE_PATH_STYLE_ENDPOINT: "true"

        # Mail (disabled for now)
        MAIL_MAILER: log
  dataFrom:
    - extract:
        key: pterodactyl
```

> [!IMPORTANT]
> - `CADDY_APP_URL: ":80"` is required — the container uses Caddy internally
> - `TRUSTED_PROXIES` must be CIDR notation, not `*`
> - Adjust `AWS_ENDPOINT` to match your MinIO server

---

## Step 5: Create the HelmRelease

**File: `kubernetes/apps/games/pterodactyl/app/helmrelease.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/common-4.4.0/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app pterodactyl
spec:
  chart:
    spec:
      chart: app-template
      version: 4.4.0
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  interval: 15m
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
    - name: dragonfly-operator
      namespace: database
    - name: mariadb
      namespace: database
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  driftDetection:
    mode: enabled
    ignore:
      - paths:
          - /spec/containers/resources/limits
        target:
          kind: Pod
  values:
    controllers:
      pterodactyl:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ccarney16/pterodactyl-panel
              tag: v1.12.0@sha256:0283aafa61190762f7b8da29e8a1f7bbd76dc4fc02efbbdf82f861470923bcb8
            envFrom:
              - secretRef:
                  name: pterodactyl-secret
            resources:
              requests:
                cpu: 50m
                memory: 256Mi
              limits:
                memory: 512Mi

    service:
      app:
        controller: *app
        ports:
          http:
            port: 80

    route:
      app:
        annotations:
          gethomepage.dev/enabled: "true"
          gethomepage.dev/group: Games
          gethomepage.dev/name: Pterodactyl
          gethomepage.dev/icon: pterodactyl
          gethomepage.dev/description: Game Server Management
          external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
        hostnames:
          - "{{ .Release.Name }}.${SECRET_DOMAIN}"
        parentRefs:
          - name: external
            namespace: network
            sectionName: https
        rules:
          - backendRefs:
              - identifier: app
                port: 80

    persistence:
      data:
        existingClaim: *app
        globalMounts:
          - path: /app/var
      logs:
        type: emptyDir
        globalMounts:
          - path: /app/storage/logs
```

---

## Step 6: Create the Kustomization Files

**File: `kubernetes/apps/games/pterodactyl/app/kustomization.yaml`**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - externalsecret.yaml
  - helmrelease.yaml
```

**File: `kubernetes/apps/games/pterodactyl/ks.yaml`**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.nerdz.cloud/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app pterodactyl
  namespace: &namespace games
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cluster-apps-rook-ceph-cluster
      namespace: rook-ceph
    - name: dragonfly-cluster
      namespace: database
    - name: mariadb
      namespace: database
  path: ./kubernetes/apps/games/pterodactyl/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  postBuild:
    substitute:
      APP: *app
      APP_UID: "1000"
      APP_GID: "1000"
      VOLSYNC_CAPACITY: 5Gi
      VOLSYNC_MINUTE: "30"
      VOLSYNC_STORAGECLASS: ${CLUSTER_STORAGE_BLOCK}
      VOLSYNC_SNAPSHOTCLASS: ${CLUSTER_SNAPSHOT_BLOCK}
      VOLSYNC_COPY_METHOD: Snapshot
```

---

## Step 7: Add to Namespace Kustomization

**File: `kubernetes/apps/games/kustomization.yaml`**

Add the Pterodactyl resource:

```yaml
resources:
  - ./pterodactyl/ks.yaml
```

---

## Step 8: Deploy via GitOps

```bash
git add kubernetes/apps/games/pterodactyl/
git commit -m "feat(games): deploy pterodactyl panel"
git push
```

Wait for Flux to reconcile:

```bash
flux reconcile kustomization pterodactyl --with-source
```

---

## Step 9: Initial Panel Setup

Once the pod is running:

1. Visit `https://pterodactyl.${SECRET_DOMAIN}`
2. Create your admin account
3. Configure your first Location (e.g., "Home Lab")

**Checkpoint:** You can access the Panel and create a location.

---

## Troubleshooting {#panel-troubleshooting}

### Database Connection Failed

**Symptoms:** Panel shows database error on startup

**Check database exists:**
```bash
kubectl exec -it -n database mariadb-0 -- mysql -u root -p -e "SHOW DATABASES;"
```

**Check user permissions:**
```bash
kubectl exec -it -n database mariadb-0 -- mysql -u root -p -e "SHOW GRANTS FOR 'pterodactyl'@'%';"
```

### Redis/Dragonfly Connection Failed

**Check Dragonfly is running:**
```bash
kubectl get pods -n database -l app.kubernetes.io/name=dragonfly
```

**Test connectivity from Panel pod:**
```bash
kubectl exec -it -n games deploy/pterodactyl -- nc -zv dragonfly.database.svc.cluster.local 6379
```

### 500 Server Error

Enable debug mode temporarily:

```bash
kubectl set env deploy/pterodactyl -n games APP_DEBUG=true
kubectl logs -n games deploy/pterodactyl -f
```

Remember to disable debug after resolving:
```bash
kubectl set env deploy/pterodactyl -n games APP_DEBUG=false
```

---

## Next Steps

With the Panel running, proceed to [Part 2: Wings Setup](./02-wings-truenas.md) to deploy the Wings daemon on TrueNAS.
