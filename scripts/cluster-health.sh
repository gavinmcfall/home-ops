#!/bin/bash
# Kubernetes Cluster Health Report
# Usage: ./cluster-health.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== KUBERNETES CLUSTER HEALTH REPORT ==="
echo "Generated: $(date)"
echo ""

# Nodes
echo "NODES:"
kubectl get nodes --no-headers | while read -r name status roles age version; do
    if [[ "$status" == "Ready" ]]; then
        echo -e "  ${GREEN}✓${NC} $name: $status ($age)"
    else
        echo -e "  ${RED}✗${NC} $name: $status ($age)"
    fi
done
echo ""

# Kustomizations
KS_TOTAL=$(kubectl get kustomization -n flux-system --no-headers 2>/dev/null | wc -l)
KS_READY=$(kubectl get kustomization -n flux-system --no-headers 2>/dev/null | grep -c 'True' || echo 0)
KS_FAILED=$((KS_TOTAL - KS_READY))

echo "FLUX KUSTOMIZATIONS:"
if [[ $KS_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} $KS_READY/$KS_TOTAL ready"
else
    echo -e "  ${YELLOW}!${NC} $KS_READY/$KS_TOTAL ready ($KS_FAILED failing)"
    echo "  Failed:"
    flux get kustomizations -A --status-selector ready=false --no-headers 2>/dev/null | awk '{print "    - " $1 "/" $2}' | head -10
fi
echo ""

# HelmReleases
HR_TOTAL=$(kubectl get helmrelease -A --no-headers 2>/dev/null | wc -l)
HR_READY=$(kubectl get helmrelease -A --no-headers 2>/dev/null | grep -c 'True' || echo 0)
HR_FAILED=$((HR_TOTAL - HR_READY))

echo "HELM RELEASES:"
if [[ $HR_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} $HR_READY/$HR_TOTAL ready"
else
    echo -e "  ${YELLOW}!${NC} $HR_READY/$HR_TOTAL ready ($HR_FAILED failing)"
    echo "  Failed:"
    kubectl get helmrelease -A --no-headers 2>/dev/null | grep -v 'True' | awk '{print "    - " $1 "/" $2 ": " $4}' | head -10
fi
echo ""

# Pods
POD_TOTAL=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
POD_RUNNING=$(kubectl get pods -A --no-headers --field-selector=status.phase=Running 2>/dev/null | wc -l)
POD_SUCCEEDED=$(kubectl get pods -A --no-headers --field-selector=status.phase=Succeeded 2>/dev/null | wc -l)
POD_ISSUES=$((POD_TOTAL - POD_RUNNING - POD_SUCCEEDED))

echo "PODS:"
if [[ $POD_ISSUES -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} $POD_RUNNING running, $POD_SUCCEEDED completed (total: $POD_TOTAL)"
else
    echo -e "  ${YELLOW}!${NC} $POD_RUNNING running, $POD_SUCCEEDED completed, $POD_ISSUES issues (total: $POD_TOTAL)"
    echo "  Issues:"
    kubectl get pods -A --no-headers --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | awk '{print "    - " $1 "/" $2 ": " $4}' | head -10
fi

echo ""
echo "  By Namespace:"
kubectl get pods -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | while read -r count ns; do
    printf "    %-25s %s\n" "$ns:" "$count"
done
echo ""

# PVCs
PVC_TOTAL=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)
PVC_BOUND=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c 'Bound' || echo 0)
PVC_UNBOUND=$((PVC_TOTAL - PVC_BOUND))

echo "PERSISTENT VOLUME CLAIMS:"
if [[ $PVC_UNBOUND -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} $PVC_BOUND/$PVC_TOTAL bound"
else
    echo -e "  ${YELLOW}!${NC} $PVC_BOUND/$PVC_TOTAL bound ($PVC_UNBOUND unbound)"
    echo "  Unbound:"
    kubectl get pvc -A --no-headers 2>/dev/null | grep -v 'Bound' | awk '{print "    - " $1 "/" $2 ": " $3}' | head -10
fi
echo ""

# Ceph (if present)
if kubectl get cephcluster -n rook-ceph &>/dev/null; then
    CEPH_HEALTH=$(kubectl get cephcluster -n rook-ceph -o jsonpath='{.items[0].status.ceph.health}' 2>/dev/null || echo "Unknown")
    CEPH_PHASE=$(kubectl get cephcluster -n rook-ceph -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")

    echo "CEPH STORAGE:"
    if [[ "$CEPH_HEALTH" == "HEALTH_OK" ]]; then
        echo -e "  ${GREEN}✓${NC} $CEPH_HEALTH (Phase: $CEPH_PHASE)"
    elif [[ "$CEPH_HEALTH" == "HEALTH_WARN" ]]; then
        echo -e "  ${YELLOW}!${NC} $CEPH_HEALTH (Phase: $CEPH_PHASE)"
    else
        echo -e "  ${RED}✗${NC} $CEPH_HEALTH (Phase: $CEPH_PHASE)"
    fi

    # OSD count
    OSD_COUNT=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd --no-headers 2>/dev/null | wc -l)
    echo "  OSDs: $OSD_COUNT"
    echo ""
fi

# CNPG Databases (if present)
if kubectl get cluster -n database &>/dev/null; then
    echo "CLOUDNATIVE-PG DATABASES:"
    kubectl get cluster -n database --no-headers 2>/dev/null | while read -r name instances ready status age; do
        if [[ "$status" == *"healthy"* ]]; then
            echo -e "  ${GREEN}✓${NC} $name: $status ($ready instances)"
        else
            echo -e "  ${YELLOW}!${NC} $name: $status ($ready instances)"
        fi
    done
    echo ""
fi

# Resource Usage
echo "NODE RESOURCES:"
if kubectl top nodes &>/dev/null; then
    kubectl top nodes --no-headers 2>/dev/null | while read -r name cpu cpu_pct mem mem_pct; do
        # Parse percentage (remove % sign)
        cpu_val=${cpu_pct/\%/}
        mem_val=${mem_pct/\%/}

        # Color based on usage
        if [[ $cpu_val -gt 80 ]] || [[ $mem_val -gt 80 ]]; then
            color=$RED
        elif [[ $cpu_val -gt 60 ]] || [[ $mem_val -gt 60 ]]; then
            color=$YELLOW
        else
            color=$GREEN
        fi

        echo -e "  $name: CPU=${color}$cpu ($cpu_pct)${NC}, Memory=${color}$mem ($mem_pct)${NC}"
    done
else
    echo "  Metrics server not available"
fi
echo ""

# Services count
SVC_COUNT=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l)
echo "SERVICES: $SVC_COUNT"
echo ""

# Summary
echo "=== SUMMARY ==="
ISSUES=0

if [[ $KS_FAILED -gt 0 ]]; then
    echo -e "${YELLOW}! $KS_FAILED Kustomization(s) failing${NC}"
    ISSUES=$((ISSUES + KS_FAILED))
fi

if [[ $HR_FAILED -gt 0 ]]; then
    echo -e "${YELLOW}! $HR_FAILED HelmRelease(s) failing${NC}"
    ISSUES=$((ISSUES + HR_FAILED))
fi

if [[ $POD_ISSUES -gt 0 ]]; then
    echo -e "${YELLOW}! $POD_ISSUES Pod(s) with issues${NC}"
    ISSUES=$((ISSUES + POD_ISSUES))
fi

if [[ $PVC_UNBOUND -gt 0 ]]; then
    echo -e "${YELLOW}! $PVC_UNBOUND PVC(s) unbound${NC}"
    ISSUES=$((ISSUES + PVC_UNBOUND))
fi

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✓ All systems healthy${NC}"
fi

echo ""
