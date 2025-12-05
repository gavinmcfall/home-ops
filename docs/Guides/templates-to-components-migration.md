# Templates to Components Migration Guide

## Context

This guide documents the shift from Flux **postBuild templates** to Kustomize **components** for shared configurations like Volsync backups.

**Current State**: Using `kubernetes/templates/volsync/` with postBuild substitution
**Target State**: Using `kubernetes/components/volsync/` with Kustomize Component pattern

---

## Why Migrate?

### Templates (Current Approach)

```
kubernetes/templates/volsync/
├── claim.yaml        # PVC with ${APP}, ${VOLSYNC_CAPACITY}
├── backblaze.yaml    # ReplicationSource → B2
└── r2.yaml           # ReplicationSource → R2
```

**How it works**: Apps include templates via kustomization.yaml resources, Flux substitutes variables via postBuild.

```yaml
# App's kustomization.yaml
resources:
  - ../../../../templates/volsync

# App's ks.yaml
postBuild:
  substitute:
    APP: sonarr
    VOLSYNC_CAPACITY: 10Gi
```

**Problems**:
1. **Not reusable across contexts**: postBuild substitution only works within Flux Kustomizations
2. **No inheritance/composition**: Can't easily extend or override individual pieces
3. **Testing limitations**: Can't `kustomize build` without Flux
4. **Duplicated paths**: Every app references the same template path

### Components (Target Approach)

```
kubernetes/components/volsync/
├── kustomization.yaml   # Kind: Component
├── externalsecret.yaml  # ExternalSecret (uses ${APP})
├── claim.yaml           # PVC (uses ${APP}, ${VOLSYNC_CAPACITY})
├── replicationsource.yaml
└── replicationdestination.yaml
```

**How it works**: Apps include components via Kustomize's `components:` field.

```yaml
# App's ks.yaml
spec:
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: sonarr
      VOLSYNC_CAPACITY: 10Gi
```

**Benefits**:
1. **Native Kustomize feature**: `kustomize build` works without Flux
2. **Composable**: Can include multiple components, each adding specific functionality
3. **Hierarchical**: Components can include other components
4. **Selective inclusion**: Components can be conditionally included based on app needs

---

## Pattern Comparison

### onedr0p's Implementation

**Reference**: `/home/gavin/cloned-repos/homelab-repos/onedr0p(Devin)/home-ops/`

```
kubernetes/components/
├── volsync/              # Volsync backup component
│   ├── kustomization.yaml
│   ├── externalsecret.yaml
│   ├── replicationsource.yaml
│   ├── replicationdestination.yaml
│   └── claim.yaml
└── nfs-scaler/           # KEDA-based NFS availability
    ├── kustomization.yaml
    └── scaledobject.yaml
```

**App usage**:
```yaml
# kubernetes/apps/default/sonarr/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sonarr
spec:
  components:
    - ../../../../components/volsync
    - ../../../../components/nfs-scaler
  postBuild:
    substitute:
      APP: sonarr
      VOLSYNC_CAPACITY: 10Gi
      NFS_SERVER: expanse.internal
      NFS_PATH: /mnt/media
```

**Key patterns**:
- MutatingAdmissionPolicy auto-injects NFS mounts into mover jobs
- KEDA ScaledObject scales pods based on NFS availability
- Single Kopia repository shared across all apps (cross-app deduplication)

### joryirving's Implementation

**Reference**: `/home/gavin/cloned-repos/homelab-repos/LilDrukenSmurf(joryireving)/home-ops/`

```
kubernetes/components/volsync/
├── kustomization.yaml
├── externalsecret.yaml
├── replicationsource.yaml
├── replicationdestination.yaml
└── claim.yaml
```

**Additional features**:
- **Jitter injection**: Random 0-30s delay via MutatingAdmissionPolicy to prevent thundering herd
- **Dual ExternalSecrets**: Both Kopia (filesystem) and Restic (R2) credentials available
- **enableFileDeletion**: Set on ReplicationDestination for clean restores

---

## Component Structure

### kustomization.yaml (Component Definition)

```yaml
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./externalsecret.yaml
  - ./replicationsource.yaml
  - ./replicationdestination.yaml
  - ./claim.yaml
```

Note: `kind: Component` (not `Kustomization`)

### Variable Substitution

Components still use Flux postBuild substitution for variables:

```yaml
# In component files
metadata:
  name: ${APP}
spec:
  capacity: ${VOLSYNC_CAPACITY}
```

```yaml
# In app's ks.yaml
postBuild:
  substitute:
    APP: sonarr
    VOLSYNC_CAPACITY: 10Gi
```

### Default Values

Use Bash-style defaults for optional variables:

```yaml
copyMethod: ${VOLSYNC_COPYMETHOD:-Snapshot}
storageClassName: ${VOLSYNC_STORAGECLASS:-ceph-block}
```

---

## Migration Steps

### Phase 1: Create Component

1. **Create component structure**:
```bash
mkdir -p kubernetes/components/volsync
```

2. **Create kustomization.yaml**:
```yaml
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./externalsecret.yaml
  - ./replicationsource.yaml
  - ./replicationdestination.yaml
  - ./claim.yaml
```

3. **Move/adapt template files** to component:
   - Keep same variable substitution (`${APP}`, etc.)
   - Update any path references
   - Add defaults where appropriate

### Phase 2: Update Apps (One at a Time)

**Before** (template approach):
```yaml
# App's app/kustomization.yaml
resources:
  - ./helmrelease.yaml
  - ../../../../templates/volsync
```

**After** (component approach):
```yaml
# App's app/kustomization.yaml
resources:
  - ./helmrelease.yaml

# App's ks.yaml
spec:
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: sonarr
      VOLSYNC_CAPACITY: 10Gi
```

### Phase 3: Remove Templates

Once all apps are migrated:
```bash
rm -rf kubernetes/templates/volsync
```

---

## Your Current State

### Existing Components

```
kubernetes/components/
├── common/           # Namespace, cluster-vars, alerts, sops
├── gatus/            # Gatus monitoring integration
├── keda/             # KEDA scaling
└── volsync/          # Volsync backup (partially implemented)
```

### Existing Templates

```
kubernetes/templates/
├── gatus/            # Gatus (duplicate?)
└── volsync/          # Volsync backup (current)
    ├── claim.yaml
    ├── backblaze.yaml
    └── r2.yaml
```

### Next Steps

1. **Audit**: Check which apps use `templates/volsync` vs `components/volsync`
2. **Complete component**: Ensure `components/volsync` has all necessary files
3. **Migrate apps**: Update ks.yaml to use component instead of template
4. **Clean up**: Remove redundant templates

---

## Advanced: MutatingAdmissionPolicy for NFS Injection

Both onedr0p and joryirving use this pattern to auto-inject NFS mounts:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingAdmissionPolicy
metadata:
  name: volsync-mover-nfs
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["batch"]
        apiVersions: ["v1"]
        resources: ["jobs"]
        operations: ["CREATE"]
    matchPolicy: Equivalent
  matchConditions:
    - name: is-volsync-job
      expression: "object.metadata.name.startsWith('volsync-')"
  mutations:
    - patchType: JSONPatch
      jsonPatch:
        expression: |
          [
            {
              "op": "add",
              "path": "/spec/template/spec/volumes/-",
              "value": {
                "name": "repository",
                "nfs": {
                  "server": "citadel.internal",
                  "path": "/mnt/storage0/backups/volsync"
                }
              }
            },
            {
              "op": "add",
              "path": "/spec/template/spec/containers/0/volumeMounts/-",
              "value": {
                "name": "repository",
                "mountPath": "/repository"
              }
            }
          ]
```

**Why this is powerful**: No app-level configuration needed for repository access. All Volsync mover jobs automatically get NFS mounted.

---

## References

- [Kustomize Components](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
- [Flux postBuild Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [onedr0p home-ops](https://github.com/onedr0p/home-ops)
- [joryirving home-ops](https://github.com/joryirving/home-ops)
- [Volsync/Kopia Migration Guide](./volsync-kopia-migration.md)
