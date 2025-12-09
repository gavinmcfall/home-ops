# ZFS Library Dataset Migration Guide

This guide covers migrating the `/mnt/storage0/media/Library` folder to a dedicated ZFS dataset with child datasets for granular disk usage tracking via Prometheus metrics.

## Purpose

By creating ZFS datasets for each media category (Movies, Television, Books, etc.), you gain:
- Per-category disk usage metrics in Prometheus/Grafana
- Independent snapshot capabilities
- Granular quota management if needed
- Better visibility into storage consumption patterns

## Prerequisites

- TrueNAS Scale with graphite exporter configured
- Access to TrueNAS UI or CLI
- Kubernetes cluster access with kubectl
- ~30 minutes of downtime for all media-related services

## Affected Applications

The following 32 applications mount `/mnt/storage0/media` via NFS and must be scaled down:

### downloads namespace
- bazarr, bazarr-foreign, bazarr-uhd
- cross-seed, kapowarr, metube
- qbittorrent, sabnzbd, unpackerr
- radarr, radarr-uhd, readarr
- whisparr, sonarr, sonarr-foreign, sonarr-uhd

### entertainment namespace
- audiobookshelf, calibre-web
- fileflows-server, fileflows-node
- immich, jellyfin, kavita
- peertube, plex, stash

### games namespace
- romm

### home namespace
- filebrowser, manyfold, paperless

### home-automation namespace
- n8n

### storage namespace
- kopia, syncthing, volsync

## Migration Steps

### Phase 1: Scale Down All Services

Run these commands to scale down all affected deployments:

```bash
# downloads namespace
kubectl scale deployment -n downloads bazarr --replicas=0
kubectl scale deployment -n downloads bazarr-foreign --replicas=0
kubectl scale deployment -n downloads bazarr-uhd --replicas=0
kubectl scale deployment -n downloads cross-seed --replicas=0
kubectl scale deployment -n downloads kapowarr --replicas=0
kubectl scale deployment -n downloads metube --replicas=0
kubectl scale deployment -n downloads qbittorrent --replicas=0
kubectl scale deployment -n downloads sabnzbd --replicas=0
kubectl scale deployment -n downloads unpackerr --replicas=0
kubectl scale deployment -n downloads radarr --replicas=0
kubectl scale deployment -n downloads radarr-uhd --replicas=0
kubectl scale deployment -n downloads readarr --replicas=0
kubectl scale deployment -n downloads whisparr --replicas=0
kubectl scale deployment -n downloads sonarr --replicas=0
kubectl scale deployment -n downloads sonarr-foreign --replicas=0
kubectl scale deployment -n downloads sonarr-uhd --replicas=0

# entertainment namespace
kubectl scale deployment -n entertainment audiobookshelf --replicas=0
kubectl scale deployment -n entertainment calibre-web --replicas=0
kubectl scale deployment -n entertainment fileflows-server --replicas=0
kubectl scale deployment -n entertainment fileflows-node --replicas=0
kubectl scale deployment -n entertainment immich-server --replicas=0
kubectl scale deployment -n entertainment immich-machine-learning --replicas=0
kubectl scale deployment -n entertainment jellyfin --replicas=0
kubectl scale deployment -n entertainment kavita --replicas=0
kubectl scale deployment -n entertainment peertube --replicas=0
kubectl scale deployment -n entertainment plex --replicas=0
kubectl scale deployment -n entertainment stash --replicas=0

# games namespace
kubectl scale deployment -n games romm --replicas=0

# home namespace
kubectl scale deployment -n home filebrowser --replicas=0
kubectl scale deployment -n home manyfold --replicas=0
kubectl scale deployment -n home paperless --replicas=0

# home-automation namespace
kubectl scale deployment -n home-automation n8n --replicas=0

# storage namespace
kubectl scale deployment -n storage kopia --replicas=0
kubectl scale deployment -n storage syncthing --replicas=0
kubectl scale deployment -n storage volsync --replicas=0
```

Verify all pods are terminated:
```bash
kubectl get pods -A | grep -E "downloads|entertainment|games|storage" | grep -v Completed
```

### Phase 2: Create Datasets in TrueNAS

#### Option A: Via TrueNAS UI

1. Go to **Datasets** in the left sidebar
2. Select the `storage0/media` dataset
3. Click **Add Dataset**
4. Create `Library` dataset with these settings:
   - Name: `Library`
   - Sync: Standard
   - Compression: lz4 (inherit or set explicitly)
   - Enable Atime: Off
   - Record Size: 1M (good for media files)

5. After creating `Library`, select it and create child datasets for each category:
   - `3DModels`
   - `Anime`
   - `Books`
   - `Education`
   - `Emulation`
   - `Images`
   - `Movies`
   - `Movies - Horror`
   - `Movies - UHD`
   - `Private`
   - `Tdarr`
   - `Tdarr - Output`
   - `Television`
   - `Television - Foreign`
   - `Television - UHD`

#### Option B: Via CLI (SSH to TrueNAS)

```bash
# Create parent Library dataset
zfs create storage0/media/Library

# Create child datasets for each category
zfs create "storage0/media/Library/3DModels"
zfs create "storage0/media/Library/Anime"
zfs create "storage0/media/Library/Books"
zfs create "storage0/media/Library/Education"
zfs create "storage0/media/Library/Emulation"
zfs create "storage0/media/Library/Images"
zfs create "storage0/media/Library/Movies"
zfs create "storage0/media/Library/Movies - Horror"
zfs create "storage0/media/Library/Movies - UHD"
zfs create "storage0/media/Library/Private"
zfs create "storage0/media/Library/Tdarr"
zfs create "storage0/media/Library/Tdarr - Output"
zfs create "storage0/media/Library/Television"
zfs create "storage0/media/Library/Television - Foreign"
zfs create "storage0/media/Library/Television - UHD"
```

### Phase 3: Migrate Data

Once the datasets are created, the original folders are "hidden" behind the new empty mountpoints. You need to move the data:

```bash
# SSH into TrueNAS

# For each category, move data from the hidden original to the new dataset
# The original data is now accessible via .zfs/snapshot or by temporarily unmounting

# Method: Use zfs rename if data was in child datasets, or rsync if folders
# Since these were folders (not datasets), use rsync:

cd /mnt/storage0/media

# Temporarily rename the new Library dataset mountpoint
zfs set mountpoint=/mnt/storage0/media/Library-new storage0/media/Library

# Now original Library folder is visible again
# Move each folder's contents to the corresponding dataset

rsync -avP /mnt/storage0/media/Library/3DModels/ /mnt/storage0/media/Library-new/3DModels/
rsync -avP /mnt/storage0/media/Library/Anime/ /mnt/storage0/media/Library-new/Anime/
rsync -avP /mnt/storage0/media/Library/Books/ /mnt/storage0/media/Library-new/Books/
rsync -avP /mnt/storage0/media/Library/Education/ /mnt/storage0/media/Library-new/Education/
rsync -avP /mnt/storage0/media/Library/Emulation/ /mnt/storage0/media/Library-new/Emulation/
rsync -avP /mnt/storage0/media/Library/Images/ /mnt/storage0/media/Library-new/Images/
rsync -avP /mnt/storage0/media/Library/Movies/ /mnt/storage0/media/Library-new/Movies/
rsync -avP "/mnt/storage0/media/Library/Movies - Horror/" "/mnt/storage0/media/Library-new/Movies - Horror/"
rsync -avP "/mnt/storage0/media/Library/Movies - UHD/" "/mnt/storage0/media/Library-new/Movies - UHD/"
rsync -avP /mnt/storage0/media/Library/Private/ /mnt/storage0/media/Library-new/Private/
rsync -avP /mnt/storage0/media/Library/Tdarr/ /mnt/storage0/media/Library-new/Tdarr/
rsync -avP "/mnt/storage0/media/Library/Tdarr - Output/" "/mnt/storage0/media/Library-new/Tdarr - Output/"
rsync -avP /mnt/storage0/media/Library/Television/ /mnt/storage0/media/Library-new/Television/
rsync -avP "/mnt/storage0/media/Library/Television - Foreign/" "/mnt/storage0/media/Library-new/Television - Foreign/"
rsync -avP "/mnt/storage0/media/Library/Television - UHD/" "/mnt/storage0/media/Library-new/Television - UHD/"

# After verification, remove old Library folder and restore mountpoint
rm -rf /mnt/storage0/media/Library
zfs set mountpoint=/mnt/storage0/media/Library storage0/media/Library
```

**Important**: The rsync commands may take a very long time depending on data size. Consider running in a tmux/screen session.

### Phase 4: Verify Dataset Structure

```bash
zfs list -r storage0/media/Library
```

Expected output shows each dataset with its own USED column:
```
NAME                                    USED  AVAIL  REFER  MOUNTPOINT
storage0/media/Library                  10T   20T    96K    /mnt/storage0/media/Library
storage0/media/Library/Movies           5T    20T    5T     /mnt/storage0/media/Library/Movies
storage0/media/Library/Television       3T    20T    3T     /mnt/storage0/media/Library/Television
...
```

### Phase 5: Scale Up All Services

```bash
# downloads namespace
kubectl scale deployment -n downloads bazarr --replicas=1
kubectl scale deployment -n downloads bazarr-foreign --replicas=1
kubectl scale deployment -n downloads bazarr-uhd --replicas=1
kubectl scale deployment -n downloads cross-seed --replicas=1
kubectl scale deployment -n downloads kapowarr --replicas=1
kubectl scale deployment -n downloads metube --replicas=1
kubectl scale deployment -n downloads qbittorrent --replicas=1
kubectl scale deployment -n downloads sabnzbd --replicas=1
kubectl scale deployment -n downloads unpackerr --replicas=1
kubectl scale deployment -n downloads radarr --replicas=1
kubectl scale deployment -n downloads radarr-uhd --replicas=1
kubectl scale deployment -n downloads readarr --replicas=1
kubectl scale deployment -n downloads whisparr --replicas=1
kubectl scale deployment -n downloads sonarr --replicas=1
kubectl scale deployment -n downloads sonarr-foreign --replicas=1
kubectl scale deployment -n downloads sonarr-uhd --replicas=1

# entertainment namespace
kubectl scale deployment -n entertainment audiobookshelf --replicas=1
kubectl scale deployment -n entertainment calibre-web --replicas=1
kubectl scale deployment -n entertainment fileflows-server --replicas=1
kubectl scale deployment -n entertainment fileflows-node --replicas=1
kubectl scale deployment -n entertainment immich-server --replicas=1
kubectl scale deployment -n entertainment immich-machine-learning --replicas=1
kubectl scale deployment -n entertainment jellyfin --replicas=1
kubectl scale deployment -n entertainment kavita --replicas=1
kubectl scale deployment -n entertainment peertube --replicas=1
kubectl scale deployment -n entertainment plex --replicas=1
kubectl scale deployment -n entertainment stash --replicas=1

# games namespace
kubectl scale deployment -n games romm --replicas=1

# home namespace
kubectl scale deployment -n home filebrowser --replicas=1
kubectl scale deployment -n home manyfold --replicas=1
kubectl scale deployment -n home paperless --replicas=1

# home-automation namespace
kubectl scale deployment -n home-automation n8n --replicas=1

# storage namespace
kubectl scale deployment -n storage kopia --replicas=1
kubectl scale deployment -n storage syncthing --replicas=1
kubectl scale deployment -n storage volsync --replicas=1
```

### Phase 6: Verify Services

```bash
# Check all pods are running
kubectl get pods -A | grep -E "downloads|entertainment|games|storage|home" | grep -v Completed

# Test a few apps via their web interfaces
# - Plex: Check libraries are accessible
# - Radarr/Sonarr: Verify root folders are valid
# - Jellyfin: Confirm media is visible
```

## Prometheus Metrics

After migration, the graphite exporter will expose metrics for each dataset:

```promql
# Query individual dataset usage
truenas_zfs_dataset_used_bytes{dataset="storage0/media/Library/Movies"}
truenas_zfs_dataset_used_bytes{dataset="storage0/media/Library/Television"}

# Compare all Library datasets
truenas_zfs_dataset_used_bytes{dataset=~"storage0/media/Library/.*"}
```

## Rollback Plan

If issues occur, you can reverse the migration:

1. Scale down all services (Phase 1 commands)
2. Move data back from datasets to folders
3. Destroy the datasets: `zfs destroy -r storage0/media/Library`
4. Scale up services (Phase 5 commands)

## Estimated Timeline

| Phase | Duration |
|-------|----------|
| Scale down | 5 minutes |
| Create datasets | 10 minutes |
| Data migration | 2-8 hours (depends on data size) |
| Verification | 10 minutes |
| Scale up | 5 minutes |
| Service verification | 10 minutes |

**Total**: Plan for 3-9 hours depending on data volume.

## Notes

- NFS mounts automatically include child datasets - no Kubernetes config changes needed
- Apps will see the same paths (`/media/Library/Movies`) after migration
- Consider running migration during off-hours to minimize user impact
- Volsync must be scaled down to prevent backup jobs from running during migration
