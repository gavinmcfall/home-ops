# Cortex Stack Architecture

## Overview

mem0 serves as the universal memory layer across all client interfaces (Discord, Open WebUI, Claude Code), with user_id scoping ensuring per-person memory isolation. All inference routes through LocalAI's P2P federated cluster.

## Architecture Diagram

```mermaid
flowchart TD
    subgraph users["Persons (memory scoped by user_id)"]
        direction LR
        pa["Person A"]
        pb["Person B"]
        pc["Person C"]
        pd["Person D"]
    end

    subgraph clients["Client Interfaces"]
        discord["Discord"]
        owui["Open WebUI (browser)"]
        cc["Claude Code (terminal)"]
    end

    subgraph integration["Memory Integration Layer"]
        oc_plugin["openclaw-mem0 plugin"]
        owui_pipe["mem0-owui pipeline filter"]
        mem0_mcp["mem0-mcp (selfhosted)"]
    end

    mem0["mem0 API Server"]:::memory

    subgraph storage["Shared Storage"]
        qdrant[("Qdrant")]
        sqlite[("SQLite History")]
    end

    subgraph localai["LocalAI P2P Federation"]
        lb["Load Balancer (CPU)"]
        intel["Intel iGPU Workers x3"]
        nvidia["NVIDIA 1080 Ti Worker"]
    end

    searxng["SearXNG"]

    pa & pb & pc & pd --> discord
    pa & pb & pc & pd --> owui
    pa --> cc

    discord --> openclaw["OpenClaw (agent)"]
    openclaw --> oc_plugin
    owui --> owui_pipe
    cc --> mem0_mcp

    oc_plugin --|scoped by user_id|--> mem0
    owui_pipe --|scoped by user_id|--> mem0
    mem0_mcp --|scoped by user_id|--> mem0

    mem0 --|store and search|--> qdrant
    mem0 --|history|--> sqlite
    mem0 --|LLM extract and embed|--> lb

    owui --|chat inference|--> lb
    owui --|document RAG|--> qdrant
    openclaw --|inference|--> lb
    openclaw --|web search|--> searxng

    lb --> intel & nvidia

    classDef memory fill:#90EE90,stroke:#2E7D32,color:#000
```

*Green = mem0 (central connective tissue across all interfaces)*

## Components

| Component | Role | K8s Namespace |
|-----------|------|---------------|
| LocalAI (LB + Workers) | Inference engine, P2P federated | cortex |
| Qdrant | Vector storage for mem0 memories and Open WebUI RAG | cortex |
| mem0 | Universal memory layer, fact extraction and retrieval | cortex |
| OpenClaw | Discord agent, uses openclaw-mem0 plugin | cortex |
| Open WebUI | Browser chat UI, mem0-owui pipeline filter | cortex |
| SearXNG | Web search for agent queries | cortex |
| Claude Code | CLI agent on local PC, mem0-mcp via MCP | N/A (local) |

## Deploy Order

1. LocalAI (inference engine — manifests exist)
2. Qdrant (vector DB — Helm repo registered, needs HelmRelease)
3. SearXNG (web search)
4. mem0 (memory layer — new app-template deployment)
5. OpenClaw (agent — rewire to LocalAI, add mem0 plugin)
6. Open WebUI (chat UI — connects to LocalAI + Qdrant + mem0 pipeline)

## Memory Scoping

All mem0 operations are scoped by `user_id`. A single Qdrant instance hosts separate collections for:
- **mem0 memories**: Extracted facts from conversations (shared across interfaces per user)
- **Open WebUI RAG**: Uploaded documents and knowledge bases

Cross-interface memory sharing means a fact learned via Discord is available in Open WebUI and Claude Code for the same user.
