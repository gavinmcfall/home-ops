#!/bin/bash
# Guarded reboot of ONE stanton node.
#
# Why this exists: Ceph's cluster_network is the Thunderbolt mesh
# (169.254.255.0/24), and on this hardware a reboot regularly leaves one
# Thunderbolt link wedged ("thunderbolt X-1: failed request link state change")
# until the cable is physically reseated — thunderbolt.host_reset=0 does not
# prevent it (3 reboots out of 3 on 2026-11-13). Ceph's mons mark an OSD "up"
# over the public network, so a rebooted OSD rejoins while unable to reach one
# peer and placement groups stick in peering: storage I/O stops cluster-wide.
#
# What it does:
#   1. Refuses to start unless the cluster gate passes and the node has both
#      Thunderbolt links up.
#   2. Sets Ceph noout and holds the node's OSD back (noup) so it cannot rejoin
#      by itself.
#   3. Reboots the node (plain reboot, or a machine-config patch applied with
#      --mode=reboot).
#   4. Prints the Thunderbolt state every few seconds and says which neighbour
#      is missing, so the cable can be reseated early.
#   5. Releases the OSD only when both links and both peer routes are up and
#      have stayed up, then waits for every PG to be active+clean.
#   6. Leaves noout SET. Run ./cluster-gate.sh --allow-noout, and only when it
#      passes: kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
#
# If Thunderbolt never comes up it stops with the OSD still held back and
# noout set: storage keeps running on the other OSDs (no redundancy) while the
# cable is reseated. Re-run with --resume to pick up from step 4.
#
# SOMEONE MUST BE AT THE HARDWARE. One node at a time. Never during the
# 00:00 UTC backup hour.
#
# Usage:
#   ./talos-guarded-reboot.sh <node> --check          # read-only: show what it would do
#   ./talos-guarded-reboot.sh <node>                  # talosctl reboot
#   ./talos-guarded-reboot.sh <node> --patch <file>   # talosctl patch mc --mode=reboot
#   ./talos-guarded-reboot.sh <node> --resume         # node already rebooted, guards still set
#
# With --patch, talosctl's output is never printed: a rejected patch prints a
# diff that includes secrets from the machine config.
#
# Needs: kubectl, talosctl, and the rook-ceph-tools deployment.

set -uo pipefail

NODE="${1:-}"
MODE="reboot"
PATCH=""
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check" ;;
        --resume) MODE="resume" ;;
        --patch) MODE="patch"; PATCH="${2:-}"; shift ;;
        -h | --help) sed -n '2,43p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$NODE" ] || { echo "usage: $0 <node> [--check | --patch <file> | --resume]" >&2; exit 2; }
[ "$MODE" != patch ] || [ -s "$PATCH" ] || { echo "patch file missing or empty: $PATCH" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ceph() { kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph "$@" 2>/dev/null; }
now() { date -u +%T; }

IP="$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
[ -n "$IP" ] || { echo "cannot find node $NODE" >&2; exit 2; }
T=(talosctl -e "$IP" -n "$IP")
OSDS="$(ceph osd ls-tree "$NODE" | tr '\n' ' ' | sed 's/ $//')"
[ -n "$OSDS" ] || { echo "cannot find a Ceph OSD on host $NODE" >&2; exit 2; }
# every other node is a Thunderbolt neighbour (full mesh)
PEERS_WANT="$(($(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l) - 1))"

uptime_s() { "${T[@]}" read /proc/uptime 2>/dev/null | awk '{printf "%d", $1}'; }
tb_up() { "${T[@]}" get links 2>/dev/null | awk '$4 ~ /^enx/ && $8=="up"' | wc -l; }
# peer routes only (metric 2048, one per neighbour); the node's own local route is excluded
tb_routes() { "${T[@]}" get routes 2>/dev/null | grep -c ' inet4//169.254.255.[0-9]*/32/2048 '; }
tb_errs() { "${T[@]}" dmesg 2>/dev/null | grep -c 'failed request link state change'; }
tb_peers() { "${T[@]}" dmesg 2>/dev/null | grep -E 'thunderbolt [0-9]-1: Linux' | sed -E 's/.*thunderbolt ([0-9]-1): Linux (.*)/\1=\2/' | sort -u | tr '\n' ' '; }
tb_ok() { [ "$(tb_up)" = "$PEERS_WANT" ] && [ "$(tb_routes)" = "$PEERS_WANT" ]; }
pgs_clean() {
    local stat bad
    stat="$(ceph pg stat | cut -d';' -f1)"
    bad="$(echo "$stat" | sed 's/^[0-9]* pgs: //' | tr ',' '\n' | grep -vcE '^ *[0-9]+ active\+clean(\+scrubbing)?(\+deep)?$')"
    echo "$stat" | grep -qE '^[0-9]+ pgs:' && [ "$bad" = 0 ]
}

echo "node $NODE ($IP)  ceph osd(s): $OSDS  thunderbolt neighbours expected: $PEERS_WANT  mode: $MODE"
echo "[$(now)] thunderbolt now: links_up=$(tb_up) peer_routes=$(tb_routes) found: $(tb_peers)"

if [ "$MODE" = check ]; then
    echo "--- would hold back: $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)"
    echo "--- pods on $NODE that will restart:"
    kubectl get pods -A --field-selector "spec.nodeName=$NODE" --no-headers \
        -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name | awk '{print "      "$1"/"$2}' \
        | grep -E 'postgres|mon-|mgr-|mds-|osd-[0-9]|bookorbit' || echo "      (none of the tracked ones)"
    echo "--- CNPG primaries:"
    kubectl get clusters.postgresql.cnpg.io -A \
        -o custom-columns=NAME:.metadata.name,PRIMARY:.status.currentPrimary --no-headers | sed 's/^/      /'
    echo "--- backups mid-run: $(kubectl get pods -A --no-headers 2>/dev/null | grep -c ' volsync-src-')"
    echo "--- gate:"
    "$HERE/cluster-gate.sh" | grep -E '^FAIL|VERDICT' | sed 's/^/      /'
    echo "check only — nothing changed"
    exit 0
fi

if [ "$MODE" != resume ]; then
    tb_ok || { echo "Thunderbolt is not at $PEERS_WANT links BEFORE the reboot — fix that first. Nothing changed."; exit 1; }
    "$HERE/cluster-gate.sh" > /dev/null 2>&1 || {
        echo "cluster gate does not pass — not starting. Run ./cluster-gate.sh to see why. Nothing changed."; exit 1; }

    echo "[$(now)] ceph: set noout, hold $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)back (noup)"
    ceph osd set noout > /dev/null
    for o in $OSDS; do ceph osd add-noup "osd.$o" > /dev/null; done

    if [ "$MODE" = patch ]; then
        # output deliberately discarded: a rejected patch prints a diff containing machine-config secrets
        "${T[@]}" patch mc --mode=reboot --patch "@$PATCH" > /dev/null 2>&1
        RC=$?
    else
        "${T[@]}" reboot --wait=false > /dev/null 2>&1
        RC=$?
    fi
    if [ "$RC" -ne 0 ]; then
        echo "talosctl failed (rc=$RC) — removing guards, node was not rebooted"
        for o in $OSDS; do ceph osd rm-noup "osd.$o" > /dev/null; done
        ceph osd unset noout > /dev/null
        exit 1
    fi

    echo "[$(now)] waiting for $NODE to come back"
    for _ in $(seq 1 120); do
        sleep 5
        U="$(uptime_s)"
        [ -n "$U" ] && [ "$U" -lt 900 ] && { echo "[$(now)] $NODE answering talosctl, uptime ${U}s"; break; }
    done
    U="$(uptime_s)"
    if [ -z "$U" ] || [ "$U" -ge 900 ]; then
        echo "!!! $NODE is NOT BACK (uptime='$U'). noout and noup are LEFT SET. Stopping."
        exit 2
    fi
fi

echo "[$(now)] THUNDERBOLT WATCH — need $PEERS_WANT links up and $PEERS_WANT peer routes"
TBOK=0
for _ in $(seq 1 150); do
    L="$(tb_up)"; R="$(tb_routes)"; E="$(tb_errs)"; P="$(tb_peers)"
    echo "[$(now)] thunderbolt: links_up=$L peer_routes=$R link-errors=$E found: $P"
    if [ "$L" = "$PEERS_WANT" ] && [ "$R" = "$PEERS_WANT" ]; then TBOK=1; break; fi
    if [ "$E" -gt 3 ] || [ "$L" != "$PEERS_WANT" ]; then
        echo "    >>> RESEAT NEEDED on $NODE: reseat the cable to whichever neighbour is not listed as up (links_up=$L of $PEERS_WANT)"
    fi
    sleep 5
done
if [ "$TBOK" -ne 1 ]; then
    echo "!!! THUNDERBOLT NOT HEALTHY on $NODE. Its OSD is HELD BACK (noup) and noout is SET."
    echo "    Storage is running on the other OSDs with no redundancy. Reseat, then re-run with --resume."
    ceph osd stat; ceph pg stat | cut -d';' -f1
    exit 4
fi

# a reseat can drop the node's other link; require it to hold before letting the OSD in
for _ in 1 2 3; do
    sleep 5
    tb_ok || { echo "!!! Thunderbolt dropped again (links_up=$(tb_up) peer_routes=$(tb_routes)). Guards LEFT SET. Reseat, then --resume."; exit 4; }
done
echo "[$(now)] thunderbolt stable — releasing $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)"
for o in $OSDS; do ceph osd rm-noup "osd.$o" > /dev/null; done

OK=0
for i in $(seq 1 90); do
    sleep 10
    KN="$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')"
    OSD_STAT="$(ceph osd stat | cut -d';' -f1)"
    OSD_N="$(echo "$OSD_STAT" | grep -oE '^[0-9]+')"
    if [ "$KN" = Ready ] && echo "$OSD_STAT" | grep -q "$OSD_N osds: $OSD_N up" && pgs_clean; then OK=1; break; fi
    [ $((i % 3)) -eq 0 ] && echo "[$(now)] settling: node=$KN | $OSD_STAT | $(ceph pg stat | cut -d';' -f1) | tb_links=$(tb_up)"
done
echo "[$(now)] settled=$OK node=$KN | $OSD_STAT | $(ceph pg stat | cut -d';' -f1) | tb_links=$(tb_up)"
echo
echo "noout is still SET on purpose. Next:"
echo "  $HERE/cluster-gate.sh --allow-noout"
echo "  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout   # only when the gate passes"
[ "$OK" -eq 1 ] || exit 3
