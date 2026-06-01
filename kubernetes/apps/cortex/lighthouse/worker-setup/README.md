# GPU worker bring-up — autostart + drive placement

Per-worker runbook to take a Phase-0 box (WSL2 `lighthouse` distro that can render)
to a **production GPU worker**: ComfyUI starts on boot with the right flags, the
distro lives on a roomy drive (not C:), and the cluster master can reach it.

Proven on **VengeancePC 2026-06-01**. Run the same on **VixenPC** (heavy tier) and
**Nova/Blaze** (light tier, RTX 3050 8 GB).

**Not a Flux resource** — `worker-setup/` is outside the Flux Kustomization path
(`../app`); these are host-side ops artifacts for the Windows/WSL2 workers.

> All PowerShell commands assume the distro is named `lighthouse`. All in-distro
> commands assume ComfyUI at `~/ComfyUI` with its venv at `~/ComfyUI/.venv` (the
> Phase-0 layout). `wsl ... -- <cmd>` runs **without** going through `login`, so it
> works even before the pam fix in step 1.

---

## 0. Prereq

Phase-0 done on the box: WSL2 `lighthouse` distro + CUDA toolkit + ComfyUI renders
(see `phase-0-worker-install.md` in the lighthouse repo). Everything below builds on that.

---

## 1. Pre-flight — fix the Ubuntu 24.04 login crash (`pam_lastlog`)

**Symptom:** opening the WSL terminal tab shows `[process exited with code 1]` then
"press Enter to restart." **Cause:** Ubuntu 24.04 removed `pam_lastlog.so`, but
`/etc/pam.d/login` still references it, so the interactive `login` path fails.
(ComfyUI and `wsl -- <cmd>` are unaffected — they bypass `login`.)

Run in **PowerShell** (note: `wsl -- <cmd>` form, no nested quotes — that's what
trips people up):

```powershell
wsl -d lighthouse --user root -- cp /etc/pam.d/login /etc/pam.d/login.bak
wsl -d lighthouse --user root -- sed -i "/pam_lastlog/s/^/#/" /etc/pam.d/login
wsl -d lighthouse --user root -- grep -n pam_lastlog /etc/pam.d/login   # → 82:#session ... pam_lastlog.so
```

Revert if ever needed: `wsl -d lighthouse --user root -- mv /etc/pam.d/login.bak /etc/pam.d/login`

---

## 1b. Enable mirrored WSL networking (so the LAN/cluster can reach :8188)

**Required for the cluster to reach the worker.** By default WSL2 runs the distro
behind NAT, so ComfyUI on `:8188` is NOT reachable on the PC's LAN IP — a cluster
`curl http://<host>.internal:8188/...` just **hangs**. Mirrored mode shares the
host's network interfaces, putting `:8188` directly on the LAN IP. (Needs Windows
11 22H2+.)

> ⚠️ **fstab pre-flight (do not skip).** `.wslconfig` is **global to every WSL2
> distro** on the Windows user, and mirrored mode can break a **network mount
> (NFS/CIFS) in `/etc/fstab`** → next boot hangs in `mount -a` and the distro won't
> start (this bricked the home-ops distro on VengeancePC 2026-05-28; recovery needs a
> rescue distro). Check **every** distro on the box first:
> ```powershell
> wsl -l -v    # list all distro names
> # for EACH name:
> wsl -d <distro> --user root -- sh -c "echo '== fstab =='; grep -vE '^\s*#|^\s*$' /etc/fstab; echo '== wsl.conf =='; cat /etc/wsl.conf 2>/dev/null"
> ```
> No `nfs`/`cifs` lines anywhere → safe to proceed. If a network mount exists, first
> make it mirrored-safe (`vers=3,proto=tcp,mountproto=tcp,noresvport,x-systemd.automount`)
> or set `[automount] mountFsTab=false` in that distro's `/etc/wsl.conf`, and back up
> `/etc/fstab`.

Check for an existing `.wslconfig` — if present it likely has memory/swap/processor
settings you must **not** clobber:

```powershell
Get-Content "$env:USERPROFILE\.wslconfig" -ErrorAction SilentlyContinue
```

- **No file** → create it:
  ```powershell
  "[wsl2]`r`nnetworkingMode=mirrored" | Set-Content "$env:USERPROFILE\.wslconfig" -Encoding ascii
  ```
- **File exists with a `[wsl2]` section** → **append** the line (don't overwrite):
  ```powershell
  Add-Content "$env:USERPROFILE\.wslconfig" "networkingMode=mirrored"
  Get-Content "$env:USERPROFILE\.wslconfig"   # confirm your existing settings are intact
  ```

Apply + verify **every** distro still boots (catches an fstab hang per-distro before
you rely on it):

```powershell
wsl --shutdown                       # can combine with the step-2 move
wsl -d lighthouse -- echo ok         # boots under mirrored; repeat for any other distro on the box
wsl -d lighthouse --user root -- hostname -I   # expect a 10.90.x LAN address in the list
```

> Recovery if a distro hangs on boot after this: export → unregister → mount the VHD
> from a rescue Ubuntu distro → fix `/etc/fstab` + `/etc/wsl.conf` → import-in-place.
> (Full recipe in the `C--Users-gavin-temp` memory project, `reference-wsl-distro-recovery-via-rescue`.)

---

## 2. (Recommended) Move the distro off C: to a bigger drive

Models are large, and `~/ComfyUI/models` lives **inside the distro's `ext4.vhdx`**.
By default that VHDX is on C:. Move the whole distro to a roomy drive **before**
placing models (smaller, faster move). Replace `D:` with whatever drive has space
on that box (`Get-PSDrive -PSProvider FileSystem` to check).

> **Do NOT** symlink `~/ComfyUI/models` to `/mnt/d/...`. WSL reads Windows drives
> over a slow 9P layer and safetensors uses mmap — large model loads are painful and
> flaky. Move the distro so models sit on **native ext4**.

**Find where it lives now:**

```powershell
(Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object DistributionName -eq 'lighthouse').BasePath
```

**Move it** (PowerShell):

```powershell
wsl --shutdown
wsl --manage lighthouse --move "D:\wsl\lighthouse"
wsl -l -v
```

> ⚠️ **`wsl --shutdown`, not just `--terminate`.** All WSL2 distros share one VM, so
> `--move` can't get exclusive access while *any* distro is running — `--terminate
> lighthouse` alone gives `ERROR_SHARING_VIOLATION`. `--shutdown` stops the whole WSL
> VM (every distro), which is what `--move` needs. If you're running another Claude
> Code / WSL session, `--shutdown` will drop it too — that's expected; just relaunch.
> If the sharing violation persists after `--shutdown`, wait ~10 s and retry (AV can
> hold the VHDX briefly).

**Verify it landed** (and that ComfyUI + the model dir are now on the new drive):

```powershell
(Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object DistributionName -eq 'lighthouse').BasePath   # → D:\wsl\lighthouse
wsl -d lighthouse --user gavin -- df -h /                                  # root should be the big volume
```

---

## 3. Run ComfyUI as a boot service (systemd)

### 3a. Enable systemd in the distro

Ensure `/etc/wsl.conf` has the `[boot]` block (skip if already present):

```powershell
wsl -d lighthouse --user root -- bash -c "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null || printf '[boot]\nsystemd=true\n' >> /etc/wsl.conf"
wsl --terminate lighthouse        # applies on next start
```

### 3b. Install + enable the service

Copy `comfyui-worker.service` (in this folder) into the distro and substitute the
service user. From a shell **inside the distro** (`wsl -d lighthouse`):

```bash
sudo cp /mnt/c/Users/<you>/Downloads/comfyui-worker.service /etc/systemd/system/comfyui-worker.service
# Paste the next line EXACTLY — `<WSL_USER>` is the literal placeholder to find;
# $USER auto-fills the current user. Do NOT type your own name on the left side.
sudo sed -i "s|<WSL_USER>|$USER|g" /etc/systemd/system/comfyui-worker.service
grep -E "^User=|^ExecStart=" /etc/systemd/system/comfyui-worker.service   # verify: no "<WSL_USER>" left
sudo systemctl daemon-reload
sudo systemctl enable --now comfyui-worker.service
systemctl status comfyui-worker.service        # → active (running)
curl -sf http://localhost:8188/ >/dev/null && echo "ComfyUI up"
```

> If `status` shows `(code=exited, status=217/USER)`, the `<WSL_USER>` placeholder
> wasn't replaced — the `sed` search string must be `<WSL_USER>`, not your username.
> Re-run the `sed` + `daemon-reload` + `restart`.

The unit launches ComfyUI with `--listen 0.0.0.0 --enable-cors-header` (both
**required** for a ComfyUI-Distributed remote worker) and `Restart=always`.

### 3c. Start the distro at Windows boot (Task Scheduler)

WSL only runs when invoked, so a Windows-side trigger boots the distro at startup;
systemd then keeps the service alive. **Elevated** PowerShell:

```powershell
$action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d lighthouse -u root -e /bin/true"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-lighthouse-boot" -Action $action -Trigger $trigger -Principal $principal
```

### 3d. Firewall — allow the cluster to reach :8188

```powershell
# Scope RemoteAddress to the cluster. 10.90.0.0/16 is the core LAN; tighten to the
# Talos node IPs for strict "allow-only-from-cluster".
New-NetFirewallRule -DisplayName "ComfyUI worker 8188 (cluster)" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8188 -RemoteAddress 10.90.0.0/16
```

---

## 4. Place the model(s)

The worker executes the graph, so it needs the workflow's model locally:

```bash
cd ~/ComfyUI/models/checkpoints
# Heavy tier (Vengeance/Vixen, 4080S 16 GB) — the workshop smoke fixture's model:
wget -O sd_xl_base_1.0.safetensors \
  https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

> **Light tier (Nova/Blaze, 3050 8 GB):** use SD 1.5, not SDXL (SDXL is borderline on
> 8 GB). The model a worker needs == whatever the curated workflow references.
> Per ADR 018 the worker-side fetch-from-`model-serve` client will automate this
> later; for now place it manually.

---

## 5. Verify the master can reach the worker

Once deployed, from any cluster pod:

```bash
curl -sf http://vengeancepc.internal:8188/system_stats   # (or vixenpc.internal, pc-nova.internal, pc-blaze.internal)
```

JSON back = good. If it hangs: recheck `--listen` (step 3b), the firewall rule
(3d), and that the `.internal` name resolves to the box's LAN IP.

---

## Worker → DNS name map (from cluster-deploy-contract)

| Box | DNS hostname | Tier |
|---|---|---|
| Vengeance | `vengeancepc.internal` | heavy |
| Vixen | `vixenpc.internal` | heavy |
| Nova | `pc-nova.internal` | light (deferred) |
| Blaze | `pc-blaze.internal` | light (deferred) |

Worker registration is **static** — the cluster master already lists all workers in
its `gpu_config.json` (`master_delegate_only: true`); there's no auto-discovery. A
worker is "active" the moment it's a running ComfyUI reachable at its `:8188`.
