# Kustomize Components: Reusable Configurations in GitOps

A beginner-friendly guide to understanding and using Kustomize Components for shared configurations like Volsync backups, Gatus monitoring, and KEDA scaling.

---

## What You'll Learn

By the end of this guide, you will understand:

- ✅ What Kustomize Components are and why they exist
- ✅ How components differ from regular Kustomize resources
- ✅ How to use existing components in your apps
- ✅ How to create new components
- ✅ How variable substitution works with Flux

---

## Understanding the Problem

### The Challenge: Shared Configurations

In a GitOps homelab, many apps need similar configurations:
- **Volsync backups** - Most apps need PVCs and ReplicationSources
- **Gatus monitoring** - Apps need endpoint monitoring
- **KEDA scaling** - Some apps need NFS availability checks

Without a reuse pattern, you'd copy-paste the same YAML into every app. That means:
- Updating 30 files when you change a backup destination
- Inconsistency when someone forgets to update one app
- Bloated repositories with duplicated code

### The Solution: Kustomize Components

**Components** are a Kustomize feature that lets you create reusable configuration "modules" that can be mixed into any app.

```
Before: Copy backup YAML into every app
After:  Reference a shared component, pass app-specific values
```

> [!TIP]
> Think of components like functions in programming. You define the logic once, then call it with different parameters for each app.

---

## How Components Work

### Regular Kustomize Resources vs Components

**Regular resources** (what you're used to):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./externalsecret.yaml
```

**Components** (reusable modules):
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component  # <-- Different kind!
resources:
  - ./replicationsource.yaml
  - ./pvc.yaml
```

The key difference: Components use `kind: Component` and can be included in multiple places.

### Including Components in Your App

In your app's `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
components:                          # <-- Special field for components
  - ../../../../components/volsync
  - ../../../../components/gatus/guarded
```

### Variable Substitution with Flux

Components use variables like `${APP}` that Flux fills in at deploy time:

**In the component** (`components/volsync/nfs-truenas/pvc.yaml`):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP}              # Placeholder
spec:
  resources:
    requests:
      storage: ${VOLSYNC_CAPACITY}  # Placeholder
```

**In your app's ks.yaml**:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: paperless
spec:
  path: ./kubernetes/apps/home/paperless/app
  postBuild:
    substitute:
      APP: paperless        # Value for ${APP}
      VOLSYNC_CAPACITY: 20Gi # Value for ${VOLSYNC_CAPACITY}
```

> [!NOTE]
> The `postBuild.substitute` block is where Flux replaces `${VAR}` placeholders with actual values.

---

## Your Current Components

Your repository has these reusable components:

```
kubernetes/components/
├── common/               # Namespace, cluster-vars, alerts, sops
├── gatus/                # Gatus monitoring
│   ├── external/         # For internet-accessible apps
│   ├── guarded/          # For internal-only apps
│   └── infrastructure/   # For infra services
├── keda/
│   └── nfs-scaler/       # Scale pods based on NFS availability
├── volsync/              # Backup system
│   ├── nfs-truenas/      # → TrueNAS NFS repository
│   ├── s3-backblaze/     # → Backblaze B2
│   └── s3-cloudflare/    # → Cloudflare R2
└── volsync-migrate/      # Migration helper
```

### Component Descriptions

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `volsync` | Creates PVC + backups to all destinations | Most apps with persistent data |
| `gatus/guarded` | Internal monitoring endpoint | Apps behind internal gateway |
| `gatus/external` | External monitoring endpoint | Apps exposed to internet |
| `keda/nfs-scaler` | Scale to 0 when NFS unavailable | Apps using NFS mounts |

---

## Part 1: Adding Volsync to an App

This is the most common use case - adding backups to a new app.

### Step 1.1: Understand What You Need

For Volsync to work, your app needs:
1. A PVC (created by the component)
2. A ReplicationSource (created by the component)
3. Variables passed via `postBuild.substitute`

### Step 1.2: Update Your App's kustomization.yaml

**File:** `kubernetes/apps/<namespace>/<app>/app/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./externalsecret.yaml  # If your app needs secrets
components:
  - ../../../../components/volsync  # Add this line
```

### Step 1.3: Add Variables to Your ks.yaml

**File:** `kubernetes/apps/<namespace>/<app>/ks.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  namespace: &namespace myns
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cluster-apps-rook-ceph-cluster
      namespace: rook-ceph
    - name: volsync
      namespace: storage
  path: ./kubernetes/apps/myns/myapp/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  interval: 30m
  postBuild:
    substitute:
      APP: myapp              # Required - names your PVC and backups
      VOLSYNC_CAPACITY: 10Gi  # Required - PVC size
```

> [!IMPORTANT]
> The `dependsOn` section ensures Volsync and Ceph are ready before your app deploys. Without this, the PVC creation might fail.

### Step 1.4: Update Your HelmRelease to Use the PVC

**File:** `kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml`

```yaml
# In your values section:
persistence:
  config:
    existingClaim: myapp  # Must match ${APP}
```

### Step 1.5: Deploy via GitOps

```bash
cd ~/home-ops
git add kubernetes/apps/myns/myapp/
git commit -m "feat(myapp): add volsync backup component

Pair-programmed with Claude Code - https://claude.com/claude-code

Co-Authored-By: Claude <noreply@anthropic.com>
Co-Authored-By: Gavin <gavin@nerdz.cloud>"
git push
```

**Checkpoint:** After Flux reconciles, you should see:
- A PVC named `myapp` in your namespace
- A ReplicationSource named `myapp-*` for each backup destination

---

## Part 2: Adding Gatus Monitoring

Gatus provides uptime monitoring. Different components exist for different access patterns.

### Choose the Right Gatus Component

| Component | Use When |
|-----------|----------|
| `gatus/external` | App is accessible from the internet |
| `gatus/guarded` | App is internal-only (behind VPN/internal gateway) |
| `gatus/infrastructure` | Infrastructure services (not user-facing apps) |

### Add to Your App

**File:** `kubernetes/apps/<namespace>/<app>/app/kustomization.yaml`

```yaml
components:
  - ../../../../components/gatus/guarded  # or external/infrastructure
  - ../../../../components/volsync
```

> [!NOTE]
> Gatus components typically don't require additional variables - they use the `APP` variable from your existing postBuild.

---

## Part 3: Adding KEDA NFS Scaler

If your app mounts NFS storage and you want it to scale to 0 when NFS is unavailable (preventing stuck pods), use the NFS scaler.

### Add to Your App

**File:** `kubernetes/apps/<namespace>/<app>/app/kustomization.yaml`

```yaml
components:
  - ../../../../components/keda/nfs-scaler
  - ../../../../components/gatus/guarded
  - ../../../../components/volsync
```

This creates a KEDA ScaledObject that monitors NFS availability and scales your deployment accordingly.

---

## Part 4: Creating a New Component

If you need shared configuration that doesn't exist yet, create your own component.

### Step 4.1: Create the Directory Structure

```bash
mkdir -p kubernetes/components/my-component
```

### Step 4.2: Create the Component kustomization.yaml

**File:** `kubernetes/components/my-component/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component              # <-- Must be Component, not Kustomization
resources:
  - ./my-resource.yaml
```

### Step 4.3: Create Your Resource Files

**File:** `kubernetes/components/my-component/my-resource.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP}-config        # Use ${APP} for app-specific naming
data:
  setting: ${MY_SETTING}     # Custom variable
```

### Step 4.4: Use Default Values (Optional)

For optional variables, use Bash-style defaults:

```yaml
data:
  setting: ${MY_SETTING:-default-value}  # Uses "default-value" if not set
```

### Step 4.5: Test Your Component

```bash
# Kustomize can build components locally (unlike Flux postBuild)
cd kubernetes/apps/myns/myapp/app
kustomize build .
```

> [!WARNING]
> `kustomize build` won't substitute `${VAR}` placeholders - that's Flux's job. But it will validate your component structure is correct.

---

## How the Volsync Component Works (Deep Dive)

Understanding the volsync component helps you understand the pattern.

### Component Hierarchy

```
volsync/
├── kustomization.yaml        # Parent component
│   └── includes: nfs-truenas, s3-backblaze, s3-cloudflare
├── nfs-truenas/
│   ├── kustomization.yaml    # Sub-component
│   ├── externalsecret.yaml   # Kopia credentials
│   ├── pvc.yaml              # The data PVC
│   ├── replicationsource.yaml    # Backup job
│   └── replicationdestination.yaml  # Restore config
├── s3-backblaze/
│   ├── kustomization.yaml
│   ├── externalsecret.yaml   # B2 credentials
│   └── replicationsource.yaml
└── s3-cloudflare/
    └── ... (similar structure)
```

### What Gets Created

When you include the `volsync` component, you get:
1. **PVC** named `${APP}` with size `${VOLSYNC_CAPACITY}`
2. **ExternalSecrets** for each backup destination
3. **ReplicationSources** that back up to:
   - NFS on TrueNAS
   - Backblaze B2
   - Cloudflare R2
4. **ReplicationDestination** for restoring from NFS

### Variable Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APP` | Yes | - | App name, used for PVC and backup names |
| `VOLSYNC_CAPACITY` | Yes | - | PVC storage size (e.g., `10Gi`) |
| `VOLSYNC_STORAGECLASS` | No | `ceph-block` | Storage class for PVC |
| `VOLSYNC_SNAPSHOTCLASS` | No | `csi-ceph-blockpool` | Snapshot class |

---

## Troubleshooting

### PVC Not Created

**Symptoms:** No PVC appears after deployment

**Check:**
1. Is the component included in kustomization.yaml?
   ```bash
   cat kubernetes/apps/myns/myapp/app/kustomization.yaml | grep components
   ```
2. Is `APP` defined in postBuild.substitute?
   ```bash
   cat kubernetes/apps/myns/myapp/ks.yaml | grep -A5 postBuild
   ```

### Variable Not Substituted

**Symptoms:** Resources created with literal `${APP}` in the name

**Check:**
1. Is the variable in `postBuild.substitute` (not just `substitute`)?
2. Is the Flux Kustomization pointing to the correct path?

### Component Not Found

**Symptoms:** `error: unable to find component`

**Check:**
1. Is the path correct? Count the `../` segments
2. Does the component have `kind: Component` (not `Kustomization`)?

---

## Best Practices

### 1. Use Consistent Naming

Always use `${APP}` for resource names so they're unique per-app:
```yaml
metadata:
  name: ${APP}  # Good - unique per app
  name: backup  # Bad - will conflict between apps
```

### 2. Add Defaults for Optional Variables

```yaml
storageClassName: ${VOLSYNC_STORAGECLASS:-ceph-block}
```

### 3. Document Required Variables

In your component's kustomization.yaml, add a comment:
```yaml
# Required variables:
#   APP - Application name
#   VOLSYNC_CAPACITY - PVC size
```

### 4. Keep Components Focused

Each component should do one thing:
- `volsync` = backups
- `gatus` = monitoring
- `keda/nfs-scaler` = NFS-based scaling

### 5. Test Locally First

```bash
kustomize build kubernetes/apps/myns/myapp/app/
```

---

## Quick Reference

### Adding Components to an App

```yaml
# kustomization.yaml
components:
  - ../../../../components/volsync
  - ../../../../components/gatus/guarded
  - ../../../../components/keda/nfs-scaler
```

### Required Variables for Volsync

```yaml
# ks.yaml
postBuild:
  substitute:
    APP: myapp
    VOLSYNC_CAPACITY: 10Gi
```

### Creating a New Component

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./my-resource.yaml
```

---

## Why Not Templates?

You might see references to a `kubernetes/templates/` directory in older documentation. That pattern has been replaced by components.

| Feature | Templates (Old) | Components (Current) |
|---------|-----------------|---------------------|
| Native Kustomize | No | Yes |
| Local testing | Requires Flux | Works with `kustomize build` |
| Composition | Limited | Full (components can include components) |
| Community adoption | Legacy | Standard pattern |

> [!NOTE]
> If you see `kubernetes/templates/` in your repo, it's likely legacy configuration that should be migrated to components.

---

## Sources

- [Kustomize Components Documentation](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
- [Flux postBuild Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops) - Reference implementation
- [joryirving/home-ops](https://github.com/joryirving/home-ops) - Reference implementation

---

> [!NOTE]
> **GitOps Reminder:** All component changes should be committed to Git and deployed via Flux. Test locally with `kustomize build` before pushing.
