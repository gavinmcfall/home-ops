#!/bin/bash
# Cluster gate — a strict pass/fail check to run between disruptive steps
# (node reboots, Talos/Kubernetes upgrades). Read-only.
#
# Unlike cluster-health.sh (a human-readable report), this prints PASS/FAIL per
# check and exits non-zero if ANYTHING is not healthy. The rule it encodes:
# do not start the next node until every check passes.
#
# Checks: nodes, etcd (members, single leader, alarms), each apiserver's /readyz,
# Ceph (health, OSDs, PGs, mons, mgr, MDS, pods), CNPG clusters, every pod,
# daemonsets, deployments/statefulsets, PVCs, volume attachments, Flux, VolSync.
#
# Usage:
#   ./cluster-gate.sh                 # everything must be healthy
#   ./cluster-gate.sh --allow-noout   # tolerate Ceph's noout flag (set on purpose
#                                     # for the duration of a rolling reboot)
#   ./cluster-gate.sh --allow-backups # tolerate VolSync movers that are mid-run
#
# Failed/Succeeded pod objects are leftovers, not workloads; they are counted
# separately and never fail the gate.
#
# Needs: kubectl, talosctl, python, and the rook-ceph-tools deployment.

set -uo pipefail

ALLOW_NOOUT=0
ALLOW_BACKUPS=0
for arg in "$@"; do
    case "$arg" in
        --allow-noout) ALLOW_NOOUT=1 ;;
        --allow-backups) ALLOW_BACKUPS=1 ;;
        -h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

PY="$(command -v python3 || command -v python)"
FAIL=0
chk() { if [ "$2" = "ok" ]; then echo "PASS  $1"; else echo "FAIL  $1 -> ${3:-}"; FAIL=1; fi; }
ceph() { kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph "$@" 2>/dev/null; }
# Live pods only: Failed/Succeeded pod objects are leftovers.
LIVE='--field-selector=status.phase!=Failed,status.phase!=Succeeded'

echo "== $(date -u +%FT%TZ)"

# --- nodes -------------------------------------------------------------------
mapfile -t NODE_IPS < <(kubectl get nodes -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
NODE_COUNT="$(kubectl get nodes --no-headers | wc -l)"
NOT_READY="$(kubectl get nodes --no-headers | awk '$2!="Ready"{print $1":"$2}' | tr '\n' ' ')"
chk "nodes: $NODE_COUNT Ready, none cordoned" "$([ -z "$NOT_READY" ] && echo ok)" "$NOT_READY"

# --- etcd --------------------------------------------------------------------
CP_CSV="$(IFS=,; echo "${NODE_IPS[*]}")"
ETCD="$(talosctl -e "${NODE_IPS[0]}" -n "$CP_CSV" etcd status 2>/dev/null | grep -v WARNING)"
# columns after whitespace split: 1 node, 2 member, 3-4 db size, 5-7 in use, 8 leader, 9 raft index
E_MEMBERS="$(echo "$ETCD" | awk 'NR>1' | wc -l)"
E_LEADERS="$(echo "$ETCD" | awk 'NR>1{print $8}' | sort -u | wc -l)"
E_INDEX="$(echo "$ETCD" | awk 'NR>1{print $9}' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
chk "etcd: ${#NODE_IPS[@]} members, one agreed leader" \
    "$([ "$E_MEMBERS" = "${#NODE_IPS[@]}" ] && [ "$E_LEADERS" = 1 ] && echo ok)" "members=$E_MEMBERS leaders=$E_LEADERS"
echo "      raft index min/max: $E_INDEX"
E_ALARMS="$(talosctl -e "${NODE_IPS[0]}" -n "${NODE_IPS[0]}" etcd alarm list 2>/dev/null | grep -v WARNING | awk 'NR>1' | wc -l)"
chk "etcd: no alarms" "$([ "$E_ALARMS" = 0 ] && echo ok)" "$E_ALARMS alarms"

# --- apiservers, one by one (the VIP hides a broken one) ----------------------
for ip in "${NODE_IPS[@]}"; do
    R="$(MSYS_NO_PATHCONV=1 kubectl --server "https://$ip:6443" get --raw=/readyz 2>&1 | head -1)"
    chk "apiserver $ip readyz" "$([ "$R" = ok ] && echo ok)" "$R"
done

# --- ceph --------------------------------------------------------------------
HEALTH="$(ceph health detail | head -8)"
# Warnings muted on purpose (healthCheck.muteHealthWarning in the cluster
# HelmRelease) show as a "(muted: ...)" suffix on the summary line. They do not
# count; anything unmuted still fails the gate.
HEALTH1="$(ceph health | head -1 | sed -E 's/[; ]*\(muted: [A-Z_ ]+\)$//')"
if [ "$HEALTH1" = HEALTH_OK ] || { [ "$ALLOW_NOOUT" = 1 ] && [ "$HEALTH1" = 'HEALTH_WARN noout flag(s) set' ]; }; then H_OK=ok; else H_OK=no; fi
chk "ceph health$([ "$ALLOW_NOOUT" = 1 ] && echo ' (noout tolerated)')" "$H_OK" "$(echo "$HEALTH" | tr '\n' '|')"

OSD_STAT="$(ceph osd stat)"
OSD_N="$(echo "$OSD_STAT" | grep -oE '^[0-9]+')"
chk "ceph: all $OSD_N osds up and in" "$(echo "$OSD_STAT" | grep -q "$OSD_N osds: $OSD_N up.*$OSD_N in" && echo ok)" "$OSD_STAT"
ceph osd tree | awk 'NR==1 || /osd\./{print "      "$0}'
NOUP="$(ceph osd dump | grep -c noup)"
chk "ceph: no osd held back (noup)" "$([ "$NOUP" = 0 ] && echo ok)" "$NOUP entries mention noup"

PG_STAT="$(ceph pg stat | cut -d';' -f1)"
# every state listed must be active+clean (scrubbing variants are normal background work)
PG_BAD="$(echo "$PG_STAT" | sed 's/^[0-9]* pgs: //' | tr ',' '\n' | grep -vcE '^ *[0-9]+ active\+clean(\+scrubbing)?(\+deep)?$')"
chk "ceph: all pgs active+clean (scrubbing ok)" "$(echo "$PG_STAT" | grep -qE '^[0-9]+ pgs:' && [ "$PG_BAD" = 0 ] && echo ok)" "$PG_STAT"

MONS="$(ceph quorum_status -f json | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(len(d["quorum_names"]),len(d["monmap"]["mons"]))' 2>/dev/null)"
chk "ceph: all mons in quorum" "$([ -n "$MONS" ] && [ "${MONS% *}" = "${MONS#* }" ] && echo ok)" "in quorum / total: $MONS"
MGR="$(ceph mgr stat -f json | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(d["available"],d["num_standby"])' 2>/dev/null)"
chk "ceph: mgr active with standby" "$([ "$MGR" = "True 1" ] && echo ok)" "$MGR"
MDS="$(ceph fs status -f json | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(sum(1 for m in d["mdsmap"] if m["state"]=="active"),sum(1 for m in d["mdsmap"] if "standby" in m["state"]))' 2>/dev/null)"
chk "cephfs: 1 active mds + standby" "$([ "$MDS" = "1 1" ] && echo ok)" "$MDS"
ROOK_BAD="$(kubectl -n rook-ceph get pods $LIVE --no-headers | grep -vE 'Running|Completed' | awk '{print $1":"$3}' | tr '\n' ' ')"
chk "rook-ceph pods all running" "$([ -z "$ROOK_BAD" ] && echo ok)" "$ROOK_BAD"

# --- databases ----------------------------------------------------------------
CNPG_BAD="$(kubectl get clusters.postgresql.cnpg.io -A -o json | "$PY" -c '
import sys,json
bad=[]
for i in json.load(sys.stdin)["items"]:
    s=i.get("status",{}); want=i["spec"]["instances"]
    if s.get("readyInstances",0)!=want or s.get("phase")!="Cluster in healthy state":
        bad.append("%s %s/%s %s"%(i["metadata"]["name"],s.get("readyInstances",0),want,s.get("phase")))
print("; ".join(bad))')"
chk "postgres: all CNPG clusters fully ready" "$([ -z "$CNPG_BAD" ] && echo ok)" "$CNPG_BAD"
kubectl get clusters.postgresql.cnpg.io -A \
    -o custom-columns=NAME:.metadata.name,READY:.status.readyInstances,PRIMARY:.status.currentPrimary --no-headers | sed 's/^/      /'

# --- workloads ----------------------------------------------------------------
POD_FILTER='Running|Completed'
PODS="$(kubectl get pods -A $LIVE --no-headers)"
[ "$ALLOW_BACKUPS" = 1 ] && PODS="$(echo "$PODS" | grep -v ' volsync-src-')"
PODS_BAD="$(echo "$PODS" | grep -vE "$POD_FILTER" | awk '{print $1"/"$2":"$4}' | tr '\n' ' ')"
chk "all live pods Running cluster-wide" "$([ -z "$PODS_BAD" ] && echo ok)" "$PODS_BAD"
echo "      leftover Failed pod objects (not running): $(kubectl get pods -A --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)"
UNREADY="$(echo "$PODS" | awk '$4=="Running"{split($3,a,"/"); if(a[1]!=a[2]) print $1"/"$2":"$3}' | tr '\n' ' ')"
chk "all running pods fully ready" "$([ -z "$UNREADY" ] && echo ok)" "$UNREADY"
DS_BAD="$(kubectl get ds -A --no-headers | awk '$3!=$5 || $3!=$7{print $1"/"$2":"$5"/"$3}' | tr '\n' ' ')"
chk "daemonsets fully ready" "$([ -z "$DS_BAD" ] && echo ok)" "$DS_BAD"
DEP_BAD="$(kubectl get deploy,sts -A --no-headers | awk '{split($3,a,"/"); if(a[1]!=a[2]) print $1"/"$2":"$3}' | tr '\n' ' ')"
chk "deployments/statefulsets at full replicas" "$([ -z "$DEP_BAD" ] && echo ok)" "$DEP_BAD"

# --- storage objects ------------------------------------------------------------
PVC_BAD="$(kubectl get pvc -A --no-headers | awk '$3!="Bound"{print $1"/"$2":"$3}')"
[ "$ALLOW_BACKUPS" = 1 ] && PVC_BAD="$(echo "$PVC_BAD" | grep -v '/volsync-.*-src:' || true)"
PVC_BAD="$(echo "$PVC_BAD" | tr '\n' ' ' | sed 's/^ *$//')"
chk "all PVCs bound" "$([ -z "$PVC_BAD" ] && echo ok)" "$PVC_BAD"
VA_BAD="$(kubectl get volumeattachment --no-headers 2>/dev/null | awk '$5!="true"{print $1}' | wc -l)"
chk "all volume attachments attached" "$([ "$VA_BAD" = 0 ] && echo ok)" "$VA_BAD not attached"

# --- gitops and backups -----------------------------------------------------------
KS_BAD="$(kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A --no-headers | awk '$4!="True"{print $1"/"$2}' | tr '\n' ' ')"
chk "flux kustomizations ready" "$([ -z "$KS_BAD" ] && echo ok)" "$KS_BAD"
HR_BAD="$(kubectl get helmreleases.helm.toolkit.fluxcd.io -A --no-headers | awk '$4!="True"{print $1"/"$2}' | tr '\n' ' ')"
chk "flux helmreleases ready" "$([ -z "$HR_BAD" ] && echo ok)" "$HR_BAD"
VS_RUNNING="$(kubectl get replicationsource -A -o json | "$PY" -c '
import sys,json
print(" ".join(i["metadata"]["namespace"]+"/"+i["metadata"]["name"] for i in json.load(sys.stdin)["items"] if any(c["type"]=="Synchronizing" and c["status"]=="True" for c in i.get("status",{}).get("conditions",[]))))')"
if [ "$ALLOW_BACKUPS" = 1 ]; then
    echo "      volsync backups mid-run (tolerated): ${VS_RUNNING:-none}"
else
    chk "no volsync backup running" "$([ -z "$VS_RUNNING" ] && echo ok)" "$VS_RUNNING"
fi

echo "== VERDICT: $([ $FAIL = 0 ] && echo ALL-PASS || echo NOT-HEALTHY)"
exit $FAIL
