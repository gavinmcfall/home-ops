#!/bin/bash
# Guarded reboot of ONE stanton node.
#
# Why this exists: Ceph's mons mark an OSD "up" over the public network, so a
# rebooted OSD can rejoin while its cluster (replication) network is not ready.
# Placement groups then stick in peering and storage I/O stops cluster-wide.
# That happened on 2026-11-12/13 while the cluster network was the Thunderbolt
# mesh: a Thunderbolt link wedged on 3 reboots out of 3 and needed a cable
# reseat each time.
#
# Since 2026-11-13 (#3090) the cluster network is VLAN 100 on bond1
# (10.99.100.0/24, 2x 10G SFP+ LACP), so this script guards on that bond.
# Thunderbolt state is still printed, for information only.
#
# What it does:
#   1. Refuses to start unless the cluster gate passes and the node's cluster
#      network is healthy (both bond1 members up, bond1.100 up).
#   1a. Cordons the node, then gets the databases out of the way:
#      - moves the CNPG operator and pgBackRest plugin pods off it (nothing can
#        manage a Postgres failover while either is down);
#      - switches every Postgres primary on it over to a replica on another
#        node, so writes pause for seconds instead of the minutes a cold
#        restart takes (about 2m40s on 2026-11-13). Needs the `kubectl cnpg`
#        plugin; skip with --no-switchover.
#      The node is uncordoned once it is back and its OSD has been released.
#   2. Sets Ceph noout and holds the node's OSD back (noup) so it cannot rejoin
#      by itself.
#   3. Reboots the node (plain reboot, a machine-config patch applied with
#      --mode=reboot, or a Talos upgrade).
#   4. Prints the cluster-network state every few seconds until it is healthy.
#   5. Releases the OSD only when the bond and its VLAN are up and have stayed
#      up, then waits for every PG to be active+clean.
#   6. Leaves noout SET. Run ./cluster-gate.sh --allow-noout, and only when it
#      passes: kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
#
# If the cluster network never comes up it stops with the OSD still held back
# and noout set: storage keeps running on the other OSDs (no redundancy). Fix
# the link, then re-run with --resume to pick up from step 4.
#
# One node at a time. Never during the 00:00 UTC backup hour.
#
# Usage:
#   ./talos-guarded-reboot.sh <node> --check          # read-only: show what it would do
#   ./talos-guarded-reboot.sh <node>                  # talosctl reboot
#   ./talos-guarded-reboot.sh <node> --patch <file>   # talosctl patch mc --mode=reboot
#   ./talos-guarded-reboot.sh <node> --upgrade <img>  # talosctl upgrade --image <img>, then checks the version
#   ./talos-guarded-reboot.sh <node> --resume         # node already rebooted, guards still set
#   add --no-switchover to reboot with Postgres primaries left where they are
#
# With --patch, talosctl's output is never printed: a rejected patch prints a
# diff that includes secrets from the machine config.
#
# Needs: kubectl, talosctl, and the rook-ceph-tools deployment; the
# `kubectl cnpg` plugin (same version as the operator) for the switchover.

set -uo pipefail

NODE="${1:-}"
MODE="reboot"
PATCH=""
SWITCHOVER=1
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check" ;;
        --resume) MODE="resume" ;;
        --patch) MODE="patch"; PATCH="${2:-}"; shift ;;
        --upgrade) MODE="upgrade"; IMAGE="${2:-}"; shift ;;
        --no-switchover) SWITCHOVER=0 ;;
        -h | --help) sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$NODE" ] || { echo "usage: $0 <node> [--check | --patch <file> | --upgrade <installer image> | --resume]" >&2; exit 2; }
[ "$MODE" != patch ] || [ -s "$PATCH" ] || { echo "patch file missing or empty: $PATCH" >&2; exit 2; }
if [ "$MODE" = upgrade ]; then
    # tag only, e.g. v1.13.12 from factory.talos.dev/metal-installer/<schematic>:v1.13.12
    WANT_TAG="${IMAGE##*:}"
    echo "$IMAGE" | grep -qE '^[^:@ ]+/[^:@ ]+:v[0-9]+\.[0-9]+\.[0-9]+$' \
        || { echo "--upgrade needs an installer image with a version tag, e.g. factory.talos.dev/metal-installer/<schematic>:v1.13.12" >&2; exit 2; }
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
ceph() { kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph "$@" 2>/dev/null; }
now() { date -u +%T; }

IP="$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
[ -n "$IP" ] || { echo "cannot find node $NODE" >&2; exit 2; }
T=(talosctl -e "$IP" -n "$IP")
OSDS="$(ceph osd ls-tree "$NODE" | tr '\n' ' ' | sed 's/ $//')"
[ -n "$OSDS" ] || { echo "cannot find a Ceph OSD on host $NODE" >&2; exit 2; }
# every other node is a Thunderbolt neighbour (full mesh); informational only
PEERS_WANT="$(($(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l) - 1))"

uptime_s() { "${T[@]}" read /proc/uptime 2>/dev/null | awk '{printf "%d", $1}'; }
# Talos version the node is running, e.g. v1.12.6
talos_tag() { "${T[@]}" version --short 2>/dev/null | awk '/^Server:/{s=1} s && /Tag:/{print $2; exit}'; }
UPGRADE_LOG="${TMPDIR:-/tmp}/talos-upgrade-$NODE.log"
tb_up() { "${T[@]}" get links 2>/dev/null | awk '$4 ~ /^enx/ && $8=="up"' | wc -l; }
# peer routes only (metric 2048, one per neighbour); the node's own local route is excluded
tb_routes() { "${T[@]}" get routes 2>/dev/null | grep -c ' inet4//169.254.255.[0-9]*/32/2048 '; }
tb_errs() { "${T[@]}" dmesg 2>/dev/null | grep -c 'failed request link state change'; }
tb_peers() { "${T[@]}" dmesg 2>/dev/null | grep -E 'thunderbolt [0-9]-1: Linux' | sed -E 's/.*thunderbolt ([0-9]-1): Linux (.*)/\1=\2/' | sort -u | tr '\n' ' '; }
# Ceph's cluster network: VLAN 100 on bond1. Healthy = both LACP members up and the VLAN link up.
CNET_BOND="bond1"
CNET_LINK="bond1.100"
CNET_MEMBERS=2
bond_members_up() { "${T[@]}" read "/proc/net/bonding/$CNET_BOND" 2>/dev/null | awk '/^Slave Interface/{s=1} s && /^MII Status: up/{n++; s=0} END{print n+0}'; }
# the operational state is column 8 or 9 depending on whether the link has a KIND
cnet_link_up() { "${T[@]}" get links 2>/dev/null | awk -v l="$CNET_LINK" '$4==l && ($8=="up" || $9=="up")' | wc -l; }
net_ok() { [ "$(bond_members_up)" = "$CNET_MEMBERS" ] && [ "$(cnet_link_up)" = 1 ]; }
net_state() { echo "$CNET_BOND members_up=$(bond_members_up)/$CNET_MEMBERS $CNET_LINK up=$(cnet_link_up) | thunderbolt (info only): links_up=$(tb_up) peer_routes=$(tb_routes)"; }
pgs_clean() {
    local stat bad
    stat="$(ceph pg stat | cut -d';' -f1)"
    bad="$(echo "$stat" | sed 's/^[0-9]* pgs: //' | tr ',' '\n' | grep -vcE '^ *[0-9]+ active\+clean(\+scrubbing)?(\+deep)?$')"
    echo "$stat" | grep -qE '^[0-9]+ pgs:' && [ "$bad" = 0 ]
}

have_cnpg() { kubectl cnpg version > /dev/null 2>&1; }
pod_node() { kubectl -n "$1" get pod "$2" -o jsonpath='{.spec.nodeName}' 2> /dev/null; }
# "namespace cluster instances primary" for every CNPG cluster whose primary is on $NODE
primaries_here() {
    kubectl get clusters.postgresql.cnpg.io -A --no-headers \
        -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,INST:.spec.instances,PRIMARY:.status.currentPrimary 2> /dev/null \
        | while read -r ns name inst primary; do
            [ "$(pod_node "$ns" "$primary")" = "$NODE" ] && echo "$ns $name $inst $primary"
        done
}
# first healthy instance of a cluster that is neither the primary nor on $NODE
switchover_target() {
    local ns="$1" name="$2" primary="$3" inst
    for inst in $(kubectl -n "$ns" get cluster "$name" -o jsonpath='{.status.instancesStatus.healthy[*]}'); do
        [ "$inst" = "$primary" ] && continue
        [ "$(pod_node "$ns" "$inst")" = "$NODE" ] && continue
        echo "$inst"
        return 0
    done
    return 1
}
cluster_settled() {
    [ "$(kubectl -n "$1" get cluster "$2" -o jsonpath='{.status.currentPrimary}')" = "$3" ] \
        && [ "$(kubectl -n "$1" get cluster "$2" -o jsonpath='{.status.phase}')" = "Cluster in healthy state" ] \
        && [ "$(kubectl -n "$1" get cluster "$2" -o jsonpath='{.status.readyInstances}')" = "$(kubectl -n "$1" get cluster "$2" -o jsonpath='{.spec.instances}')" ]
}
# Move the CNPG operator and pgBackRest plugin pods off $NODE (it must already be cordoned).
move_db_controllers() {
    local moved=0 sel
    for sel in "app.kubernetes.io/name=cloudnative-pg" "app=pgbackrest-controller"; do
        if [ -n "$(kubectl -n database get pods -l "$sel" --field-selector "spec.nodeName=$NODE,status.phase=Running" --no-headers 2> /dev/null)" ]; then
            echo "[$(now)] moving pods ($sel) off $NODE"
            kubectl -n database delete pod -l "$sel" --field-selector "spec.nodeName=$NODE" --wait=true --timeout=120s > /dev/null 2>&1
            moved=1
        fi
    done
    if [ "$moved" = 1 ]; then
        kubectl -n database rollout status deploy/cloudnative-pg --timeout=180s > /dev/null 2>&1 \
            && kubectl -n database rollout status deploy/pgbackrest-controller --timeout=180s > /dev/null 2>&1 \
            || { echo "!!! the CNPG operator or pgBackRest plugin did not come back on another node"; return 1; }
    fi
    return 0
}
# Switch every Postgres primary on $NODE over to a replica elsewhere.
switch_primaries_away() {
    local ns name inst primary target
    while read -r ns name inst primary; do
        [ -n "$ns" ] || continue
        if [ "$inst" -lt 2 ]; then
            echo "[$(now)] $name has a single instance — it will be DOWN for the length of the reboot"
            continue
        fi
        target="$(switchover_target "$ns" "$name" "$primary")" \
            || { echo "!!! $name: no healthy replica off $NODE to switch to"; return 1; }
        echo "[$(now)] $name: switching primary $primary -> $target"
        kubectl cnpg promote "$name" "$target" -n "$ns" > /dev/null 2>&1 \
            || { echo "!!! $name: kubectl cnpg promote failed"; return 1; }
        for _ in $(seq 1 60); do
            sleep 5
            cluster_settled "$ns" "$name" "$target" && break
        done
        cluster_settled "$ns" "$name" "$target" \
            || { echo "!!! $name: not healthy on $target after the switchover"; return 1; }
        echo "[$(now)] $name: primary is now $target, cluster healthy"
    done < <(primaries_here)
    return 0
}

echo "node $NODE ($IP)  ceph osd(s): $OSDS  thunderbolt neighbours expected: $PEERS_WANT  mode: $MODE"
echo "[$(now)] $(net_state)"

if [ "$MODE" = check ]; then
    echo "--- would hold back: $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)"
    echo "--- pods on $NODE that will restart:"
    kubectl get pods -A --field-selector "spec.nodeName=$NODE" --no-headers \
        -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name | awk '{print "      "$1"/"$2}' \
        | grep -E 'postgres|mon-|mgr-|mds-|osd-[0-9]|bookorbit' || echo "      (none of the tracked ones)"
    echo "--- database controllers on $NODE (would be moved off first):"
    kubectl -n database get pods --field-selector "spec.nodeName=$NODE,status.phase=Running" --no-headers \
        -o custom-columns=NAME:.metadata.name 2> /dev/null | grep -E '^(cloudnative-pg|pgbackrest-controller)-' | sed 's/^/      /' \
        || echo "      (none)"
    echo "--- Postgres primaries on $NODE:"
    FOUND=0
    while read -r ns name inst primary; do
        [ -n "$ns" ] || continue
        FOUND=1
        if [ "$inst" -lt 2 ]; then
            echo "      $name: $primary — single instance, DOWN for the reboot"
        elif [ "$SWITCHOVER" = 0 ]; then
            echo "      $name: $primary — left in place (--no-switchover)"
        else
            echo "      $name: $primary -> would switch to $(switchover_target "$ns" "$name" "$primary" || echo 'NO HEALTHY REPLICA OFF THIS NODE')"
        fi
    done < <(primaries_here)
    [ "$FOUND" = 1 ] || echo "      (none)"
    if have_cnpg; then echo "--- kubectl cnpg plugin: present"; else echo "--- kubectl cnpg plugin: MISSING (needed for a switchover)"; fi
    echo "--- backups mid-run: $(kubectl get pods -A --no-headers 2>/dev/null | grep -c ' volsync-src-')"
    echo "--- gate:"
    "$HERE/cluster-gate.sh" | grep -E '^FAIL|VERDICT' | sed 's/^/      /'
    echo "check only — nothing changed"
    exit 0
fi

if [ "$MODE" != resume ]; then
    net_ok || { echo "The cluster network is not healthy BEFORE the reboot ($(net_state)) — fix that first. Nothing changed."; exit 1; }
    "$HERE/cluster-gate.sh" > /dev/null 2>&1 || {
        echo "cluster gate does not pass — not starting. Run ./cluster-gate.sh to see why. Nothing changed."; exit 1; }
    if [ "$SWITCHOVER" = 1 ] && ! have_cnpg \
        && primaries_here | awk '$3 >= 2 {found=1} END {exit !found}'; then
        echo "A Postgres primary is on $NODE and the kubectl cnpg plugin is not installed."
        echo "Install it (same version as the operator) or pass --no-switchover. Nothing changed."
        exit 1
    fi

    echo "[$(now)] cordoning $NODE"
    kubectl cordon "$NODE" > /dev/null || { echo "cordon failed. Nothing else changed."; exit 1; }
    if ! move_db_controllers || { [ "$SWITCHOVER" = 1 ] && ! switch_primaries_away; }; then
        echo "Database preparation failed — uncordoning $NODE and stopping. The node was not rebooted."
        kubectl uncordon "$NODE" > /dev/null
        exit 1
    fi

    echo "[$(now)] ceph: set noout, hold $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)back (noup)"
    ceph osd set noout > /dev/null
    for o in $OSDS; do ceph osd add-noup "osd.$o" > /dev/null; done

    if [ "$MODE" = patch ]; then
        # output deliberately discarded: a rejected patch prints a diff containing machine-config secrets
        "${T[@]}" patch mc --mode=reboot --patch "@$PATCH" > /dev/null 2>&1
        RC=$?
    elif [ "$MODE" = upgrade ]; then
        # --legacy: the MachineService upgrade API. It exists on every Talos version
        # this cluster runs (the newer LifecycleService API needs a 1.13 node) and it
        # passes machine.install.extraKernelArgs to the installer, which the newer
        # API does not. Deprecated upstream; due for removal in Talos 1.18.
        # powercycle matches the repo's TalosUpgrade policy (no kexec).
        echo "[$(now)] upgrading $NODE from $(talos_tag) to $IMAGE"
        "${T[@]}" upgrade --legacy --image "$IMAGE" --reboot-mode powercycle --wait=false > "$UPGRADE_LOG" 2>&1
        RC=$?
        [ "$RC" -eq 0 ] || { echo "talosctl upgrade output:"; tail -5 "$UPGRADE_LOG"; }
    else
        "${T[@]}" reboot --wait=false > /dev/null 2>&1
        RC=$?
    fi
    if [ "$RC" -ne 0 ]; then
        echo "talosctl failed (rc=$RC) — removing guards, node was not rebooted"
        for o in $OSDS; do ceph osd rm-noup "osd.$o" > /dev/null; done
        ceph osd unset noout > /dev/null
        kubectl uncordon "$NODE" > /dev/null
        exit 1
    fi

    echo "[$(now)] waiting for $NODE to come back"
    # an upgrade pulls and writes the new image before it reboots, so allow longer
    TRIES=120
    [ "$MODE" = upgrade ] && TRIES=240
    for _ in $(seq 1 "$TRIES"); do
        sleep 5
        U="$(uptime_s)"
        [ -n "$U" ] && [ "$U" -lt 900 ] && { echo "[$(now)] $NODE answering talosctl, uptime ${U}s"; break; }
    done
    U="$(uptime_s)"
    if [ -z "$U" ] || [ "$U" -ge 900 ]; then
        echo "!!! $NODE is NOT BACK (uptime='$U'). noout and noup are LEFT SET. Stopping."
        [ "$MODE" != upgrade ] || echo "    If the node never rebooted, the upgrade did not start: see $UPGRADE_LOG and 'talosctl dmesg'."
        exit 2
    fi
    if [ "$MODE" = upgrade ]; then
        GOT_TAG="$(talos_tag)"
        if [ "$GOT_TAG" = "$WANT_TAG" ]; then
            echo "[$(now)] $NODE is running Talos $GOT_TAG, kernel $("${T[@]}" read /proc/sys/kernel/osrelease 2>/dev/null | tr -d '\n')"
        else
            echo "!!! $NODE came back on Talos '$GOT_TAG', not $WANT_TAG — the upgrade did not take (Talos rolls back a failed boot)."
            echo "    Carrying on with the network and Ceph steps so the node rejoins safely; do NOT upgrade the next node."
        fi
    fi
fi

echo "[$(now)] CLUSTER NETWORK WATCH — need $CNET_MEMBERS $CNET_BOND members up and $CNET_LINK up"
NETOK=0
for _ in $(seq 1 150); do
    echo "[$(now)] $(net_state)"
    if net_ok; then NETOK=1; break; fi
    sleep 5
done
if [ "$NETOK" -ne 1 ]; then
    echo "!!! CLUSTER NETWORK NOT HEALTHY on $NODE. Its OSD is HELD BACK (noup) and noout is SET."
    echo "    Storage is running on the other OSDs with no redundancy. Check the SFP+ links and the"
    echo "    aggregation switch, then re-run with --resume."
    ceph osd stat; ceph pg stat | cut -d';' -f1
    exit 4
fi

# require the links to hold before letting the OSD in
for _ in 1 2 3; do
    sleep 5
    net_ok || { echo "!!! The cluster network dropped again ($(net_state)). Guards LEFT SET. Fix it, then --resume."; exit 4; }
done
echo "[$(now)] cluster network stable, thunderbolt peers found: $(tb_peers)— releasing $(for o in $OSDS; do printf 'osd.%s ' "$o"; done)"
for o in $OSDS; do ceph osd rm-noup "osd.$o" > /dev/null; done
# safe to schedule on again; a no-op if the node was never cordoned
kubectl uncordon "$NODE" > /dev/null 2>&1

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
