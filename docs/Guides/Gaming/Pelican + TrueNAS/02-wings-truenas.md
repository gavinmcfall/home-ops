# Part 2: Wings Setup on TrueNAS

Deploy the Wings daemon on TrueNAS using Docker to manage game server containers.

---

## Prerequisites

Before starting, ensure you have:

- [ ] Pelican Panel running (from Part 1)
- [ ] TrueNAS with Docker support enabled
- [ ] A wildcard SSL certificate (or ability to generate one)
- [ ] External IP for port forwarding
- [ ] Access to your router for port forward configuration

---

## Step 1: Configure DNS

Create a DNS record for your Wings daemon. This is the address players will use to connect to game servers.

**In Cloudflare (or your DNS provider):**

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `play` | `<your-external-ip>` | Off (DNS only) |

> [!IMPORTANT]
> Do NOT proxy this through Cloudflare — game server traffic needs direct access.

**Verify DNS propagation:**
```bash
dig play.${SECRET_DOMAIN} @1.1.1.1
```

---

## Step 2: Configure Port Forwards

In your router (UniFi, pfSense, etc.), create port forwards to your TrueNAS server:

| Name | External Port | Internal IP | Internal Port | Protocol |
|------|---------------|-------------|---------------|----------|
| Wings API | 8443 | `<truenas-ip>` | 8443 | TCP |
| Wings SFTP | 2022 | `<truenas-ip>` | 2022 | TCP |
| Game Servers | 25565-25600 | `<truenas-ip>` | 25565-25600 | TCP/UDP |

> [!TIP]
> The port range 25565-25600 provides 36 allocations for game servers. Minecraft uses 25565 by default.

---

## Step 3: Create Directory Structure on TrueNAS

SSH into TrueNAS and create the required directories:

```bash
ssh truenas

# Create Wings directories
mkdir -p /mnt/storage0/game-servers/wings/{config,logs,tmp,certs}

# Create game server volumes directory
mkdir -p /mnt/storage0/game-servers/volumes

# Set ownership (adjust user/group as needed)
chown -R apps:apps /mnt/storage0/game-servers
```

---

## Step 4: Create the Node in Pelican

1. Go to **Pelican Admin Panel** → **Nodes** → **Create New**

2. Fill in the node details:

| Field | Value |
|-------|-------|
| Name | `citadel-01` (or your preferred name) |
| Location | Select your location |
| FQDN | `play.${SECRET_DOMAIN}` |
| Communicate Over SSL | Yes |
| Behind Proxy | No |
| Daemon Port | `8443` |
| Total Memory | (your allocation, e.g., 32768 MiB) |
| Memory Over-Allocation | `0` |
| Total Disk Space | (your allocation, e.g., 1048576 MiB) |
| Disk Over-Allocation | `0` |
| Daemon Server File Directory | `/mnt/storage0/game-servers/volumes` |

3. Click **Create Node**

---

## Step 5: Get and Customize the Configuration

1. Go to your new node → **Configuration** tab
2. Copy the YAML configuration content (NOT the auto-deploy command)
3. Save it to TrueNAS and add required customizations:

```bash
ssh truenas
nano /mnt/storage0/game-servers/wings/config/config.yml
```

**Example configuration (customize with your values):**

```yaml
debug: false
app_name: Pelican
uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
token_id: xxxxxxxxxxxxxx
token: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
api:
  host: 0.0.0.0
  port: 8443
  ssl:
    enabled: true
    cert: /etc/letsencrypt/live/play.nerdz.cloud/fullchain.pem
    key: /etc/letsencrypt/live/play.nerdz.cloud/privkey.pem
  upload_limit: 100
system:
  root_directory: /var/lib/pelican
  data: /mnt/storage0/game-servers/volumes
  log_directory: /var/log/pelican
  archive_directory: /var/lib/pelican/archives
  backup_directory: /var/lib/pelican/backups
  tmp_directory: /tmp/pelican
  username: pelican
  # IMPORTANT: Set this to false to fix container creation errors
  mount_passwd: false
  timezone: Pacific/Auckland
  sftp:
    bind_port: 2022
allowed_origins:
  - https://pelican.nerdz.cloud
remote: https://pelican.nerdz.cloud
```

> [!IMPORTANT]
> - `mount_passwd: false` is required to fix "failed to create container" errors
> - `allowed_origins` must include your Panel URL for CORS
> - Replace `nerdz.cloud` with your actual domain

---

## Step 6: Set Up SSL Certificates

Wings requires SSL certificates. You have two options:

### Option A: Use Existing Wildcard Certificate (Recommended)

If you have a wildcard certificate in your Kubernetes cluster:

**Export from Kubernetes:**
```bash
# Find your wildcard cert secret
kubectl get secrets -n network | grep tls

# Export cert and key
kubectl get secret <your-tls-secret> -n network -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/fullchain.pem
kubectl get secret <your-tls-secret> -n network -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/privkey.pem

# Copy to TrueNAS
scp /tmp/fullchain.pem /tmp/privkey.pem truenas:/mnt/storage0/game-servers/wings/certs/
```

### Option B: Disable SSL (Not Recommended)

If you can't provide certificates, edit `config.yml`:

```yaml
api:
  ssl:
    enabled: false
```

---

## Step 7: Create docker-compose.yml

Create the Docker Compose file on TrueNAS:

**File: `/mnt/storage0/game-servers/wings/docker-compose.yml`**

```yaml
services:
  wings:
    image: ghcr.io/pelican-dev/wings:latest
    restart: always
    network_mode: host
    tty: true
    environment:
      TZ: "Pacific/Auckland"
      WINGS_UID: 988
      WINGS_GID: 988
      WINGS_USERNAME: pelican
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/var/lib/docker/containers/:/var/lib/docker/containers/"
      - "./config:/etc/pelican/"
      - "./logs:/var/log/pelican/"
      - "/tmp/pelican:/tmp/pelican"
      - "/mnt/storage0/game-servers/volumes:/mnt/storage0/game-servers/volumes"
      - "./certs:/etc/letsencrypt/live/play.nerdz.cloud"

networks:
  pelican_nw:
    driver: bridge
```

> [!IMPORTANT]
> The `/tmp/pelican` volume **must** use the same path on host and container (not `./tmp:/tmp/pelican`). Wings creates install scripts in `/tmp/pelican/` and spawns containers that bind-mount this path from the **host**. If the paths don't match, installs will fail with "bind source path does not exist".

> [!NOTE]
> - `network_mode: host` is required for Wings to manage Docker networks properly
> - The certs volume mounts your SSL certificates to the path Wings expects
> - Adjust timezone (`TZ`) to match your location
> - Replace `nerdz.cloud` with your actual domain

**Create the tmp directory on the host:**
```bash
sudo mkdir -p /tmp/pelican
sudo chown -R apps:apps /tmp/pelican
```

---

## Step 8: Clean Up Old Networks (If Migrating from Pterodactyl)

If you previously ran Pterodactyl, remove the old network to prevent conflicts:

```bash
sudo docker network rm pterodactyl_nw 2>/dev/null || true
```

---

## Step 9: Start Wings

```bash
cd /mnt/storage0/game-servers/wings
sudo docker compose up -d
```

**Check the logs:**
```bash
sudo docker compose logs -f
```

You should see:
```
                     ____
__ Pelican _____/___/_______ _______ ______
\_____\    \/\/    /   /       /  __   /   ___/
   \___\          /   /   /   /  /_/  /___   /
        \___/\___/___/___/___/___    /______/
                            /_______/

INFO: loading configuration from file
INFO: configured wings with system timezone
INFO: fetching list of servers from API
INFO: configuring internal webserver host_address=0.0.0.0 host_port=8443 use_ssl=true
INFO: sftp server listening for connections listen=0.0.0.0:2022
```

---

## Step 10: Verify Node Connection

1. Go to **Pelican Admin Panel** → **Nodes** → Your node
2. The node should show a green heart icon indicating it's connected
3. System information should display (CPU threads, memory, disk)

---

## Step 11: Add Allocations

Allocations define which ports game servers can use.

1. Go to **Nodes** → Your node → **Allocation** tab
2. Add allocations:
   - **IP Address:** `0.0.0.0` (binds to all interfaces)
   - **IP Alias:** `play.${SECRET_DOMAIN}` (what players see)
   - **Ports:** `25565-25600`
3. Click **Submit**

---

## Troubleshooting {#wings-troubleshooting}

### Server Install Fails - "bind source path does not exist"

**Symptoms:**
```
ERROR: failed to run install process for server error=Error response from daemon: invalid mount config for type "bind": bind source path does not exist: /tmp/pelican/xxx
```

**Cause:** The `./tmp:/tmp/pelican` volume mount creates the path inside the Wings container, but when Wings spawns install containers, Docker looks for `/tmp/pelican` on the **host** filesystem.

**Fix:** Update docker-compose.yml to use matching paths:
```yaml
volumes:
  - "/tmp/pelican:/tmp/pelican"  # Same path on host and container
```

Then create the directory and restart:
```bash
sudo mkdir -p /tmp/pelican
sudo chown -R apps:apps /tmp/pelican
sudo docker compose down && sudo docker compose up -d
```

---

### Container Creation Fails - "/etc/passwd" Error

**Symptoms:**
```
ERROR: failed to create container error=...passwd...
```

**Fix:** Add `mount_passwd: false` to your `config.yml`:
```yaml
system:
  mount_passwd: false
```

Then restart Wings:
```bash
sudo docker compose restart
```

---

### Wings Won't Start - SSL Certificate Error

**Symptoms:**
```
FATAL: failed to configure HTTPS server error=open /etc/letsencrypt/.../fullchain.pem: no such file or directory
```

**Fix:** Ensure certificates are mounted correctly:
```bash
ls -la /mnt/storage0/game-servers/wings/certs/
# Should show fullchain.pem and privkey.pem
```

### Wings Can't Connect to Panel

**Symptoms:** Wings starts but node shows as offline in Panel

**Check DNS resolution from TrueNAS:**
```bash
dig pelican.${SECRET_DOMAIN}
```

**Check outbound connectivity:**
```bash
curl -v https://pelican.${SECRET_DOMAIN}/api/application/nodes
```

### CORS Errors in Browser Console

**Symptoms:** Browser console shows CORS errors when accessing Wings

**Fix:** Ensure `allowed_origins` in `config.yml` includes your Panel URL:
```yaml
allowed_origins:
  - https://pelican.nerdz.cloud
```

### Docker Permission Denied

**Symptoms:**
```
permission denied while trying to connect to the Docker daemon socket
```

**Fix:** Use sudo:
```bash
sudo docker compose up -d
```

Or add your user to the docker group:
```bash
sudo usermod -aG docker $USER
```

---

## Networking Troubleshooting {#networking-troubleshooting}

### Game Server Unreachable from Internet

1. **Verify port forwards are working:**
   ```bash
   # From external network
   nc -zv play.${SECRET_DOMAIN} 25565
   ```

2. **Check Wings is listening:**
   ```bash
   sudo netstat -tlnp | grep -E "8443|2022|25565"
   ```

3. **Check firewall rules on TrueNAS**

### DNS Not Resolving

**Check external DNS:**
```bash
dig play.${SECRET_DOMAIN} @1.1.1.1
```

**Check internal DNS (from Kubernetes):**
```bash
kubectl run -it --rm debug --image=busybox -- nslookup play.${SECRET_DOMAIN}
```

---

## Next Steps

With Wings running and connected:

1. **Add Nests/Eggs** — Import game server templates (Minecraft, etc.)
2. **Create a Server** — Test with a Minecraft server on port 25565
3. **Configure Backups** — Set up automatic backups to MinIO

Proceed to [Part 3: Eggs and Servers](./03-eggs-and-servers.md).

---

## Maintenance

### Updating Wings

```bash
cd /mnt/storage0/game-servers/wings
sudo docker compose pull
sudo docker compose up -d
```

### Renewing SSL Certificates

When your wildcard certificate renews, copy the new cert to TrueNAS:

```bash
# Export from Kubernetes
kubectl get secret <your-tls-secret> -n network -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/fullchain.pem
kubectl get secret <your-tls-secret> -n network -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/privkey.pem

# Copy to TrueNAS
scp /tmp/fullchain.pem /tmp/privkey.pem truenas:/mnt/storage0/game-servers/wings/certs/

# Restart Wings
ssh truenas "cd /mnt/storage0/game-servers/wings && sudo docker compose restart"
```

### Viewing Logs

```bash
ssh truenas "cd /mnt/storage0/game-servers/wings && sudo docker compose logs --tail=100"
```
