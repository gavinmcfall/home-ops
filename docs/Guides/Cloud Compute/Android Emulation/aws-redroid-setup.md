# Redroid on AWS Graviton (Free Tier)

Run Android containers on AWS Graviton ARM instances with ADB access via Tailscale.

## Prerequisites

- AWS account (free tier eligible)
- Tailscale account
- ADB and scrcpy installed on your local machine

## Why AWS Graviton?

AWS Graviton instances offer:
- **Free tier**: 750 hours/month on t4g.small until December 2026
- **Sydney region**: ~28ms latency from New Zealand vs 280ms from European providers
- **64-bit ARM support**: Works with Redroid's `_64only` images
- **Reliable availability**: Unlike Oracle Cloud's perpetual "out of capacity" issues

## 1. Create AWS EC2 Instance

### Sign Up

1. Go to https://console.aws.amazon.com
2. Create an account (requires credit card for verification)
3. New accounts get 12 months of free tier benefits

### Create Instance

1. Navigate to **EC2** → **Instances** → **Launch instance**
2. Change region to **Asia Pacific (Sydney)** (top right dropdown)
3. Configure:
   - **Name**: `android` (or whatever you prefer)
   - **Application and OS Images**:
     - Select **Ubuntu**
     - Choose **Ubuntu Server 24.04 LTS**
     - Architecture: **64-bit (Arm)**
   - **Instance type**: `t4g.small` (2 vCPU, 2GB RAM - free tier eligible)
   - **Key pair**: Create new or select existing
     - Download the `.pem` file if creating new
   - **Network settings**:
     - Allow SSH traffic from: My IP
     - (Tailscale will handle other access)
   - **Configure storage**: 16-20 GiB gp3
4. Click **Launch instance**

### Note Your Details

- **Public IP**: Shown in instance details (for initial SSH)
- **Instance ID**: For reference

## 2. SSH Setup

Move your key and set permissions:

```bash
mv ~/Downloads/android.pem ~/.ssh/
chmod 600 ~/.ssh/android.pem
```

Add to SSH config (`~/.ssh/config`):

```
Host android
    HostName <public-ip>
    User ubuntu
    IdentityFile ~/.ssh/android.pem
```

Connect:

```bash
ssh android
```

## 3. Initial Server Setup

Update the system:

```bash
sudo apt update && sudo apt upgrade -y
```

## 4. Install Docker

```bash
# Install Docker and kernel modules
sudo apt install -y docker.io linux-modules-extra-$(uname -r)

# Add your user to docker group
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# Verify
docker --version
```

## 5. Setup Binder (Required for Redroid)

Redroid requires the binder kernel module for Android's IPC mechanism.

### Load Binder Module

```bash
# Load binder with required devices
sudo modprobe binder_linux devices=binder,hwbinder,vndbinder
```

### Mount Binderfs

```bash
# Create mount point
sudo mkdir -p /dev/binderfs

# Mount binderfs
sudo mount -t binder binder /dev/binderfs

# Verify
ls -la /dev/binderfs/
# Should show: binder, binder-control, features, hwbinder, vndbinder
```

### Make Persistent Across Reboots

```bash
# Add module to load at boot
echo "binder_linux" | sudo tee -a /etc/modules

# Add fstab entry for binderfs
echo "binder /dev/binderfs binder nofail 0 0" | sudo tee -a /etc/fstab
```

## 6. Install Tailscale

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Authenticate (follow the URL)
sudo tailscale up

# Note your Tailscale IP
tailscale ip -4
```

## 7. Run Redroid

### Important: Use 64-bit Only Images

AWS Graviton (and Oracle A2) instances only support 64-bit ARM binaries. Standard Redroid images include 32-bit components that will cause kernel panics. Use the `_64only` variants:

```bash
# Android 13 (recommended)
docker run -d --name redroid-13 --privileged \
  -p 5555:5555 \
  redroid/redroid:13.0.0_64only-latest

# Watch logs for boot progress
docker logs -f redroid-13
```

### Available 64-bit Only Images

| Android Version | Image Tag |
|-----------------|-----------|
| Android 12 | `redroid/redroid:12.0.0_64only-latest` |
| Android 13 | `redroid/redroid:13.0.0_64only-latest` |
| Android 14 | `redroid/redroid:14.0.0_64only-latest` |
| Android 15 | `redroid/redroid:15.0.0_64only-latest` |
| Android 16 | `redroid/redroid:16.0.0_64only-latest` |

### Verify Boot Completed

```bash
# Check if Android booted successfully
docker exec redroid-13 getprop sys.boot_completed
# Should return: 1

# Check ADB daemon is running
docker exec redroid-13 ps -A | grep adb
# Should show adbd process
```

### Test ADB Locally

```bash
# Install ADB if not present
sudo apt install -y adb

# Connect locally
adb connect localhost:5555

# Verify
adb devices
```

## 8. Connect from Your PC

### WSL2 Setup (Windows)

If using WSL2, you need Tailscale running inside WSL2 (Windows Tailscale doesn't share network with WSL2):

```bash
# Install Tailscale in WSL2
curl -fsSL https://tailscale.com/install.sh | sh

# Start tailscaled (WSL2 doesn't use systemd by default)
sudo tailscaled > /dev/null 2>&1 &

# Authenticate
sudo tailscale up
```

### Install ADB and scrcpy

**Ubuntu/Debian (including WSL2):**
```bash
sudo apt install -y adb scrcpy
```

**macOS:**
```bash
brew install android-platform-tools scrcpy
```

**Windows (native):**
- Download ADB: https://developer.android.com/tools/releases/platform-tools
- Download scrcpy: https://github.com/Genymobile/scrcpy/releases

### Connect via Tailscale

```bash
# Check latency first
tailscale ping <tailscale-ip>
# Example output: pong from aws-android (100.66.154.79) via DERP(syd) in 28ms

# Connect ADB
adb connect <tailscale-ip>:5555

# Verify connection
adb devices

# Launch display
scrcpy -s <tailscale-ip>:5555
```

### scrcpy Options for Remote Use

```bash
# Optimized for remote connections
scrcpy -s <tailscale-ip>:5555 \
  --max-size 1024 \
  --video-bit-rate 4M \
  --max-fps 30 \
  --stay-awake \
  --window-title "Redroid"

# For high latency connections
scrcpy -s <tailscale-ip>:5555 \
  --max-size 800 \
  --video-bit-rate 2M \
  --max-fps 20
```

## 9. Persistence and Management

### Container Auto-Restart

Add `--restart unless-stopped` when creating the container for auto-restart on reboot.

### Managing the Container

```bash
# Stop
docker stop redroid-13

# Start
docker start redroid-13

# Restart
docker restart redroid-13

# View logs
docker logs -f redroid-13

# Shell into Android
adb -s <tailscale-ip>:5555 shell
```

### Data Persistence

To persist app data across container restarts:

```bash
# Create data volume
docker volume create redroid-data

# Run with persistence
docker run -d --name redroid-13 --privileged \
  --restart unless-stopped \
  -p 5555:5555 \
  -v redroid-data:/data \
  redroid/redroid:13.0.0_64only-latest
```

## 10. Troubleshooting

### Container Exits Immediately

```bash
# Check logs for errors
docker logs redroid-13

# Verify binder devices
ls -la /dev/binderfs/

# If missing, reload module
sudo modprobe -r binder_linux
sudo modprobe binder_linux devices=binder,hwbinder,vndbinder
sudo mount -t binder binder /dev/binderfs
```

### ADB Connection Refused

```bash
# Check container is running
docker ps

# Check port is listening
ss -tlnp | grep 5555

# Restart ADB in container
docker exec redroid-13 setprop service.adb.tcp.port 5555
docker exec redroid-13 stop adbd
docker exec redroid-13 start adbd
```

### Docker Logs Empty

This is normal. Redroid redirects init output to `/dev/kmsg` instead of stdout. Check boot status with:

```bash
docker exec redroid-13 getprop sys.boot_completed
```

### High Latency

```bash
# Check Tailscale connection
tailscale ping <tailscale-ip>

# Use lower quality settings in scrcpy
scrcpy -s <tailscale-ip>:5555 --max-size 800 --video-bit-rate 2M
```

## Quick Reference

| Action | Command |
|--------|---------|
| Check latency | `tailscale ping <ts-ip>` |
| Connect ADB | `adb connect <ts-ip>:5555` |
| Display | `scrcpy -s <ts-ip>:5555` |
| Shell | `adb -s <ts-ip>:5555 shell` |
| Install APK | `adb -s <ts-ip>:5555 install app.apk` |
| Push file | `adb -s <ts-ip>:5555 push local.txt /sdcard/` |
| Pull file | `adb -s <ts-ip>:5555 pull /sdcard/file.txt ./` |
| Screenshot | `adb -s <ts-ip>:5555 exec-out screencap -p > screen.png` |
| Container logs | `docker logs -f redroid-13` |
| Boot status | `docker exec redroid-13 getprop sys.boot_completed` |
| Restart container | `docker restart redroid-13` |

## Cost Considerations

| Resource | Free Tier Allowance | Notes |
|----------|---------------------|-------|
| t4g.small | 750 hours/month | Enough for 24/7 operation |
| EBS storage | 30 GB/month | 16-20GB is plenty for Redroid |
| Data transfer | 100 GB/month outbound | scrcpy uses minimal bandwidth |

The free tier runs until December 2026 for new accounts. After that, t4g.small costs approximately $0.0168/hour (~$12/month) in ap-southeast-2.
