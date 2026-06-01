# GPU worker autostart — run ComfyUI as a service on boot

Makes each GPU worker (VengeancePC, VixenPC) start ComfyUI **on boot** with the
flags ComfyUI-Distributed requires, so the cluster master can delegate renders
without anyone logging in and launching it by hand.

**Not a Flux resource** — `worker-setup/` is outside the Flux Kustomization path
(`../app`). These are host-side ops artifacts for the Windows/WSL2 workers.

## Why this exists / what was wrong

Phase-0 ([`phase-0-worker-install.md`](https://github.com/gavinmcfall/lighthouse) in the lighthouse repo) launched ComfyUI **manually** with only `--listen 0.0.0.0`. Two gaps for production distributed rendering:

1. **Not persistent** — a manual `python main.py` dies on logout/reboot.
2. **Missing `--enable-cors-header`** — ComfyUI-Distributed *requires* both
   `--listen` **and** `--enable-cors-header` on a remote worker; without CORS the
   master's cross-origin calls to the worker fail.

There is **no auto-registration** — the master already knows both workers (static
`workers[]` list in the master's `gpu_config.json`). A worker just has to be a
running ComfyUI reachable at `vengeancepc.internal:8188` / `vixenpc.internal:8188`.

## Install (per worker — run on each PC)

### 1. Enable systemd in the WSL2 `lighthouse` distro

Inside the distro (`wsl -d lighthouse`), as root, ensure `/etc/wsl.conf` has:

```ini
[boot]
systemd=true
```

Then from **Windows** PowerShell: `wsl --shutdown` (applies on next start).

### 2. Install + enable the service

Copy `comfyui-worker.service` into the distro, **replace `<WSL_USER>`** with the
distro's UNIX user (owns `~/ComfyUI`), then:

```bash
sudo cp comfyui-worker.service /etc/systemd/system/comfyui-worker.service
sudo sed -i "s/<WSL_USER>/$USER/g" /etc/systemd/system/comfyui-worker.service
sudo systemctl daemon-reload
sudo systemctl enable --now comfyui-worker.service
systemctl status comfyui-worker.service        # active (running)
curl -sf http://localhost:8188/ >/dev/null && echo "ComfyUI up"
```

### 3. Start the distro at Windows boot (Task Scheduler)

WSL only runs when invoked, so a Windows-side trigger boots the distro at startup;
systemd then keeps the service alive. In an **elevated** PowerShell:

```powershell
$action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d lighthouse -u root -e /bin/true"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-lighthouse-boot" -Action $action -Trigger $trigger -Principal $principal
```

(The task just boots the distro; systemd + `Restart=always` keep ComfyUI running.)

### 4. Firewall — allow the cluster to reach :8188

```powershell
# Scope RemoteAddress to the cluster nodes. CONFIRM the Talos node subnet/IPs;
# 10.90.0.0/16 is the core LAN (tighten to node IPs for "allow-only-from-cluster").
New-NetFirewallRule -DisplayName "ComfyUI worker 8188 (cluster)" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8188 -RemoteAddress 10.90.0.0/16
```

### 5. Model present

The worker executes the graph, so it needs the smoke model locally:
`~/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors` (Phase-0 placed SD 1.5;
the workshop fixture uses SDXL base). Per ADR 018 the worker-side fetch-from-
model-serve client will automate this later; for the first smoke, place it
manually.

## Verify the master sees the worker

Once deployed, from the master pod (or any cluster pod):
`curl -sf http://vengeancepc.internal:8188/system_stats` should return JSON. If it
hangs, recheck `--listen`, the firewall rule, and DNS resolution of the
`.internal` name.
