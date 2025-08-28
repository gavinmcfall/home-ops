# Talos Kubernetes Cluster Information

**Generated:** 2025-08-27 08:41:07
**Talos Version:** Client:
Talos v1.10.4
**Kubernetes Version:** v1.33.1
**Node Count:** 3
3
3
3
3
3
3
3
3
**Cluster Endpoint:** Unknown

## Cluster Overview

## Node Information

| Node | Role | Status | Talos Version | Kernel | Architecture | Uptime |
|------|------|--------|---------------|--------|-------------|---------|
| stanton-01 | control-plane | Ready | v1.33.1 | 6.12.31-talos | amd64 | N/A |
| stanton-02 | control-plane | Ready | v1.33.1 | 6.12.31-talos | amd64 | N/A |
| stanton-03 | control-plane | Ready | v1.33.1 | 6.12.31-talos | amd64 | N/A |

## Hardware Specifications

### Node: stanton-01


#### Network Interfaces

| Interface | Status | Speed |
|-----------|--------|-------|

#### Storage Devices

| Device | Size | Type | Model |
|--------|------|------|-------|
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |

### Node: stanton-02


#### Network Interfaces

| Interface | Status | Speed |
|-----------|--------|-------|

#### Storage Devices

| Device | Size | Type | Model |
|--------|------|------|-------|
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |

### Node: stanton-03


#### Network Interfaces

| Interface | Status | Speed |
|-----------|--------|-------|

#### Storage Devices

| Device | Size | Type | Model |
|--------|------|------|-------|
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |
| Unknown | 0 GB | Unknown | Unknown |

## Current Resource Usage

### Node Resource Usage

```
NAME         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
stanton-01   1174m        5%       20559Mi         21%         
stanton-02   1383m        6%       22135Mi         23%         
stanton-03   1455m        7%       27068Mi         28%         
```

### Top Resource Consuming Pods

```
NAMESPACE          NAME                                                     CPU(cores)   MEMORY(bytes)   
cert-manager       cert-manager-7b7568855f-v5b4d                            2m           35Mi            
cert-manager       cert-manager-cainjector-6d547ff648-hf92q                 1m           61Mi            
cert-manager       cert-manager-webhook-69656bff95-x7kzx                    2m           17Mi            
cortex             litellm-7f559d6466-hkrpf                                 14m          544Mi           
cortex             open-webui-6cbbf7769d-n5fxl                              3m           648Mi           
cortex             qdrant-6c9df8685f-5kc67                                  12m          585Mi           
database           cloudnative-pg-7795f9f94d-m2fjv                          4m           101Mi           
database           dragonfly-0                                              19m          27Mi            
database           dragonfly-1                                              20m          27Mi            
database           dragonfly-2                                              13m          28Mi            
database           dragonfly-3                                              32m          31Mi            
database           dragonfly-4                                              20m          28Mi            
database           dragonfly-5                                              23m          97Mi            
database           dragonfly-operator-55cc89ff4b-sxgm2                      2m           31Mi            
database           mariadb-0                                                22m          123Mi           
database           mosquitto-6bb9f85f9f-4l7p8                               1m           2Mi             
database           postgres17-1                                             32m          812Mi           
database           postgres17-2                                             10m          631Mi           
database           postgres17-3                                             9m           480Mi           
```

## AI/ML Workload Suitability

### For AI Tutor Project:

❌ **No GPU nodes detected** - Local AI processing may be limited
⚠️ **NVIDIA Device Plugin**: Not detected

### Cluster Resource Summary:
- **Total CPU Cores**: 60
- **Total Memory**: 282 GB
- **Suitable for**: Medium-scale AI workloads, model serving, preprocessing

### Recommended AI Components for Your Cluster:
- **Ollama Deployment**: For local LLM inference (LLaVA, coding models)
- **Vector Database**: Qdrant integration (you already have this)
- **Model Storage**: Persistent volumes for model caching
- **Load Balancing**: Distribute AI workloads across nodes

### Namespace Suggestions:
```yaml
# ai-tutor namespace for your project
apiVersion: v1
kind: Namespace
metadata:
  name: ai-tutor
  labels:
    name: ai-tutor
    purpose: ai-ml-workloads
```

## Installed Services & Operators

### Namespaces:
- cert-manager
- cilium-secrets
- cortex
- database
- default
- downloads
- entertainment
- external-secrets
- flux-system
- games
- home
- home-automation
- kube-node-lease
- kube-public
- kube-system
- network
- observability
- openebs-system
- rook-ceph
- security
- storage
- volsync-system

### AI/ML Related Services:
- litellm-7f559d6466-hkrpf (Running)
- open-webui-6cbbf7769d-n5fxl (Running)
- qdrant-6c9df8685f-5kc67 (Running)

### Storage Classes:
- ceph-block ((default))
- ceph-bucket (rook-ceph.ceph.rook.io/bucket)
- ceph-filesystem (rook-ceph.cephfs.csi.ceph.com)
- openebs-hostpath (openebs.io/local)

### Ingress Controllers:
- cert-manager-7b7568855f-v5b4d in cert-manager
- ingress-nginx-external-controller-c6978b9dc-qfqsc in network
- ingress-nginx-internal-controller-7f9ddd56f9-72bqx in network

## AI Tutor Deployment Recommendations

### BJW-S App Template Example:

```yaml
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
```

### Deployment Steps:

1. **Create Namespace:**
   ```bash
   kubectl create namespace ai-tutor
   ```

2. **Deploy with BJW-S Template:**
   ```bash
   kubectl apply -f ollama-helmrelease.yaml
   ```

3. **Load Models:**
   ```bash
   kubectl exec -n ai-tutor deployment/ollama-llava -- ollama pull llava:13b
   ```

