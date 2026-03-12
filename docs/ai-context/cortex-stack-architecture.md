# Cortex Stack Architecture

## Overview

mem0 serves as the universal memory layer across all client interfaces (Discord, Open WebUI, Claude Code), with user_id scoping ensuring per-person memory isolation. Inference is split across two LocalAI worker groups — Intel iGPU workers for general-purpose models and an NVIDIA worker for coder models — accessed via direct Kubernetes services. PostgreSQL (existing CNPG) provides structured storage for both mem0 and Open WebUI.

## Mermaid Diagram

![Cortex Stack Architecture](images/claude_cortex_stack.png)

*Green = mem0 (central connective tissue across all interfaces)*

## Components

| Component | Role | K8s Namespace |
|-----------|------|---------------|
| LocalAI Intel (x2) | Chat, embeddings, whisper, TTS inference | cortex |
| LocalAI NVIDIA (x1) | Coder model inference (Qwen 2.5) | cortex |
| Qdrant | Vector storage for mem0 memories and Open WebUI RAG | cortex |
| PostgreSQL (CNPG) | Structured data for mem0 and Open WebUI | database |
| mem0 | Universal memory layer, fact extraction and retrieval | cortex |
| OpenClaw | Discord agent, uses openclaw-mem0 plugin | cortex |
| Open WebUI | Browser chat UI, mem0-owui pipeline filter | cortex |
| SearXNG | Web search for agent queries | home |
| Claude Code | CLI agent on local PC, mem0-mcp via MCP | N/A (local) |

## Service Routing

Consumers talk directly to worker services — no P2P federation or load balancer:

| Consumer | Backend | Service URL |
|----------|---------|-------------|
| Open WebUI | Both | `local-ai-intel:8080/v1` + `local-ai-nvidia:8080/v1` |
| mem0 | Intel (embeddings) | `local-ai-intel:8080/v1` |
| OpenClaw | NVIDIA (coder) | `local-ai-nvidia:8080/v1` |

## Deploy Order

1. LocalAI (inference engine)
2. Qdrant (vector DB)
3. SearXNG (web search)
4. mem0 (memory layer)
5. OpenClaw (agent)
6. Open WebUI (chat UI)

*PostgreSQL already deployed via CNPG — just needs new databases for mem0 and Open WebUI.*

## Memory Scoping

All mem0 operations are scoped by `user_id`. A single Qdrant instance hosts separate collections for:
- **mem0 memories**: Extracted facts from conversations (shared across interfaces per user)
- **Open WebUI RAG**: Uploaded documents and knowledge bases

Cross-interface memory sharing means a fact learned via Discord is available in Open WebUI and Claude Code for the same user.
