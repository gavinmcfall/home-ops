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

## 2. (Optional) Move the distro off C: to a bigger drive

Models live **inside the distro's `ext4.vhdx`**, which sits on C: by default. Moving
the distro keeps a big SDXL library off C:. **Only worth it on the heavy boxes** —
the kids' light-tier boxes hold one ~4 GB SD-1.5 model, so if C: has space, **skip
this step on them.** Check space with `Get-PSDrive -PSProvider FileSystem`; replace
`D:` below with whatever drive has room.

Do the move **while the distro is fresh/empty** (before CUDA/ComfyUI) if you can —
it's smaller and faster.

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
wsl -d lighthouse --user root -- df -h /                                   # root fs should be the big volume
```

> **If `--move` fails with `ERROR_FILE_NOT_FOUND`:** some distro layouts park the
> `ext4.vhdx` away from the registry `BasePath`, and `--move`/`--export` can't find
> it. **Do not keep retrying `--move`** — it can leave the distro registered but
> disk-less (boot then fails `attach disk … ERROR_FILE_NOT_FOUND`, and the vhdx may
> be gone). If C: has space, just **leave it on C:**. If you must relocate, the
> bulletproof method on a *healthy* distro is export → re-register in place:
> ```powershell
> wsl --shutdown
> New-Item -ItemType Directory -Force -Path "D:\wsl\lighthouse" | Out-Null
> wsl --export --vhd lighthouse "D:\wsl\lighthouse\ext4.vhdx"
> Get-Item "D:\wsl\lighthouse\ext4.vhdx"          # CONFIRM a real, multi-GB file BEFORE the next line
> wsl --unregister lighthouse
> wsl --import-in-place lighthouse "D:\wsl\lighthouse\ext4.vhdx"
> ```
> Cheapest of all: do the relocation on a **fresh empty distro** (install with
> `--no-launch`, move, *then* set up) so a failure costs nothing.

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

### 3c. Boot autostart — ⚠️ the old SYSTEM task is BROKEN; rely on sleep/wake

> **Correction 2026-06-05 (verified live on Nova + Blaze):** the SYSTEM /
> `-AtStartup` task this section used to document **does not work** — and the
> design doesn't need it.

**Why it's broken:** WSL2 distros are registered **per Windows user**. `lighthouse`
belongs to the box's user (`kieran` on Nova, `ariana` on Blaze); the **SYSTEM**
account can't see it, so `wsl -d lighthouse …` as SYSTEM is a silent no-op (distro
never starts; `LastTaskResult` may still read `0`). Separately,
`wsl -d lighthouse -e /bin/true` boots the distro, runs `true`, and WSL tears it
down seconds later — `systemd=true` alone does **not** hold it up; only a **held
process** (`-e sleep infinity`) or active use does.

**What we actually do (the design):** workers run **sleep/wake, not boot/shutdown**.
Start the distro once (`wsl -d lighthouse`), then sleep/wake the PC — the distro +
`comfyui-worker.service` survive sleep (CUDA-resume restores the GPU), so no
autostart task is needed for normal operation. After a *rare hard reboot*, start it
manually; robust unattended-after-reboot lifecycle is **Plan 2's wol-agent**.

**If you ever do need true headless-on-boot:** it must run as the **owning user**
(not SYSTEM), with **"run whether user is logged on or not"** (stored creds → no
window) **and** a keep-alive (`-e sleep infinity`). MS-account users make the
stored-cred path painful (`MicrosoftAccount\you@email` + real password; Hello PIN
won't work). Cleaner alternatives: auto-login + a hidden launcher
(`conhost --headless` / VBS `Run(...,0)`) at logon, or **NSSM** wrapping WSL as a
Windows service. Don't re-add the SYSTEM task.

### 3d. Firewall — allow the cluster to reach :8188

```powershell
# Allow only the cluster node IPs (master pod egress SNATs to the node it runs on;
# it can run on any node). Tighter than the whole LAN.
New-NetFirewallRule -DisplayName "ComfyUI worker 8188 (cluster)" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8188 `
  -RemoteAddress @("10.90.3.101","10.90.3.102","10.90.3.103")
```

> **Verify-source-first:** before adding any *blocking* rule, run a render and watch
> the worker's ComfyUI console for the incoming source IP — confirm it's one of the
> node IPs above, so you don't cut off dispatch. And **keep `--enable-cors-header`**
> in the worker launch — the master's dispatch requires it (bypasses ComfyUI's
> Origin/Host check); do NOT remove it as "hardening".

---

## 4. Place the model(s) — **match the model to the tier**

The worker executes the graph, so it needs the workflow's model locally. **Which
model depends on the box's GPU — do NOT put SDXL on the 3050s.**

**Heavy tier (Vengeance / Vixen, RTX 4080S 16 GB)** — SDXL base (the workshop smoke
fixture's model):

```bash
cd ~/ComfyUI/models/checkpoints
wget -O sd_xl_base_1.0.safetensors \
  https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

**Light tier (Nova / Blaze, RTX 3050 8 GB)** — SD 1.5 **only**. SDXL (~7 GB) will OOM
an 8 GB card. SD 1.5 is ~4 GB and fits comfortably:

```bash
cd ~/ComfyUI/models/checkpoints
wget -O v1-5-pruned-emaonly.safetensors \
  https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors
```

> ⚠️ **Light-tier boxes stay OUT of the master's `gpu_config.json` worker pool for
> now.** ComfyUI-Distributed fans every job out to **all enabled workers with no
> per-job tier routing** — so if a 3050 is in the pool and an SDXL job runs, it gets
> handed work it can't fit and the render fails. Mixing tiers in one pool **breaks**
> the heavy-tier smoke rather than helping it. The kids' boxes are valid prep, but
> they only join the pool once there's tier-aware dispatch and/or SD-1.5-only
> workflows (the "light tier deferred" milestone line). Per ADR 018 the worker-side
> fetch-from-`model-serve` client will automate model placement later; for now place
> it manually.

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

Worker registration is **static** — workers only participate when listed in the
master's `gpu_config.json` (`master_delegate_only: true`) **and** reachable on
`:8188`; there's no auto-discovery, and adding a box to the LAN does NOT auto-enroll
it. **`gpu_config.json` currently lists only the two heavy workers
(`vengeancepc.internal`, `vixenpc.internal`).** The light boxes (`pc-nova.internal`,
`pc-blaze.internal`) are intentionally absent — see the tier warning in step 4: a
3050 in the pool would be handed SDXL jobs it can't fit. They get added when
light-tier routing exists.
