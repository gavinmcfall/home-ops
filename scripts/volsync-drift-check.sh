#!/bin/bash
# VolSync drift check
#
# Catches the classes of VolSync failure that are silent — the ones where Flux
# reports "applied" and the dashboards look fine, but a restore would fail or a
# backup has quietly stopped running.
#
# Checks:
#   1. Mover drift        — any RS/RD not on the kopia mover (pre-migration restic leftovers)
#   2. Dead repo secret   — RS/RD pointing at a repository secret that no longer exists
#   3. Orphan RDs         — a ReplicationDestination with no matching ReplicationSource
#                           (app removed/replaced; the RD and its snapshots linger)
#   4. Cache size drift   — cache PVC size != the size its RS requests. openebs-hostpath
#                           cannot expand, so this wedges the mover permanently.
#   5. Stale sources      — RS in Error, or no successful sync in over 24h
#
# Exit code is non-zero if anything is found, so this is safe to wire into CI or a
# CronJob later.
#
# Usage: ./volsync-drift-check.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

findings=0
note() { echo -e "  ${RED}✗${NC} $1"; findings=$((findings + 1)); }

echo "=== VOLSYNC DRIFT CHECK ==="
echo "Generated: $(date)"
echo ""

# ---------------------------------------------------------------------------
echo "1. Mover drift (expect kopia everywhere)"
for kind in replicationsource replicationdestination; do
    while read -r ns name; do
        # .spec.kopia is absent if the live object is still on restic/rsync.
        if ! kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.kopia}' 2>/dev/null | grep -q .; then
            mover=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.restic}' 2>/dev/null | grep -q . && echo restic || echo unknown)
            note "$ns/$name ($kind) is on mover '$mover', not kopia"
        fi
    done < <(kubectl get "$kind" -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)
done
[[ $findings -eq 0 ]] && echo -e "  ${GREEN}✓${NC} all sources and destinations on kopia"
echo ""

# ---------------------------------------------------------------------------
before=$findings
echo "2. Dead repository secrets"
for kind in replicationsource replicationdestination; do
    while read -r ns name; do
        secret=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.kopia.repository}' 2>/dev/null || true)
        [[ -z "$secret" ]] && continue
        if ! kubectl get secret "$secret" -n "$ns" >/dev/null 2>&1; then
            note "$ns/$name ($kind) references missing secret '$secret'"
        fi
    done < <(kubectl get "$kind" -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)
done
[[ $findings -eq $before ]] && echo -e "  ${GREEN}✓${NC} all repository secrets exist"
echo ""

# ---------------------------------------------------------------------------
before=$findings
echo "3. Orphan ReplicationDestinations"
while read -r ns name; do
    # RDs are named <app>-dst and pair with an RS named <app>.
    app="${name%-dst}"
    if ! kubectl get replicationsource "$app" -n "$ns" >/dev/null 2>&1; then
        snaps=$(kubectl get volumesnapshot -n "$ns" --no-headers 2>/dev/null | grep -c "volsync-${app}-dst" || true)
        note "$ns/$name has no matching ReplicationSource '$app' (${snaps} snapshot(s) held)"
    fi
done < <(kubectl get replicationdestination -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)
[[ $findings -eq $before ]] && echo -e "  ${GREEN}✓${NC} every destination has a live source"
echo ""

# ---------------------------------------------------------------------------
before=$findings
echo "4. Cache size drift (openebs-hostpath cannot expand)"
while read -r ns name; do
    want=$(kubectl get replicationsource "$name" -n "$ns" -o jsonpath='{.spec.kopia.cacheCapacity}' 2>/dev/null || true)
    pvc="volsync-src-${name}-cache"
    have=$(kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || true)
    [[ -z "$have" || -z "$want" ]] && continue
    if [[ "$want" != "$have" ]]; then
        note "$ns/$pvc is $have but source wants $want — mover will wedge; run scripts/volsync-cache-sweep.sh"
    fi
done < <(kubectl get replicationsource -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)
[[ $findings -eq $before ]] && echo -e "  ${GREEN}✓${NC} all cache PVCs match their source"
echo ""

# ---------------------------------------------------------------------------
before=$findings
echo "5. Stale or failing sources"
now=$(date -u +%s)
while read -r ns name; do
    reason=$(kubectl get replicationsource "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Synchronizing")].reason}' 2>/dev/null || true)
    msg=$(kubectl get replicationsource "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Synchronizing")].message}' 2>/dev/null || true)
    last=$(kubectl get replicationsource "$name" -n "$ns" -o jsonpath='{.status.lastSyncTime}' 2>/dev/null || true)

    if [[ "$reason" == "Error" ]]; then
        note "$ns/$name is in Error: $msg"
        continue
    fi

    if [[ -n "$last" ]]; then
        lastEpoch=$(date -u -d "$last" +%s 2>/dev/null || echo 0)
        if [[ "$lastEpoch" -gt 0 ]]; then
            age=$(( (now - lastEpoch) / 3600 ))
            # -b2 sources run daily; NFS sources run far more often. 24h is a
            # deliberately loose threshold that both should always beat.
            if [[ "$age" -gt 24 ]]; then
                note "$ns/$name last synced ${age}h ago"
            fi
        fi
    else
        note "$ns/$name has never completed a sync"
    fi
done < <(kubectl get replicationsource -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)
[[ $findings -eq $before ]] && echo -e "  ${GREEN}✓${NC} all sources synced within 24h"
echo ""

# ---------------------------------------------------------------------------
echo "=========================================="
if [[ $findings -eq 0 ]]; then
    echo -e "${GREEN}No drift found.${NC}"
else
    echo -e "${RED}${findings} issue(s) found.${NC}"
    exit 1
fi
