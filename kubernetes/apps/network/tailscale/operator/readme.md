# Tailscale Operator

This operator provides two main capabilities:

1. **API Server Proxy** — Remote `kubectl` access to the cluster via Tailscale
2. **Subnet Router (Connector)** — Expose cluster networks to the Tailnet for Split DNS remote access

> [!NOTE]
> We use Split DNS + Connector for app access instead of per-app Tailscale ingresses.
> This means one Connector pod instead of 23+ proxy pods.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Tailscale Remote Access                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Remote Device                                                     │
│       │                                                             │
│       │ 1. DNS: paperless.${SECRET_DOMAIN}                          │
│       ▼                                                             │
│   ┌─────────────────┐                                               │
│   │ Tailscale Client│  2. Split DNS forwards to k8s-gateway         │
│   └────────┬────────┘     via WireGuard tunnel                      │
│            │                                                        │
│            ▼                                                        │
│   ┌─────────────────┐                                               │
│   │   k8s-gateway   │  3. Returns: 10.90.3.202 (internal gateway)   │
│   │   10.90.3.200   │                                               │
│   └────────┬────────┘                                               │
│            │                                                        │
│            ▼                                                        │
│   ┌─────────────────┐                                               │
│   │    Connector    │  4. Subnet route makes 10.90.x.x reachable    │
│   │ (home-subnet)   │     via WireGuard mesh                        │
│   └────────┬────────┘                                               │
│            │                                                        │
│            ▼                                                        │
│   ┌─────────────────┐                                               │
│   │ Internal Gateway│  5. HTTPRoute serves the app                  │
│   │   10.90.3.202   │                                               │
│   └─────────────────┘                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Tailscale account (free tier works)
- Tailscale app on at least two devices (phone, laptop, etc.)
- 1Password Connect (or your secret store of choice)

---

## Part 1: Operator Setup

### Tailscale Account Configuration

1. Login to [Tailscale](https://login.tailscale.com/)

2. Go to [Access Controls](https://login.tailscale.com/admin/acls/file) and add these tags:

    ```json
    "tagOwners": {
        "tag:k8s-operator": [],
        "tag:k8s":          ["tag:k8s-operator"],
    },
    ```

3. Click **Save**

4. Go to **Settings** → [OAuth Clients](https://login.tailscale.com/admin/settings/oauth)

5. Click **Generate OAuth client...** with these settings:
    - Description: `k8s-operator`
    - Device: Read ✓, Write ✓
    - Add tag: `k8s-operator`

6. Save the **Client ID** and **Secret** to 1Password:
    - `TAILSCALE_OATH_CLIENT_ID`
    - `TAILSCALE_OAUTH_CLIENT_SECRET`

7. Go to **Settings** → [Device Management](https://login.tailscale.com/admin/settings/device-management) and set up [Tailnet Lock](https://tailscale.com/kb/1226/tailnet-lock)

### Deploy the Operator

1. Add to your cluster secrets:
    ```bash
    sops ~/home-ops/kubernetes/flux/vars/cluster-secrets.sops.yaml
    ```
    Add: `TAILSCALE_EMAIL: your-tailscale-email@example.com`

2. Uncomment `./tailscale/ks.yaml` in the network namespace kustomization

3. Push to git and wait for Flux to reconcile

4. Once the operator pod is running, go to [Machines](https://login.tailscale.com/admin/machines)

5. Find `tailscale-operator`, click it, and **Sign Node**

### Configure kubectl Access

```bash
tailscale configure kubeconfig tailscale-operator
```

This adds a new context to `~/.kube/config`. Merge it with your main kubeconfig to use `kubectl` remotely.

---

## Part 2: Connector (Subnet Router)

The Connector advertises cluster subnets to your Tailnet, making internal IPs reachable from any Tailscale device.

### Deploy the Connector

The Connector is defined in `connector.yaml`:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: Connector
metadata:
  name: home-subnet
spec:
  hostname: home-subnet-router
  subnetRouter:
    advertiseRoutes:
      - 10.90.0.0/16
```

After deployment, verify it's running:

```bash
kubectl get connector -n network
# NAME          SUBNETROUTES   STATUS             AGE
# home-subnet   10.90.0.0/16   ConnectorCreated   5m
```

### Approve Subnet Routes

1. Go to [Machines](https://login.tailscale.com/admin/machines)
2. Find `home-subnet-router`
3. Click **Edit route settings**
4. Approve the `10.90.0.0/16` route

---

## Part 3: Split DNS Configuration

Split DNS routes `*.${SECRET_DOMAIN}` queries through Tailscale to your internal DNS.

### Configure in Tailscale Admin

1. Go to [DNS Settings](https://login.tailscale.com/admin/dns)

2. Under **Nameservers**, click **Add nameserver** → **Custom...**

3. Configure:
    - **Nameserver**: `10.90.3.200` (k8s-gateway)
    - Check **Restrict to domain**
    - **Domain**: `${SECRET_DOMAIN}`

4. Enable **Override local DNS** (recommended)

### Verify It Works

From a Tailscale-connected device (remote):

```bash
dig paperless.${SECRET_DOMAIN}
# Should return: 10.90.3.202
```

Now `paperless.${SECRET_DOMAIN}` works the same whether you're on LAN or remote via Tailscale.

---

## App Configuration

Apps only need an internal HTTPRoute. No Tailscale ingress required.

```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: internal
        namespace: network
```

### Legacy: Per-App Tailscale Ingress (Deprecated)

The old approach created a proxy pod per app:

```yaml
# DON'T USE THIS - creates unnecessary proxy pods
ingress:
  tailscale:
    enabled: true
    className: tailscale
    hosts:
      - host: paperless
```

This is no longer needed with Split DNS. Remove these blocks from your HelmReleases.

---

## Troubleshooting

### DNS not resolving via Tailscale

1. Check the Connector is running:
   ```bash
   kubectl get connector -n network
   ```

2. Verify subnet routes are approved in Tailscale admin

3. Test DNS resolution:
   ```bash
   tailscale status
   dig @10.90.3.200 paperless.${SECRET_DOMAIN}
   ```

### Can't reach internal gateway IP

The Connector must advertise a route that includes `10.90.3.202`. Check:

```bash
kubectl get connector home-subnet -n network -o yaml | grep advertiseRoutes -A5
```

### Apps not accessible

Ensure the app has an internal HTTPRoute with the correct hostname. The internal gateway must have a matching route.

---

## Components

| Component | Purpose |
|-----------|---------|
| `helmrelease.yaml` | Tailscale Operator deployment |
| `connector.yaml` | Subnet router advertising `10.90.0.0/16` |
| `externalsecret.yaml` | OAuth credentials from 1Password |
| `rbac.yaml` | RBAC for API server proxy (commented out) |

## References

- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets)
- [Tailscale Split DNS](https://tailscale.com/kb/1054/dns)
