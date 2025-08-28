#!/bin/bash

# Talos Kubernetes Cluster Information Collector
# Run this script on a machine with talosctl and kubectl configured
# Usage: ./talos-cluster-info.sh [output-file]

OUTPUT_FILE="${1:-cluster-info.md}"
TEMP_DIR="/tmp/cluster-info-$$"
mkdir -p "$TEMP_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required tools
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v talosctl &> /dev/null; then
        error "talosctl not found. Please install Talos CLI."
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        warn "jq not found. Some features may be limited."
    fi

    log "Prerequisites check complete"
}

# Get Talos cluster information
get_cluster_info() {
    log "Gathering cluster information..."

    # Get cluster nodes
    NODES=$(talosctl get members --output json 2>/dev/null || echo "[]")
    NODE_COUNT=$(echo "$NODES" | jq '. | length' 2>/dev/null || echo "Unknown")

    # Get Talos version
    TALOS_VERSION=$(talosctl version --client --short 2>/dev/null || echo "Unknown")

    # Get Kubernetes version
    K8S_VERSION=$(kubectl version --output=json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "Unknown")

    # Cluster endpoint
    CLUSTER_ENDPOINT=$(talosctl config info | grep -oP '(?<=Endpoints: \[)[^\]]*' || echo "Unknown")

    cat > "$TEMP_DIR/cluster-overview.md" << EOF
# Talos Kubernetes Cluster Information

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Talos Version:** $TALOS_VERSION
**Kubernetes Version:** $K8S_VERSION
**Node Count:** $NODE_COUNT
**Cluster Endpoint:** $CLUSTER_ENDPOINT

## Cluster Overview

EOF
}

# Get detailed node information
get_node_details() {
    log "Collecting node details..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF
## Node Information

| Node | Role | Status | Talos Version | Kernel | Architecture | Uptime |
|------|------|--------|---------------|--------|-------------|---------|
EOF

    # Get nodes from kubectl for more detailed info
    kubectl get nodes -o json > "$TEMP_DIR/nodes.json" 2>/dev/null

    if [ -f "$TEMP_DIR/nodes.json" ] && command -v jq &> /dev/null; then
        jq -r '.items[] | [
            .metadata.name,
            (.metadata.labels["node-role.kubernetes.io/control-plane"] // .metadata.labels["node-role.kubernetes.io/master"] // "worker" | if . == "true" or . == "" then "control-plane" else "worker" end),
            .status.conditions[-1].type,
            (.status.nodeInfo.kubeletVersion // "Unknown"),
            (.status.nodeInfo.kernelVersion // "Unknown"),
            (.status.nodeInfo.architecture // "Unknown"),
            (.status.nodeInfo.bootID // "Unknown")
        ] | @tsv' "$TEMP_DIR/nodes.json" | while IFS=$'\t' read -r name role status version kernel arch uptime; do
            echo "| $name | $role | $status | $version | $kernel | $arch | N/A |" >> "$TEMP_DIR/cluster-overview.md"
        done
    else
        # Fallback to basic talosctl info
        talosctl get members --output json 2>/dev/null | jq -r '.[] | [.metadata.id, "Unknown", "Unknown", "Unknown", "Unknown", "Unknown", "Unknown"] | @tsv' | while IFS=$'\t' read -r name role status version kernel arch uptime; do
            echo "| $name | $role | $status | $version | $kernel | $arch | $uptime |" >> "$TEMP_DIR/cluster-overview.md"
        done 2>/dev/null || echo "| No node information available | | | | | | |" >> "$TEMP_DIR/cluster-overview.md"
    fi

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

EOF
}

# Get hardware specifications for each node
get_hardware_specs() {
    log "Collecting hardware specifications..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF
## Hardware Specifications

EOF

    # Get node list
    if command -v jq &> /dev/null && [ -f "$TEMP_DIR/nodes.json" ]; then
        NODE_NAMES=$(jq -r '.items[].metadata.name' "$TEMP_DIR/nodes.json")
    else
        NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')
    fi

    for node in $NODE_NAMES; do
        cat >> "$TEMP_DIR/cluster-overview.md" << EOF
### Node: $node

EOF

        # Try to get detailed system info from Talos
        log "Getting hardware info for $node..."

        # CPU Info
        CPU_INFO=$(talosctl -n "$node" get cpus --output json 2>/dev/null || echo "[]")
        if [ "$CPU_INFO" != "[]" ] && command -v jq &> /dev/null; then
            echo "#### CPU Information" >> "$TEMP_DIR/cluster-overview.md"
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "| Specification | Value |" >> "$TEMP_DIR/cluster-overview.md"
            echo "|---------------|-------|" >> "$TEMP_DIR/cluster-overview.md"

            echo "$CPU_INFO" | jq -r '.[0] | [
                ("**Model**", (.spec.modelName // "Unknown")),
                ("**Cores**", (.spec.coreCount // "Unknown" | tostring)),
                ("**Threads**", (.spec.threadCount // "Unknown" | tostring)),
                ("**Frequency**", ((.spec.maxSpeed // 0) | tostring) + " MHz")
            ] | @tsv' | while IFS=$'\t' read -r key value; do
                echo "| $key | $value |" >> "$TEMP_DIR/cluster-overview.md"
            done 2>/dev/null
        fi

        # Memory Info
        MEMORY_INFO=$(talosctl -n "$node" get memory --output json 2>/dev/null || echo "[]")
        if [ "$MEMORY_INFO" != "[]" ] && command -v jq &> /dev/null; then
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "#### Memory Information" >> "$TEMP_DIR/cluster-overview.md"
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "| Specification | Value |" >> "$TEMP_DIR/cluster-overview.md"
            echo "|---------------|-------|" >> "$TEMP_DIR/cluster-overview.md"

            TOTAL_MEMORY=$(echo "$MEMORY_INFO" | jq -r '.[0].spec.totalSize // 0' | awk '{print int($1/1024/1024/1024)" GB"}')
            AVAILABLE_MEMORY=$(echo "$MEMORY_INFO" | jq -r '.[0].spec.availableSize // 0' | awk '{print int($1/1024/1024/1024)" GB"}')

            echo "| **Total RAM** | $TOTAL_MEMORY |" >> "$TEMP_DIR/cluster-overview.md"
            echo "| **Available RAM** | $AVAILABLE_MEMORY |" >> "$TEMP_DIR/cluster-overview.md"
        fi

        # Network Info
        NETWORK_INFO=$(talosctl -n "$node" get links --output json 2>/dev/null || echo "[]")
        if [ "$NETWORK_INFO" != "[]" ] && command -v jq &> /dev/null; then
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "#### Network Interfaces" >> "$TEMP_DIR/cluster-overview.md"
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "| Interface | Status | Speed |" >> "$TEMP_DIR/cluster-overview.md"
            echo "|-----------|--------|-------|" >> "$TEMP_DIR/cluster-overview.md"

            echo "$NETWORK_INFO" | jq -r '.[] | select(.spec.type == "physical") | [
                (.metadata.id // "Unknown"),
                (if .spec.up then "Up" else "Down" end),
                ((.spec.speedMbps // 0 | tostring) + " Mbps")
            ] | @tsv' | while IFS=$'\t' read -r interface status speed; do
                echo "| $interface | $status | $speed |" >> "$TEMP_DIR/cluster-overview.md"
            done 2>/dev/null
        fi

        # Storage Info
        DISKS_INFO=$(talosctl -n "$node" get disks --output json 2>/dev/null || echo "[]")
        if [ "$DISKS_INFO" != "[]" ] && command -v jq &> /dev/null; then
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "#### Storage Devices" >> "$TEMP_DIR/cluster-overview.md"
            echo "" >> "$TEMP_DIR/cluster-overview.md"
            echo "| Device | Size | Type | Model |" >> "$TEMP_DIR/cluster-overview.md"
            echo "|--------|------|------|-------|" >> "$TEMP_DIR/cluster-overview.md"

            echo "$DISKS_INFO" | jq -r '.[] | [
                (.metadata.id // "Unknown"),
                ((.spec.size // 0) | (. / 1024 / 1024 / 1024 | floor | tostring) + " GB"),
                (.spec.type // "Unknown"),
                (.spec.model // "Unknown")
            ] | @tsv' | while IFS=$'\t' read -r device size type model; do
                echo "| $device | $size | $type | $model |" >> "$TEMP_DIR/cluster-overview.md"
            done 2>/dev/null
        fi

        echo "" >> "$TEMP_DIR/cluster-overview.md"
    done
}

# Get resource utilization
get_resource_usage() {
    log "Collecting resource usage..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF
## Current Resource Usage

EOF

    # Node resource usage
    kubectl top nodes > "$TEMP_DIR/node-usage.txt" 2>/dev/null || echo "Resource metrics unavailable" > "$TEMP_DIR/node-usage.txt"

    if grep -q "Resource metrics unavailable" "$TEMP_DIR/node-usage.txt"; then
        cat >> "$TEMP_DIR/cluster-overview.md" << EOF
*Resource metrics unavailable - metrics-server may not be installed*

EOF
    else
        echo "### Node Resource Usage" >> "$TEMP_DIR/cluster-overview.md"
        echo "" >> "$TEMP_DIR/cluster-overview.md"
        echo '```' >> "$TEMP_DIR/cluster-overview.md"
        cat "$TEMP_DIR/node-usage.txt" >> "$TEMP_DIR/cluster-overview.md"
        echo '```' >> "$TEMP_DIR/cluster-overview.md"
        echo "" >> "$TEMP_DIR/cluster-overview.md"
    fi

    # Namespace resource usage
    kubectl top pods --all-namespaces > "$TEMP_DIR/pod-usage.txt" 2>/dev/null || echo "Pod metrics unavailable" > "$TEMP_DIR/pod-usage.txt"

    if ! grep -q "Pod metrics unavailable" "$TEMP_DIR/pod-usage.txt"; then
        echo "### Top Resource Consuming Pods" >> "$TEMP_DIR/cluster-overview.md"
        echo "" >> "$TEMP_DIR/cluster-overview.md"
        echo '```' >> "$TEMP_DIR/cluster-overview.md"
        head -20 "$TEMP_DIR/pod-usage.txt" >> "$TEMP_DIR/cluster-overview.md"
        echo '```' >> "$TEMP_DIR/cluster-overview.md"
        echo "" >> "$TEMP_DIR/cluster-overview.md"
    fi
}

# Get AI/ML workload suitability
get_ai_suitability() {
    log "Assessing AI/ML workload suitability..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF
## AI/ML Workload Suitability

### For AI Tutor Project:

EOF

    # Check for GPU nodes
    GPU_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name' 2>/dev/null)

    if [ -n "$GPU_NODES" ]; then
        echo "✅ **GPU Nodes Available:**" >> "$TEMP_DIR/cluster-overview.md"
        for gpu_node in $GPU_NODES; do
            GPU_COUNT=$(kubectl get node "$gpu_node" -o json | jq -r '.status.capacity."nvidia.com/gpu"' 2>/dev/null)
            echo "  - $gpu_node: $GPU_COUNT GPU(s)" >> "$TEMP_DIR/cluster-overview.md"
        done
    else
        echo "❌ **No GPU nodes detected** - Local AI processing may be limited" >> "$TEMP_DIR/cluster-overview.md"
    fi

    # Check for NVIDIA device plugin
    NVIDIA_PLUGIN=$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o name 2>/dev/null | wc -l)
    if [ "$NVIDIA_PLUGIN" -gt 0 ]; then
        echo "✅ **NVIDIA Device Plugin**: Installed" >> "$TEMP_DIR/cluster-overview.md"
    else
        echo "⚠️ **NVIDIA Device Plugin**: Not detected" >> "$TEMP_DIR/cluster-overview.md"
    fi

    # Check total cluster resources
    TOTAL_CPU=$(kubectl get nodes -o json | jq -r '.items[].status.capacity.cpu' | sed 's/m$//' | awk '{sum += ($1 > 1000 ? $1/1000 : $1)} END {print int(sum)}' 2>/dev/null || echo "Unknown")
    TOTAL_MEMORY=$(kubectl get nodes -o json | jq -r '.items[].status.capacity.memory' | sed 's/Ki$//' | awk '{sum += $1/1024/1024} END {print int(sum)}' 2>/dev/null || echo "Unknown")

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

### Cluster Resource Summary:
- **Total CPU Cores**: $TOTAL_CPU
- **Total Memory**: $TOTAL_MEMORY GB
- **Suitable for**: Medium-scale AI workloads, model serving, preprocessing

### Recommended AI Components for Your Cluster:
- **Ollama Deployment**: For local LLM inference (LLaVA, coding models)
- **Vector Database**: Qdrant integration (you already have this)
- **Model Storage**: Persistent volumes for model caching
- **Load Balancing**: Distribute AI workloads across nodes

### Namespace Suggestions:
\`\`\`yaml
# ai-tutor namespace for your project
apiVersion: v1
kind: Namespace
metadata:
  name: ai-tutor
  labels:
    name: ai-tutor
    purpose: ai-ml-workloads
\`\`\`

EOF
}

# Get installed operators and relevant services
get_installed_services() {
    log "Checking installed services relevant to AI workloads..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF
## Installed Services & Operators

### Namespaces:
EOF

    kubectl get namespaces --no-headers | awk '{print "- " $1}' >> "$TEMP_DIR/cluster-overview.md"

    # Check for existing AI/ML related services
    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

### AI/ML Related Services:
EOF

    # Check your existing cortex namespace
    CORTEX_SERVICES=$(kubectl get pods -n cortex --no-headers 2>/dev/null | awk '{print "- " $1 " (" $3 ")"}' || echo "- No cortex namespace found")
    echo "$CORTEX_SERVICES" >> "$TEMP_DIR/cluster-overview.md"

    # Check for storage classes suitable for AI workloads
    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

### Storage Classes:
EOF

    kubectl get storageclass --no-headers | awk '{print "- " $1 " (" $2 ")"}' >> "$TEMP_DIR/cluster-overview.md" 2>/dev/null || echo "- No storage classes found" >> "$TEMP_DIR/cluster-overview.md"

    # Check for ingress controllers
    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

### Ingress Controllers:
EOF

    kubectl get pods --all-namespaces -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | awk '{print "- " $2 " in " $1}' >> "$TEMP_DIR/cluster-overview.md" || echo "- No ingress controllers found" >> "$TEMP_DIR/cluster-overview.md"
}

# Generate recommendations for AI tutor deployment
generate_recommendations() {
    log "Generating deployment recommendations..."

    cat >> "$TEMP_DIR/cluster-overview.md" << EOF

## AI Tutor Deployment Recommendations

### BJW-S App Template Example:

\`\`\`yaml
# apps/ai-tutor/ollama-llava/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ollama-llava
  namespace: ai-tutor
spec:
  chart:
    spec:
      chart: app-template
      version: 2.4.0
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  values:
    controllers:
      main:
        containers:
          main:
            image:
              repository: ollama/ollama
              tag: latest
            env:
              OLLAMA_MODELS: /models
    service:
      main:
        ports:
          http:
            port: 11434
    persistence:
      models:
        size: 200Gi
        accessMode: ReadWriteOnce
\`\`\`

### Deployment Steps:

1. **Create Namespace:**
   \`\`\`bash
   kubectl create namespace ai-tutor
   \`\`\`

2. **Deploy with BJW-S Template:**
   \`\`\`bash
   kubectl apply -f ollama-helmrelease.yaml
   \`\`\`

3. **Load Models:**
   \`\`\`bash
   kubectl exec -n ai-tutor deployment/ollama-llava -- ollama pull llava:13b
   \`\`\`

EOF
}

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Main execution
main() {
    log "Starting Talos Kubernetes cluster analysis..."

    # Set up cleanup trap
    trap cleanup EXIT

    check_prerequisites
    get_cluster_info
    get_node_details
    get_hardware_specs
    get_resource_usage
    get_ai_suitability
    get_installed_services
    generate_recommendations

    # Combine all information
    cat "$TEMP_DIR/cluster-overview.md" > "$OUTPUT_FILE"

    log "Cluster information saved to: $OUTPUT_FILE"
    log "Analysis complete!"

    # Display summary
    echo ""
    echo -e "${BLUE}=== CLUSTER SUMMARY ===${NC}"
    echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
    echo "Namespaces: $(kubectl get namespaces --no-headers | wc -l)"
    echo "Total Pods: $(kubectl get pods --all-namespaces --no-headers | wc -l)"
    echo "Report: $OUTPUT_FILE"
    echo ""
}

# Run main function
main "$@"
