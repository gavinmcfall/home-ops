# Part 4: PocketID OAuth Integration

Configure single sign-on (SSO) for Pelican Panel using PocketID as the OIDC provider.

---

## Overview

This guide enables users to log into Pelican Panel using their PocketID credentials. The integration requires:

1. Installing the PocketID Socialite plugin
2. Installing the `socialiteproviders/pocketid` Composer package
3. Configuring environment variables
4. Creating an OIDC client in PocketID

---

## Prerequisites

- [ ] Pelican Panel running (from Part 1)
- [ ] PocketID deployed and accessible
- [ ] Admin access to both Pelican and PocketID

---

## Known Issues

> [!WARNING]
> **Username "bio" suffix bug**: New users created via PocketID OAuth sometimes get "bio" appended to their username (e.g., "serinamcfall" → "serinamcfallbio"). This requires manual correction in the Pelican admin panel.

---

## Step 1: Create OIDC Client in PocketID

1. Log into PocketID admin at `https://id.${SECRET_DOMAIN}`
2. Go to **OIDC Clients** → **Create New**
3. Configure the client:

| Field | Value |
|-------|-------|
| Name | `Pelican` |
| Callback URL | `https://pelican.${SECRET_DOMAIN}/auth/oauth/callback/pocketid` |

4. Save and note the **Client ID** and **Client Secret**

---

## Step 2: Add Secrets to 1Password

Add these fields to your `pelican` vault item:

| Field | Value |
|-------|-------|
| `PELICAN_POCKETID_CLIENTID` | OAuth Client ID from Step 1 |
| `PELICAN_POCKETID_SECRET` | OAuth Client Secret from Step 1 |

---

## Step 3: Update ExternalSecret

Add PocketID environment variables to your ExternalSecret.

**File: `kubernetes/apps/games/pelican/app/externalsecret.yaml`**

Add to the `data` section:

```yaml
# PocketID OAuth
OAUTH_POCKETID_CLIENT_ID: "{{ .PELICAN_POCKETID_CLIENTID }}"
OAUTH_POCKETID_CLIENT_SECRET: "{{ .PELICAN_POCKETID_SECRET }}"
OAUTH_POCKETID_BASE_URL: https://id.${SECRET_DOMAIN}
OAUTH_POCKETID_DISPLAY_NAME: PocketID
OAUTH_POCKETID_SHOULD_CREATE_MISSING_USERS: "true"
OAUTH_POCKETID_SHOULD_LINK_MISSING_USERS: "true"
```

### Environment Variable Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `OAUTH_POCKETID_CLIENT_ID` | OAuth Client ID | (required) |
| `OAUTH_POCKETID_CLIENT_SECRET` | OAuth Client Secret | (required) |
| `OAUTH_POCKETID_BASE_URL` | PocketID URL (no trailing slash) | (required) |
| `OAUTH_POCKETID_DISPLAY_NAME` | Button text on login page | `PocketID` |
| `OAUTH_POCKETID_SHOULD_CREATE_MISSING_USERS` | Auto-create accounts for new users | `false` |
| `OAUTH_POCKETID_SHOULD_LINK_MISSING_USERS` | Auto-link existing accounts by email | `false` |

---

## Step 4: Install Composer Dependencies

The PocketID plugin requires the `socialiteproviders/pocketid` package, which isn't included in the base Pelican image. Add init containers to install it.

**File: `kubernetes/apps/games/pelican/app/helmrelease.yaml`**

Add these init containers before your main app container:

```yaml
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
  copy-vendor:
    image:
      repository: ghcr.io/pelican-dev/panel
      tag: v1.0.0-beta30@sha256:aec08833e40b54e773cae68945d81f42561d176244032e33c152a92ebd0e0deb
    command:
      - /bin/sh
      - -c
      - |
        set -e
        echo "Copying composer files to shared volume..."
        cp -a /var/www/html/vendor /composer-workdir/
        cp /var/www/html/composer.json /composer-workdir/
        cp /var/www/html/composer.lock /composer-workdir/
        echo "Vendor files copied"
    securityContext:
      runAsUser: 0
      runAsGroup: 0
  install-pocketid:
    image:
      repository: composer
      tag: "2@sha256:f5e5bb7048c7b0182ea153fed4a63d021f3c77d4a654d6572da4a42aaff547e3"
    command:
      - /bin/sh
      - -c
      - |
        set -e
        cd /composer-workdir
        if [ ! -d "vendor/socialiteproviders/pocketid" ]; then
          echo "Installing socialiteproviders/pocketid..."
          composer require socialiteproviders/pocketid:^5.0 --no-interaction --no-progress --ignore-platform-reqs
        else
          echo "socialiteproviders/pocketid already installed"
        fi
    securityContext:
      runAsUser: 0
      runAsGroup: 0
```

Add an emptyDir volume for the composer workdir:

```yaml
persistence:
  composer-workdir:
    type: emptyDir
    advancedMounts:
      pelican:
        copy-vendor:
          - path: /composer-workdir
        install-pocketid:
          - path: /composer-workdir
        app:
          - path: /var/www/html/vendor
            subPath: vendor
```

> [!NOTE]
> The composer package is reinstalled on each pod restart, adding ~30-60 seconds to startup time. This workaround is needed until the upstream Pelican image includes proper plugin support.

---

## Step 5: Deploy Changes

Commit and push:

```bash
git add kubernetes/apps/games/pelican/
git commit -m "feat(pelican): add PocketID OAuth integration"
git push
```

Wait for reconciliation:

```bash
flux reconcile kustomization pelican --with-source
```

---

## Step 6: Install the PocketID Plugin

1. Download the plugin from: https://github.com/pelican-dev/plugins/tree/main/pocketid
2. Go to **Pelican Admin Panel** → **Plugins**
3. Upload the plugin files or clone directly:

```bash
kubectl exec -n games deploy/pelican -- \
  git clone https://github.com/pelican-dev/plugins.git /tmp/plugins

kubectl exec -n games deploy/pelican -- \
  cp -r /tmp/plugins/pocketid /var/www/html/plugins/
```

4. Enable the plugin in Pelican Admin → Plugins

---

## Step 7: Verify Integration

1. Visit `https://pelican.${SECRET_DOMAIN}/login`
2. You should see a "Login with PocketID" button
3. Click it and authenticate with your PocketID credentials
4. On success, you'll be logged into Pelican

---

## User Linking Behavior

| Scenario | Behavior |
|----------|----------|
| New user, `SHOULD_CREATE_MISSING_USERS=true` | Account created automatically |
| Existing user, `SHOULD_LINK_MISSING_USERS=true` | Account linked by matching email |
| Existing user, linking disabled | User must manually link via Profile → Linked Accounts |

### Manual Account Linking

For existing users who need to link their accounts:

1. Log into Pelican with existing credentials
2. Go to **Profile** → **Linked Accounts**
3. Click **Link PocketID**
4. Authenticate with PocketID
5. Accounts are now linked

---

## Troubleshooting {#oauth-troubleshooting}

### "Login with PocketID" Button Not Showing

**Check plugin is installed:**
```bash
kubectl exec -n games deploy/pelican -- ls -la /var/www/html/plugins/
```

**Check plugin is enabled:**
Go to Admin Panel → Plugins and verify PocketID is listed and enabled.

### OAuth Callback Error

**Verify callback URL matches exactly:**
- PocketID OIDC client callback: `https://pelican.nerdz.cloud/auth/oauth/callback/pocketid`
- Must match your Panel URL exactly (no trailing slash differences)

**Check environment variables:**
```bash
kubectl exec -n games deploy/pelican -- env | grep OAUTH_POCKETID
```

### Composer Package Not Found

**Check composer workdir:**
```bash
kubectl exec -n games deploy/pelican -- ls -la /var/www/html/vendor/socialiteproviders/
```

**Force reinstall:**
```bash
kubectl rollout restart deployment/pelican -n games
```

### Username Has "bio" Suffix

This is a known bug. Manually fix in Admin Panel:

1. Go to **Admin** → **Users**
2. Find the affected user
3. Edit and correct the username
4. Save

---

## Upstream Contributions

The following PRs were created to improve Pelican's container experience:

| PR | Description | Status |
|----|-------------|--------|
| [pelican-dev/panel#2112](https://github.com/pelican-dev/panel/pull/2112) | Make `APP_TIMEZONE` env var work | Pending |
| [pelican-dev/plugins#82](https://github.com/pelican-dev/plugins/pull/82) | PocketID container/Kubernetes docs | Pending |
| [pelican-dev/panel#2063](https://github.com/pelican-dev/panel/pull/2063) | Fix plugins symlink in Dockerfile | Open |

Once PR #2063 is merged, the plugin mounting workaround can be simplified.
