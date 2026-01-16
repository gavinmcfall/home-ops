# Part 1: Deploying Pelican Panel on Kubernetes

Deploy the Pelican Panel using the bjw-s app-template Helm chart with GitOps.

> [!NOTE]
> Pelican is the community-driven successor to Pterodactyl. The official image is `ghcr.io/pelican-dev/panel`.

---

## Step 1: Create the Database

Pelican requires a MariaDB database. Add an init script to your MariaDB HelmRelease to create the database and user automatically.

**File: `kubernetes/apps/database/mariadb/app/helmrelease.yaml`**

Add to the `initdbScripts` section:

```yaml
initdbScripts:
  create-pelican.sql: |
    CREATE DATABASE IF NOT EXISTS pelican;
    CREATE USER IF NOT EXISTS 'pelican'@'%' IDENTIFIED BY '${PELICAN_MARIADB_PASSWORD}';
    GRANT ALL PRIVILEGES ON pelican.* to 'pelican'@'%';
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
| `PELICAN_APP_KEY` | Laravel encryption key | `base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `PELICAN_MARIADB_PASSWORD` | Database password | (generate a strong password) |
| `PELICAN_ADMIN_EMAIL` | Admin email for mail from address | `admin@example.com` |
| `MINIO_ACCESS_KEY` | MinIO access key for backups | (from MinIO) |
| `MINIO_SECRET_KEY` | MinIO secret key for backups | (from MinIO) |

> [!TIP]
> Generate the APP_KEY with: `echo "base64:$(openssl rand -base64 32)"`

---

## Step 3: Create the Directory Structure

```bash
mkdir -p kubernetes/apps/games/pelican/app
```

---

## Step 4: Create the ExternalSecret

**File: `kubernetes/apps/games/pelican/app/externalsecret.yaml`**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.nerdz.cloud/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pelican
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: pelican-secret
    template:
      engineVersion: v2
      data:
        # App
        APP_KEY: "{{ .PELICAN_APP_KEY }}"
        APP_URL: https://pelican.${SECRET_DOMAIN}
        APP_ENV: production
        APP_DEBUG: "false"
        APP_TIMEZONE: ${TIMEZONE}
        TRUSTED_PROXIES: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        BEHIND_PROXY: "true"

        # Database
        DB_CONNECTION: mysql
        DB_HOST: mariadb.database.svc.cluster.local
        DB_PORT: "3306"
        DB_DATABASE: pelican
        DB_USERNAME: pelican
        DB_PASSWORD: "{{ .PELICAN_MARIADB_PASSWORD }}"

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

        # Mail via smtp-relay
        MAIL_MAILER: smtp
        MAIL_HOST: smtp-relay.home.svc.cluster.local
        MAIL_PORT: "25"
        MAIL_USERNAME: ""
        MAIL_PASSWORD: ""
        MAIL_ENCRYPTION: "null"
        MAIL_FROM_ADDRESS: "{{ .PELICAN_ADMIN_EMAIL }}"
        MAIL_FROM_NAME: Pelican
  dataFrom:
    - extract:
        key: pelican
```

> [!IMPORTANT]
> - `BEHIND_PROXY: "true"` tells Pelican it's behind a reverse proxy
> - `TRUSTED_PROXIES` must be CIDR notation, not `*`
> - Adjust `AWS_ENDPOINT` to match your MinIO server

---

## Step 5: Create the HelmRelease

**File: `kubernetes/apps/games/pelican/app/helmrelease.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/common-4.4.0/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app pelican
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
      pelican:
        annotations:
          reloader.stakater.com/auto: "true"
        initContainers:
          init-plugins:
            image:
              repository: ghcr.io/pelican-dev/panel
              tag: v1.0.0-beta30@sha256:aec08833e40b54e773cae68945d81f42561d176244032e33c152a92ebd0e0deb
            command:
              - /bin/sh
              - -c
              - |
                set -e
                # Ensure plugins dir has correct permissions
                mkdir -p /pelican-data/plugins
                chown www-data:www-data /pelican-data/plugins
                chmod 775 /pelican-data/plugins
                echo "Plugins directory ready"
            securityContext:
              runAsUser: 0
              runAsGroup: 0
        containers:
          app:
            image:
              repository: ghcr.io/pelican-dev/panel
              tag: v1.0.0-beta30@sha256:aec08833e40b54e773cae68945d81f42561d176244032e33c152a92ebd0e0deb
            env:
              XDG_DATA_HOME: /pelican-data
            envFrom:
              - secretRef:
                  name: pelican-secret
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
          gethomepage.dev/name: Pelican
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
        advancedMounts:
          pelican:
            init-plugins:
              - path: /pelican-data
            app:
              - path: /pelican-data
              - path: /var/www/html/plugins
                subPath: plugins
      logs:
        type: emptyDir
        globalMounts:
          - path: /var/www/html/storage/logs
```

> [!IMPORTANT]
> **Known Issue:** The official Pelican Docker image has a broken symlink for plugins:
> - `/var/www/html/plugins/plugins` → `/pelican-data/plugins` (nested incorrectly)
> - Should be `/var/www/html/plugins` → `/pelican-data/plugins`
>
> The workaround mounts the PVC directly to `/var/www/html/plugins` via subPath.
> This issue is tracked in [pelican-dev/panel#2063](https://github.com/pelican-dev/panel/pull/2063).

---

## Step 6: Create the Kustomization Files

**File: `kubernetes/apps/games/pelican/app/kustomization.yaml`**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - externalsecret.yaml
  - helmrelease.yaml
```

**File: `kubernetes/apps/games/pelican/ks.yaml`**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.nerdz.cloud/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app pelican
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
  path: ./kubernetes/apps/games/pelican/app
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

Add the Pelican resource:

```yaml
resources:
  - ./pelican/ks.yaml
```

---

## Step 8: Deploy via GitOps

```bash
git add kubernetes/apps/games/pelican/
git commit -m "feat(games): deploy pelican panel"
git push
```

Wait for Flux to reconcile:

```bash
flux reconcile kustomization pelican --with-source
```

---

## Step 9: Initial Panel Setup

Once the pod is running:

1. Visit `https://pelican.${SECRET_DOMAIN}`
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
kubectl exec -it -n database mariadb-0 -- mysql -u root -p -e "SHOW GRANTS FOR 'pelican'@'%';"
```

### Redis/Dragonfly Connection Failed

**Check Dragonfly is running:**
```bash
kubectl get pods -n database -l app.kubernetes.io/name=dragonfly
```

**Test connectivity from Panel pod:**
```bash
kubectl exec -it -n games deploy/pelican -- nc -zv dragonfly.database.svc.cluster.local 6379
```

### 500 Server Error

Enable debug mode temporarily:

```bash
kubectl set env deploy/pelican -n games APP_DEBUG=true
kubectl logs -n games deploy/pelican -f
```

Remember to disable debug after resolving:
```bash
kubectl set env deploy/pelican -n games APP_DEBUG=false
```

### Plugins Not Loading

**Check plugin directory permissions:**
```bash
kubectl exec -n games deploy/pelican -- ls -la /var/www/html/plugins/
```

**Verify PVC mount:**
```bash
kubectl exec -n games deploy/pelican -- ls -la /pelican-data/plugins/
```

---

## Next Steps

With the Panel running, proceed to [Part 2: Wings Setup](./02-wings-truenas.md) to deploy the Wings daemon on TrueNAS.
