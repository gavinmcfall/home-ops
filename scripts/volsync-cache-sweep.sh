#!/bin/bash
# VolSync Kopia cache PVC sweep
#
# Deletes NFS-side VolSync cache PVCs whose size does not match the size their
# ReplicationSource now requests. VolSync recreates them at the correct size on
# the next sync.
#
# Why this is needed: cache PVCs live on openebs-hostpath, which does not support
# volume expansion. Any change to a cache PVC's requested size wedges the mover with
#   "forbidden: only dynamically provisioned pvc can be resized and the
#    storageclass that provisions the pvc must support resize"
# and the only remedy is to delete the PVC so it gets recreated.
#
# Run this immediately after merging a change to cacheCapacity in
# components/volsync/nfs-truenas*/replicationsource.yaml.
#
# Deleting a cache PVC loses no backup data — the Kopia repository lives on
# NFS/B2. The next sync re-downloads index/metadata and so runs slower once.
#
# Usage: ./volsync-cache-sweep.sh [--apply]     (default is a dry run)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

if [[ "$APPLY" == false ]]; then
    echo -e "${YELLOW}DRY RUN${NC} — pass --apply to actually delete. Nothing will be changed."
fi
echo ""

deleted=0
skipped=0

# Only NFS-side sources. The -b2 sources already use VOLSYNC_CACHE_CAPACITY and
# their caches are correctly sized, so they are deliberately left alone — they are
# also the safety net that keeps backups running during this sweep.
while read -r ns name; do
    [[ "$name" == *-b2 ]] && continue

    want=$(kubectl get replicationsource "$name" -n "$ns" -o jsonpath='{.spec.kopia.cacheCapacity}' 2>/dev/null || true)
    pvc="volsync-src-${name}-cache"
    have=$(kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || true)

    if [[ -z "$have" ]]; then
        echo -e "  ${YELLOW}-${NC} $ns/$pvc: no cache PVC yet, nothing to do"
        continue
    fi

    # Never delete on a missing or malformed target size. An empty $want means the
    # API call failed or the source is not on kopia -- either way it would compare
    # unequal to $have and delete a cache we have no instruction to touch.
    if ! [[ "$want" =~ ^[0-9]+(Mi|Gi|Ti)$ ]]; then
        echo -e "  ${YELLOW}!${NC} $ns/$name: could not read a valid cacheCapacity (got '${want}') — skipping"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$want" == "$have" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    echo -e "  ${RED}✗${NC} $ns/$pvc: has $have, source wants $want"
    if [[ "$APPLY" == true ]]; then
        # A mover pod may hold the PVC; the pvc-protection finalizer clears once it exits.
        kubectl delete pvc "$pvc" -n "$ns" --wait=false >/dev/null
        echo -e "    ${GREEN}→${NC} deleted, will be recreated at $want on next sync"
    fi
    deleted=$((deleted + 1))
done < <(kubectl get replicationsource -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name')

echo ""
echo "Already correct: $skipped"
if [[ "$APPLY" == true ]]; then
    echo -e "${GREEN}Deleted: $deleted${NC} — run scripts/volsync-drift-check.sh after the next sync cycle to confirm."
else
    echo -e "${YELLOW}Would delete: $deleted${NC} — re-run with --apply."
fi
