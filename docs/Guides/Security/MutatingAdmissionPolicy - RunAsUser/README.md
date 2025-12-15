# MutatingAdmissionPolicy: Automatic Security Defaults

A beginner-friendly guide to automatically setting `runAsUser` on pods using Kubernetes native MutatingAdmissionPolicy.

---

## What You'll Learn

By the end of this guide, you'll understand:
- Why running containers as non-root matters
- What MutatingAdmissionPolicy does and how it works
- How to automatically apply security defaults to all pods
- How to exempt certain namespaces or workloads

**Time required**: 15-20 minutes

**Difficulty**: Intermediate

**Workflow**: This guide follows GitOps practices. You'll edit files in your repository and push to git - Flux (or ArgoCD) will apply the changes automatically.

---

## Part 1: Understanding the Problem

### Why Does This Matter?

By default, containers can run as the `root` user (UID 0). This is a security risk because:

- If an attacker escapes the container, they have root access to the host
- Root can modify files that should be read-only
- Root can bind to privileged ports
- Root can potentially access other containers' data

**Best practice**: Run containers as a non-root user (like UID 568).

### The Manual Approach (Tedious)

You could add this to every single pod:

```yaml
spec:
  securityContext:
    runAsUser: 568
    runAsGroup: 568
    runAsNonRoot: true
```

But with dozens of apps, this is:
- Easy to forget
- Tedious to maintain
- Error-prone

### The Automated Approach (This Guide)

**MutatingAdmissionPolicy** automatically modifies pods as they're created:

```
You create a pod          Kubernetes API           Pod is created
without runAsUser    →    intercepts and      →    WITH runAsUser: 568
                          adds it for you          automatically!
```

> [!NOTE]
> MutatingAdmissionPolicy is a native Kubernetes feature (v1.33+). No additional controllers or webhooks needed - the API server handles it directly.

---

## Part 2: How It Works

### The Flow

```
1. You (or Flux) create a Pod
           ↓
2. API Server receives the request
           ↓
3. MutatingAdmissionPolicy checks:
   - Is this namespace exempt? (skip if yes)
   - Does pod already have runAsUser? (skip if yes)
           ↓
4. Policy adds runAsUser/runAsGroup/runAsNonRoot
           ↓
5. Pod is created with security context applied
```

### Key Concepts

| Term | What It Means |
|------|---------------|
| **MutatingAdmissionPolicy** | A rule that modifies resources before they're saved |
| **MutatingAdmissionPolicyBinding** | Activates the policy (connects it to the cluster) |
| **matchConditions** | Rules for when the policy should apply |
| **CEL** | Common Expression Language - the syntax for conditions |
| **JSONPatch** | How the modification is applied to the resource |

---

## Part 3: Before You Start

### Prerequisites

- [ ] Kubernetes cluster version 1.33 or newer
- [ ] `kubectl` access to your cluster
- [ ] Git repository with Flux/ArgoCD managing your cluster

### Verify Your Kubernetes Version

```bash
kubectl version --short
```

You need v1.33.0 or higher. The `MutatingAdmissionPolicy` feature is beta and enabled by default in 1.33+.

### Plan Your Exceptions

Some namespaces should be exempt from this policy. Common exceptions:

| Namespace | Why Exempt |
|-----------|------------|
| `kube-system` | System components have specific UID requirements |
| `flux-system` | Flux controllers manage their own security |
| `rook-ceph` | Storage components need specific permissions |
| `security` | Security tools may need special access |

---

## Part 4: Create the Policy

### Step 4.1: Create the Directory Structure

In your repository:

```
kubernetes/apps/security/mutating-policies/
├── kustomization.yaml
└── default-run-as-user.yaml
```

### Step 4.2: Create the Policy File

Create `kubernetes/apps/security/mutating-policies/default-run-as-user.yaml`:

```yaml
---
# The policy definition - what to do
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingAdmissionPolicy
metadata:
  name: default-run-as-user
spec:
  # If the policy fails, deny the pod (safer than allowing insecure pods)
  failurePolicy: Fail

  # Re-run if other policies modify the pod
  reinvocationPolicy: IfNeeded

  # Only apply to Pod resources
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]

  # Conditions that must be true for the policy to apply
  matchConditions:
    # Skip exempt namespaces
    - name: non-exempt-namespace
      expression: >
        !['kube-system','flux-system','rook-ceph','security'].exists(ns, ns == object.metadata.namespace)

    # Only apply if runAsUser is not already set
    - name: pod-missing-run-as-user
      expression: >
        has(object.spec) && (!has(object.spec.securityContext) || !has(object.spec.securityContext.runAsUser))

  # The actual modification to make
  mutations:
    - patchType: JSONPatch
      jsonPatch:
        expression: >
          [
            JSONPatch{
              op: "add",
              path: "/spec/securityContext",
              value: object.spec.securityContext.orValue(PodSpec.securityContext{})
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsUser",
              value: 568
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsGroup",
              value: 568
            },
            JSONPatch{
              op: "add",
              path: "/spec/securityContext/runAsNonRoot",
              value: true
            }
          ]
---
# The binding - activates the policy
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingAdmissionPolicyBinding
metadata:
  name: default-run-as-user
spec:
  policyName: default-run-as-user
```

### Step 4.3: Understanding the Policy

Let's break down what each part does:

**The matchConditions (when to apply):**

```yaml
# This CEL expression checks if namespace is NOT in the exempt list
!['kube-system','flux-system','rook-ceph','security'].exists(ns, ns == object.metadata.namespace)
```

Translation: "Apply this policy unless the pod is in kube-system, flux-system, rook-ceph, or security namespace."

```yaml
# This checks if runAsUser is missing
has(object.spec) && (!has(object.spec.securityContext) || !has(object.spec.securityContext.runAsUser))
```

Translation: "Apply this policy only if the pod doesn't already have runAsUser set."

**The mutations (what to change):**

The JSONPatch adds:
- `runAsUser: 568` - Run as user ID 568 (a common non-root UID)
- `runAsGroup: 568` - Run as group ID 568
- `runAsNonRoot: true` - Kubernetes will refuse to start the container as root

> [!TIP]
> Why 568? It's a convention in the homelab community (used by linuxserver.io images). You can use any non-root UID, but 568 is widely recognized.

### Step 4.4: Create the Kustomization

Create `kubernetes/apps/security/mutating-policies/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - default-run-as-user.yaml
```

### Step 4.5: Add to Parent Kustomization

Update `kubernetes/apps/security/kustomization.yaml` to include the new directory:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - pocket-id/ks.yaml
  - mutating-policies  # Add this line
```

### Step 4.6: Commit and Push

```bash
git add kubernetes/apps/security/mutating-policies/
git add kubernetes/apps/security/kustomization.yaml
git commit -m "feat(security): add MutatingAdmissionPolicy for default runAsUser"
git push
```

### Step 4.7: Wait for Flux to Reconcile

```bash
# Watch the reconciliation
flux get kustomizations --watch

# Or force immediate sync
flux reconcile kustomization security --with-source
```

---

## Part 5: Verify It Works

### Step 5.1: Check the Policy Exists

```bash
kubectl get mutatingadmissionpolicies
```

Expected output:
```
NAME                  AGE
default-run-as-user   1m
```

### Step 5.2: Check the Binding Exists

```bash
kubectl get mutatingadmissionpolicybindings
```

Expected output:
```
NAME                  AGE
default-run-as-user   1m
```

### Step 5.3: Test with a New Pod

Create a test pod without any securityContext. The easiest way is to trigger a pod recreation in a non-exempt namespace.

Then check if the policy was applied:

```bash
# Pick any pod in a non-exempt namespace
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 "securityContext"
```

You should see:
```yaml
securityContext:
  runAsUser: 568
  runAsGroup: 568
  runAsNonRoot: true
```

### Step 5.4: Verify Exemptions Work

Check a pod in an exempt namespace (like `kube-system`):

```bash
kubectl get pod -n kube-system <pod-name> -o yaml | grep -A5 "securityContext"
```

It should NOT have been modified (will show original values or nothing).

---

## Part 6: Customization Options

### Adding More Exempt Namespaces

Edit the `matchConditions` expression:

```yaml
- name: non-exempt-namespace
  expression: >
    !['kube-system','flux-system','rook-ceph','security','database','my-new-namespace'].exists(ns, ns == object.metadata.namespace)
```

### Adding a Label-Based Opt-Out

Allow specific pods to skip the policy by adding a label:

```yaml
matchConditions:
  - name: non-exempt-namespace
    expression: >
      !['kube-system','flux-system','rook-ceph','security'].exists(ns, ns == object.metadata.namespace)
  - name: pod-missing-run-as-user
    expression: >
      has(object.spec) && (!has(object.spec.securityContext) || !has(object.spec.securityContext.runAsUser))
  # Add this new condition
  - name: no-opt-out-label
    expression: >
      !has(object.metadata.labels) || !has(object.metadata.labels['security.policy/skip-run-as-user']) || object.metadata.labels['security.policy/skip-run-as-user'] != 'true'
```

Then pods can opt out with:

```yaml
metadata:
  labels:
    security.policy/skip-run-as-user: "true"
```

### Using a Different UID

Change `568` to your preferred UID in the mutations:

```yaml
JSONPatch{
  op: "add",
  path: "/spec/securityContext/runAsUser",
  value: 1000  # Your preferred UID
}
```

---

## Part 7: Troubleshooting

### Problem: Policy Not Listed

**Symptoms**: `kubectl get mutatingadmissionpolicies` shows nothing

**Check 1**: Is your cluster version 1.33+?
```bash
kubectl version
```

**Check 2**: Did Flux apply the resources?
```bash
flux get kustomizations | grep security
kubectl get events -n security --sort-by='.lastTimestamp'
```

### Problem: Policy Exists But Pods Aren't Modified

**Symptoms**: Policy shows up, but new pods don't have runAsUser

**Check 1**: Is the binding present?
```bash
kubectl get mutatingadmissionpolicybindings
```

**Check 2**: Is the pod in an exempt namespace?

**Check 3**: Does the pod already have runAsUser set?
```bash
kubectl get pod <name> -o yaml | grep runAsUser
```

**Check 4**: Check API server logs for policy errors:
```bash
kubectl logs -n kube-system -l component=kube-apiserver --tail=100 | grep -i admission
```

### Problem: Pods Failing to Create

**Symptoms**: Pods stuck in Pending or error creating

**Check 1**: Look at pod events:
```bash
kubectl describe pod <name>
```

**Check 2**: The `failurePolicy: Fail` means if the policy can't be evaluated, pods are denied. Check if there's a CEL syntax error:
```bash
kubectl get mutatingadmissionpolicy default-run-as-user -o yaml
```

### Problem: Need to Debug CEL Expressions

CEL expressions can be tricky. Simplify to debug:

```yaml
# Start simple - just check namespace
expression: >
  object.metadata.namespace != 'kube-system'
```

Then gradually add complexity back.

---

## Quick Reference

### Files to Create

| File | Purpose |
|------|---------|
| `kubernetes/apps/security/mutating-policies/default-run-as-user.yaml` | Policy + Binding |
| `kubernetes/apps/security/mutating-policies/kustomization.yaml` | Kustomize resource list |

### Useful Commands

| Task | Command |
|------|---------|
| List policies | `kubectl get mutatingadmissionpolicies` |
| List bindings | `kubectl get mutatingadmissionpolicybindings` |
| Check pod security context | `kubectl get pod <name> -o yaml \| grep -A5 securityContext` |
| View policy details | `kubectl describe mutatingadmissionpolicy default-run-as-user` |

### Default Values Applied

| Field | Value | Meaning |
|-------|-------|---------|
| `runAsUser` | 568 | Container runs as UID 568 |
| `runAsGroup` | 568 | Container's primary group is GID 568 |
| `runAsNonRoot` | true | Kubernetes prevents container from running as root |

---

## What's Next?

Now that you have automatic security defaults:

1. **Monitor for issues**: Watch for pods that fail due to needing root access
2. **Add ValidatingAdmissionPolicy**: Create a policy that warns (but doesn't block) pods without security context
3. **Expand coverage**: Consider policies for other security settings like `readOnlyRootFilesystem`

---

## Further Reading

- [Kubernetes MutatingAdmissionPolicy Docs](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [CEL Language Specification](https://github.com/google/cel-spec)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
