# CloudNativePG: Dual-Destination Backups with pgBackRest

This guide walks you through setting up a dedicated PostgreSQL cluster for Immich using CloudNativePG with the pgBackRest plugin for true dual-destination backups to both Backblaze B2 and Cloudflare R2.

## What You'll Learn

- How to deploy the pgBackRest plugin for CloudNativePG
- Creating a dedicated PostgreSQL 18 cluster for Immich
- Configuring dual S3 repositories (B2 + R2)
- Setting up scheduled backups to both destinations
- Understanding pgBackRest's multi-repository behavior

> [!NOTE]
> **GitOps Workflow**: This guide follows GitOps practices. All changes are made by editing files in Git and pushing to trigger Flux reconciliation—never by running `kubectl apply` directly.

---

## Understanding the Architecture

### Why pgBackRest Instead of Barman?

CloudNativePG's default backup plugin is Barman Cloud. It works well for single-destination backups, but has a critical limitation: the `barmanObjectName` parameter in ScheduledBackup is [ignored](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/611). This means you can't have scheduled backups go to different ObjectStores.

pgBackRest solves this with native multi-repository support:
- **WAL archiving**: Pushes to ALL configured repositories simultaneously
- **Full backups**: Target specific repositories using the `selectedRepository` parameter

### The Backup Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                    PostgreSQL Cluster (immich18)                  │
│                         3 instances                               │
└───────────────────────────┬──────────────────────────────────────┘
                            │
              pgBackRest Plugin (sidecar)
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
       ┌──────────────┐           ┌──────────────┐
       │ Backblaze B2 │           │Cloudflare R2 │
       │   (repo1)    │           │   (repo2)    │
       └──────────────┘           └──────────────┘
              │                           │
              └───────────┬───────────────┘
                          │
           WAL archives to BOTH repos simultaneously
           Full backups targeted to specific repo
```

---

## Before You Begin

### Prerequisites

- [ ] CloudNativePG operator installed in the `database` namespace
- [ ] cert-manager installed and functioning
- [ ] External Secrets operator with a working ClusterSecretStore
- [ ] S3 credentials for both Backblaze B2 and Cloudflare R2
- [ ] A 1Password item (or equivalent) with the required secrets

### Required Secrets

The ExternalSecret pulls from multiple 1Password items. Ensure these fields exist:

| 1Password Item | Field | Description |
|----------------|-------|-------------|
| `cloudnative-pg` | `POSTGRES_SUPER_USER` | PostgreSQL admin username |
| `cloudnative-pg` | `POSTGRES_SUPER_PASS` | PostgreSQL admin password |
| `backblaze` | `IMMICH_B2_ACCESS_KEY` | Backblaze B2 application key ID |
| `backblaze` | `IMMICH_B2_SECRET_ACCESS_KEY` | Backblaze B2 application key |
| `cloudflare` | `IMMICH_R2_ACCESS_KEY` | Cloudflare R2 access key ID |
| `cloudflare` | `IMMICH_R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret access key |
| `cloudflare` | `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID (for R2 endpoint) |
| `immich` | `IMMICH_PG_BACKUP_R2_BUCKET` | R2 bucket name for Flux substitution |

### Required S3 Buckets

Create these buckets (they can have the same name in both providers):

| Provider | Bucket Name | Region |
|----------|-------------|--------|
| Backblaze B2 | `nerdz-immich-postgres` | `us-east-005` (or your region) |
| Cloudflare R2 | `nerdz-immich-postgres` | `auto` |

---

## Part 1: Deploy the pgBackRest Plugin

The pgBackRest plugin requires several Kubernetes resources. Create these in `kubernetes/apps/database/cloudnative-pg/pgbackrest/`.

### Directory Structure

```
kubernetes/apps/database/cloudnative-pg/pgbackrest/
├── kustomization.yaml
├── crd.yaml           # Repository CRD from Dalibo
├── rbac.yaml          # ServiceAccount, ClusterRole, RoleBinding
├── certificate.yaml   # Self-signed TLS for plugin communication
├── deployment.yaml    # The pgBackRest controller
└── service.yaml       # Exposes controller to CNPG operator
```

### Step 1.1: Create the Kustomization

```yaml
# kubernetes/apps/database/cloudnative-pg/pgbackrest/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: database
resources:
  - ./crd.yaml
  - ./rbac.yaml
  - ./certificate.yaml
  - ./deployment.yaml
  - ./service.yaml
```

### Step 1.2: Download the CRD

Get the latest Repository CRD from the Dalibo project:

```bash
curl -sL https://raw.githubusercontent.com/dalibo/cnpg-plugin-pgbackrest/main/config/crd/bases/pgbackrest.dalibo.com_repositories.yaml \
  > kubernetes/apps/database/cloudnative-pg/pgbackrest/crd.yaml
```

### Step 1.3: Create RBAC Resources

```yaml
# kubernetes/apps/database/cloudnative-pg/pgbackrest/rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pgbackrest-controller
  namespace: database
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pgbackrest-controller
rules:
  - apiGroups: [""]
    resources: [secrets]
    verbs: [create, delete, get, list, watch]
  - apiGroups: [pgbackrest.dalibo.com]
    resources: [repositories, repositories/finalizers, repositories/status]
    verbs: [create, delete, get, list, patch, update, watch]
  - apiGroups: [postgresql.cnpg.io]
    resources: [backups, clusters/finalizers]
    verbs: [get, list, watch, update]
  - apiGroups: [rbac.authorization.k8s.io]
    resources: [rolebindings, roles]
    verbs: [create, get, list, patch, update, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pgbackrest-controller-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pgbackrest-controller
subjects:
  - kind: ServiceAccount
    name: pgbackrest-controller
    namespace: database
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pgbackrest-leader-election
  namespace: database
rules:
  - apiGroups: [""]
    resources: [configmaps]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [coordination.k8s.io]
    resources: [leases]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [events]
    verbs: [create, patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pgbackrest-leader-election-binding
  namespace: database
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pgbackrest-leader-election
subjects:
  - kind: ServiceAccount
    name: pgbackrest-controller
    namespace: database
```

### Step 1.4: Create TLS Certificates

CloudNativePG plugins communicate over mTLS. We use a self-signed issuer:

```yaml
# kubernetes/apps/database/cloudnative-pg/pgbackrest/certificate.yaml
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: pgbackrest-selfsigned-issuer
  namespace: database
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pgbackrest-controller-client
  namespace: database
spec:
  commonName: pgbackrest-controller-client
  duration: 2160h
  isCA: false
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: pgbackrest-selfsigned-issuer
  renewBefore: 360h
  secretName: pgbackrest-controller-client-tls
  usages:
    - client auth
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pgbackrest-controller-server
  namespace: database
spec:
  commonName: cnpg-pgbackrest
  dnsNames:
    - cnpg-pgbackrest
    - cnpg-pgbackrest.database
    - cnpg-pgbackrest.database.svc
    - cnpg-pgbackrest.database.svc.cluster.local
  duration: 2160h
  isCA: false
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: pgbackrest-selfsigned-issuer
  renewBefore: 360h
  secretName: pgbackrest-controller-server-tls
  usages:
    - server auth
```

### Step 1.5: Create the Controller Deployment

```yaml
# kubernetes/apps/database/cloudnative-pg/pgbackrest/deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: pgbackrest-controller
  name: pgbackrest-controller
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgbackrest-controller
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: pgbackrest-controller
    spec:
      containers:
        - name: pgbackrest-controller
          image: registry.hub.docker.com/dalibo/cnpg-pgbackrest-controller:latest
          imagePullPolicy: IfNotPresent
          args:
            - operator
            - --server-cert=/server/tls.crt
            - --server-key=/server/tls.key
            - --client-cert=/client/tls.crt
            - --server-address=:9090
            - --log-level=debug
          env:
            - name: SIDECAR_IMAGE
              value: registry.hub.docker.com/dalibo/cnpg-pgbackrest-sidecar:latest
          ports:
            - containerPort: 9090
              protocol: TCP
          readinessProbe:
            initialDelaySeconds: 10
            periodSeconds: 10
            tcpSocket:
              port: 9090
          resources:
            requests:
              cpu: 10m
              memory: 64Mi
            limits:
              memory: 256Mi
          volumeMounts:
            - mountPath: /server
              name: server
            - mountPath: /client
              name: client
      serviceAccountName: pgbackrest-controller
      volumes:
        - name: server
          secret:
            secretName: pgbackrest-controller-server-tls
        - name: client
          secret:
            secretName: pgbackrest-controller-client-tls
```

### Step 1.6: Create the Service

> [!IMPORTANT]
> The service MUST be named `cnpg-pgbackrest`, NOT `pgbackrest`. Kubernetes creates environment variables like `PGBACKREST_SERVICE_HOST` for services, and pgBackRest interprets any `PGBACKREST_*` variable as configuration, causing JSON parsing errors.

```yaml
# kubernetes/apps/database/cloudnative-pg/pgbackrest/service.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: cnpg-pgbackrest
  namespace: database
  labels:
    app: pgbackrest-controller
    cnpg.io/pluginName: pgbackrest.dalibo.com
  annotations:
    cnpg.io/pluginClientSecret: pgbackrest-controller-client-tls
    cnpg.io/pluginServerSecret: pgbackrest-controller-server-tls
    cnpg.io/pluginPort: "9090"
spec:
  ports:
    - port: 9090
      protocol: TCP
      targetPort: 9090
  selector:
    app: pgbackrest-controller
```

### Step 1.7: Add the Flux Kustomization

Add the pgBackRest kustomization to your main `ks.yaml`:

```yaml
# kubernetes/apps/database/cloudnative-pg/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cloudnative-pg-pgbackrest
  namespace: database
spec:
  targetNamespace: database
  commonMetadata:
    labels:
      app.kubernetes.io/name: cloudnative-pg-pgbackrest
  dependsOn:
    - name: cloudnative-pg
      namespace: database
    - name: cert-manager
      namespace: cert-manager
  path: ./kubernetes/apps/database/cloudnative-pg/pgbackrest
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

---

## Part 2: Create the Immich PostgreSQL Cluster

### Directory Structure

```
kubernetes/apps/database/cloudnative-pg/immich18/
├── kustomization.yaml
├── externalsecret.yaml
├── repository.yaml      # pgBackRest Repository CR
├── cluster.yaml         # PostgreSQL cluster definition
├── pooler.yaml          # PgBouncer connection pooler
├── scheduledbackup.yaml # Two backups, one per destination
└── service.yaml         # LoadBalancer service
```

### Step 2.1: Create the Kustomization

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./repository.yaml
  - ./cluster.yaml
  - ./pooler.yaml
  - ./scheduledbackup.yaml
  - ./service.yaml
```

### Step 2.2: Create the ExternalSecret

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/externalsecret.yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: immich-cnpg
  namespace: database
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: immich-cnpg-secret
    template:
      engineVersion: v2
      metadata:
        labels:
          cnpg.io/reload: "true"
      data:
        username: "{{ .POSTGRES_SUPER_USER }}"
        password: "{{ .POSTGRES_SUPER_PASS }}"
        # Backblaze B2 credentials
        b2-access-key-id: "{{ .IMMICH_B2_ACCESS_KEY }}"
        b2-secret-access-key: "{{ .IMMICH_B2_SECRET_ACCESS_KEY }}"
        # Cloudflare R2 credentials
        r2-access-key-id: "{{ .IMMICH_R2_ACCESS_KEY }}"
        r2-secret-access-key: "{{ .IMMICH_R2_SECRET_ACCESS_KEY }}"
        # Bucket and account info for Flux substitution
        IMMICH_PG_BACKUP_R2_BUCKET: "{{ .IMMICH_PG_BACKUP_R2_BUCKET }}"
        CLOUDFLARE_ACCOUNT_ID: "{{ .CLOUDFLARE_ACCOUNT_ID }}"
  dataFrom:
    - extract:
        key: cloudnative-pg
    - extract:
        key: backblaze
    - extract:
        key: cloudflare
    - extract:
        key: immich
```

### Step 2.3: Create the pgBackRest Repository

This defines both S3 destinations:

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/repository.yaml
---
apiVersion: pgbackrest.dalibo.com/v1
kind: Repository
metadata:
  name: immich18-repository
  namespace: database
spec:
  repoConfiguration:
    stanza: immich18
    archive:
      async: true
      getQueueMax: 128MiB
      pushQueueMax: 1GiB
    processMax: 4
    s3Repositories:
      # Repository 1: Backblaze B2
      - bucket: nerdz-immich-postgres
        endpoint: s3.us-east-005.backblazeb2.com
        region: us-east-005
        repoPath: /immich18
        uriStyle: path
        verifyTLS: true
        retentionPolicy:
          full: 14
          fullType: count
          diff: 30
          archive: 7
          archiveType: full
          history: 30
        secretRef:
          accessKeyId:
            name: immich-cnpg-secret
            key: b2-access-key-id
          secretAccessKey:
            name: immich-cnpg-secret
            key: b2-secret-access-key
      # Repository 2: Cloudflare R2 (use Flux variable substitution)
      - bucket: ${IMMICH_PG_BACKUP_R2_BUCKET}
        endpoint: ${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com
        region: auto
        repoPath: /immich18
        uriStyle: path
        verifyTLS: true
        retentionPolicy:
          full: 14
          fullType: count
          diff: 30
          archive: 7
          archiveType: full
          history: 30
        secretRef:
          accessKeyId:
            name: immich-cnpg-secret
            key: r2-access-key-id
          secretAccessKey:
            name: immich-cnpg-secret
            key: r2-secret-access-key
```

> [!NOTE]
> The R2 bucket and endpoint use Flux variable substitution. Ensure your ExternalSecret includes `IMMICH_PG_BACKUP_R2_BUCKET` and `CLOUDFLARE_ACCOUNT_ID` fields, and your Kustomization has `substituteFrom` configured to reference the secret.

### Step 2.4: Create the Cluster

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/cluster.yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: immich18
  namespace: database
spec:
  instances: 3
  imageName: ghcr.io/tensorchord/cloudnative-pgvecto.rs:16-v0.4.0
  primaryUpdateStrategy: unsupervised

  storage:
    size: 20Gi
    storageClass: ceph-block

  superuserSecret:
    name: immich-cnpg-secret

  postgresql:
    shared_preload_libraries:
      - "vectors.so"
    parameters:
      max_connections: "500"
      shared_buffers: "256MB"

  # pgBackRest plugin configuration
  plugins:
    - name: pgbackrest.dalibo.com
      parameters:
        repositoryRef: immich18-repository

  resources:
    requests:
      memory: "512Mi"
      cpu: "100m"
    limits:
      memory: "2Gi"
```

### Step 2.5: Create the Pooler (Optional)

PgBouncer pooler for connection management:

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/pooler.yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: immich18-pooler
  namespace: database
spec:
  cluster:
    name: immich18
  instances: 2
  type: rw
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "1000"
      default_pool_size: "25"
```

### Step 2.6: Create the ScheduledBackups

> [!IMPORTANT]
> Create TWO ScheduledBackups—one for each repository. Use the `selectedRepository` parameter to target specific repos. The schedules are offset by 1 hour to avoid concurrent backup operations.

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/scheduledbackup.yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: immich18-daily-b2
  namespace: database
spec:
  schedule: "0 3 * * *"    # 3 AM daily
  immediate: true
  backupOwnerReference: self
  method: plugin
  target: primary          # REQUIRED for pgBackRest
  cluster:
    name: immich18
  pluginConfiguration:
    name: pgbackrest.dalibo.com
    parameters:
      selectedRepository: "1"    # Backblaze B2
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: immich18-daily-r2
  namespace: database
spec:
  schedule: "0 4 * * *"    # 4 AM daily (1 hour offset)
  immediate: false
  backupOwnerReference: self
  method: plugin
  target: primary          # REQUIRED for pgBackRest
  cluster:
    name: immich18
  pluginConfiguration:
    name: pgbackrest.dalibo.com
    parameters:
      selectedRepository: "2"    # Cloudflare R2
```

> [!CAUTION]
> The `target: primary` is **required**. pgBackRest cannot run backups from replica nodes without SSH access to the primary. Without this setting, you'll get "unable to find primary cluster" errors.

### Step 2.7: Create the LoadBalancer Service

```yaml
# kubernetes/apps/database/cloudnative-pg/immich18/service.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: immich18-lb
  namespace: database
  annotations:
    io.cilium/lb-ipam-ips: "10.90.3.211"    # Your IP here
spec:
  type: LoadBalancer
  ports:
    - port: 5432
      targetPort: 5432
      protocol: TCP
  selector:
    cnpg.io/cluster: immich18
    role: primary
```

### Step 2.8: Add the Flux Kustomization

Add the immich18 cluster to your `ks.yaml`:

```yaml
# kubernetes/apps/database/cloudnative-pg/ks.yaml (add this)
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cloudnative-pg-immich18
  namespace: database
spec:
  targetNamespace: database
  commonMetadata:
    labels:
      app.kubernetes.io/name: cloudnative-pg-immich18
  dependsOn:
    - name: cloudnative-pg
      namespace: database
    - name: cloudnative-pg-pgbackrest
      namespace: database
    - name: external-secrets-stores
      namespace: external-secrets
  path: ./kubernetes/apps/database/cloudnative-pg/immich18
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-settings
      - kind: Secret
        name: immich-cnpg-secret
```

---

## Part 3: Commit and Deploy

### Step 3.1: Commit All Changes

```bash
cd /home/gavin/home-ops

git add kubernetes/apps/database/cloudnative-pg/
git commit -m "feat(immich): add dedicated PostgreSQL cluster with pgBackRest dual backups

- Deploy pgBackRest controller with TLS certificates
- Create immich18 cluster with PostgreSQL 18 + pgvecto.rs
- Configure dual S3 repositories (B2 + R2)
- Set up daily backups to both destinations"

git push
```

### Step 3.2: Watch the Deployment

```bash
# Watch Flux apply the changes
flux get kustomizations -w

# Or force immediate reconciliation
flux reconcile kustomization cloudnative-pg-pgbackrest -n flux-system --with-source
flux reconcile kustomization cloudnative-pg-immich18 -n flux-system --with-source
```

### Step 3.3: Verify Plugin Deployment

```bash
# Check pgBackRest controller is running
kubectl get pods -n database -l app=pgbackrest-controller

# Check certificates were created
kubectl get certificate -n database | grep pgbackrest

# Check the service
kubectl get svc -n database cnpg-pgbackrest
```

### Step 3.4: Verify Cluster Deployment

```bash
# Check cluster status
kubectl get cluster -n database immich18

# Check all pods are running
kubectl get pods -n database -l cnpg.io/cluster=immich18

# Check the repository status
kubectl get repository -n database immich18-repository -o yaml
```

---

## Part 4: Test Backups

### Step 4.1: Trigger a Manual Backup to B2

```bash
kubectl create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: immich18-test-b2
  namespace: database
spec:
  cluster:
    name: immich18
  method: plugin
  target: primary
  pluginConfiguration:
    name: pgbackrest.dalibo.com
    parameters:
      selectedRepository: "1"
EOF
```

### Step 4.2: Watch Backup Progress

```bash
# Check backup status
kubectl get backup -n database immich18-test-b2 -w

# Check logs from the primary pod
kubectl logs -n database -l cnpg.io/cluster=immich18,role=primary --all-containers -f | grep -i backup
```

### Step 4.3: Trigger a Manual Backup to R2

```bash
kubectl create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: immich18-test-r2
  namespace: database
spec:
  cluster:
    name: immich18
  method: plugin
  target: primary
  pluginConfiguration:
    name: pgbackrest.dalibo.com
    parameters:
      selectedRepository: "2"
EOF
```

### Step 4.4: Verify Files in Both Buckets

```bash
# Check B2
aws s3 ls s3://nerdz-immich-postgres/immich18/ --profile backblaze-b2 --recursive | wc -l

# Check R2
aws s3 ls s3://nerdz-immich-postgres/immich18/ --profile cloudflare-r2 --region auto --recursive | wc -l
```

Both should show files. B2 and R2 should each have:
- `archive/` - WAL files (both repos get these automatically)
- `backup/` - Full backup files (targeted by repository number)

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Controller stuck acquiring lease | Barman plugin holding lease | Suspend Barman HelmRelease and scale down |
| "can't parse pgbackrest JSON" | Service named `pgbackrest` | Rename service to `cnpg-pgbackrest` |
| "unable to find primary cluster" | Backup running on replica | Add `target: primary` to ScheduledBackup |
| Backup only in repo1 | Using wrong parameter name | Use `selectedRepository`, not `repo` |
| Certificate errors | Wrong dnsNames | Ensure dnsNames match service name |

### Checking Controller Logs

```bash
kubectl logs -n database deploy/pgbackrest-controller --tail=100
```

### Checking WAL Archiving

WAL archiving logs appear in the postgres container:

```bash
kubectl logs -n database -l cnpg.io/cluster=immich18,role=primary -c postgres --tail=50 | grep -i "archive-push"
```

### Verifying Repository Status

```bash
kubectl get repository -n database immich18-repository -o yaml | grep -A20 "status:"
```

The status should show `recoveryWindow` with backup information.

---

## Quick Reference

### Key Resources

| Resource | Purpose |
|----------|---------|
| `Repository` | Defines S3 destinations and retention policies |
| `Cluster.spec.plugins` | Connects cluster to pgBackRest plugin |
| `ScheduledBackup` | Schedules backups with target repository |
| `Backup` | Manual one-time backup |

### pgBackRest Multi-Repository Behavior

| Operation | Behavior |
|-----------|----------|
| WAL archiving | Pushes to ALL repositories automatically |
| Full backup | Targets ONE repository (defaults to repo1) |
| `selectedRepository: "2"` | Forces backup to repo2 |

### Common Commands

```bash
# Check backup status
kubectl get backup -n database

# Check scheduled backup status
kubectl get scheduledbackup -n database

# Check repository status
kubectl get repository -n database

# Force backup to specific repo
kubectl create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-backup-$(date +%s)
  namespace: database
spec:
  cluster:
    name: immich18
  method: plugin
  target: primary
  pluginConfiguration:
    name: pgbackrest.dalibo.com
    parameters:
      selectedRepository: "1"    # or "2" for R2
EOF
```

---

## Lessons Learned

| Issue | Wrong | Correct |
|-------|-------|---------|
| Service name | `pgbackrest` | `cnpg-pgbackrest` |
| Backup target | (default - replica) | `target: primary` |
| Repository parameter | `repo: "2"` | `selectedRepository: "2"` |
| Plugin namespace | `cnpg-system` | `database` (match your operator) |
| Leader lease | Both plugins running | Disable Barman first |

---

## Further Reading

- [Dalibo pgBackRest Plugin](https://github.com/dalibo/cnpg-plugin-pgbackrest)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [pgBackRest Documentation](https://pgbackrest.org/)
- [Barman Cloud Plugin Issue #611](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/611)
