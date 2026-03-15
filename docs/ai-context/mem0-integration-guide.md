# mem0 Integration Guide — Wiring Up the Memory Layer

This guide covers connecting all three client interfaces to the mem0 API server that's already deployed in the cortex namespace.

## Current State

Already deployed and running:

| Component | Service URL | Status |
|-----------|------------|--------|
| mem0 API (OpenMemory) | `mem0.cortex.svc.cluster.local:8765` | Running, `/docs` accessible |
| Qdrant | `qdrant.cortex.svc.cluster.local:6333` | Running |
| LocalAI Intel | `local-ai-intel.cortex.svc.cluster.local:8080` | Running (has nomic-embed-text) |
| Open WebUI | `open-webui.cortex.svc.cluster.local:8080` | Running |
| OpenClaw | `openclaw.cortex.svc.cluster.local:18789` | Running |

## Prerequisites

Before starting, you need one 1Password item:

**`mem0` item in 1Password** — must contain:
- `MEM0_API_KEY` — any string (used as OPENAI_API_KEY for LocalAI, which doesn't validate it but the mem0 SDK requires it to be non-empty)

This should already exist from the ExternalSecret. Verify:
```bash
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl get externalsecret -n cortex mem0
```

---

## Step 1: Configure mem0 to Use Qdrant + LocalAI

The mem0 server needs to be told to use your Qdrant instance for vectors and LocalAI for LLM/embeddings. This is done via the config API endpoint.

### 1a. Hit the config endpoint

```bash
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl exec -n cortex deploy/mem0 -- \
  curl -s -X PUT http://localhost:8765/api/v1/config/openmemory \
  -H "Content-Type: application/json" \
  -d '{
    "openmemory": {
      "custom_instructions": ""
    },
    "mem0": {
      "vector_store": {
        "provider": "qdrant",
        "config": {
          "collection_name": "mem0",
          "host": "qdrant.cortex.svc.cluster.local",
          "port": 6333,
          "embedding_model_dims": 768
        }
      },
      "llm": {
        "provider": "openai",
        "config": {
          "model": "mistral-7b-instruct",
          "temperature": 0.1,
          "max_tokens": 2048,
          "openai_base_url": "http://local-ai-intel.cortex.svc.cluster.local:8080/v1",
          "api_key": "not-needed"
        }
      },
      "embedder": {
        "provider": "openai",
        "config": {
          "model": "nomic-embed-text",
          "openai_base_url": "http://local-ai-intel.cortex.svc.cluster.local:8080/v1",
          "api_key": "not-needed",
          "embedding_dims": 768
        }
      }
    }
  }'
```

> **Note**: `embedding_model_dims` (on vector_store) and `embedding_dims` (on embedder) must match. nomic-embed-text produces 768-dimensional vectors.

### 1b. Verify the config took effect

```bash
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl exec -n cortex deploy/mem0 -- \
  curl -s http://localhost:8765/api/v1/config/openmemory | python3 -m json.tool
```

You should see your Qdrant/LocalAI config in the response, not OpenAI defaults.

### 1c. Test memory operations

```bash
# Add a memory
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl exec -n cortex deploy/mem0 -- \
  curl -s -X POST http://localhost:8765/api/v1/memories/ \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "I prefer dark mode in all my applications"},
      {"role": "assistant", "content": "Noted, you prefer dark mode."}
    ],
    "user_id": "gavin"
  }'

# Search memories
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl exec -n cortex deploy/mem0 -- \
  curl -s -X POST http://localhost:8765/api/v1/memories/search/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "UI preferences",
    "user_id": "gavin",
    "limit": 5
  }'
```

If both return valid JSON with memory data, the mem0 → Qdrant → LocalAI pipeline is working.

### Known issue

GitHub issues #3238 and #3439 report that the config endpoint sometimes doesn't persist across restarts (hardcoded defaults override). If this happens:
- Re-send the PUT request after each pod restart
- Or: consider creating a startup Job/initContainer that sends the config on boot

---

## Step 2: Open WebUI — Pipelines + mem0 Filter

Open WebUI uses a **separate Pipelines service** (FastAPI on port 9099) that intercepts conversations. You need to deploy the Pipelines service and install a mem0 filter.

### 2a. Deploy the Pipelines service in Kubernetes

Create a new app at `kubernetes/apps/cortex/open-webui-pipelines/` with a HelmRelease that runs the `ghcr.io/open-webui/pipelines:main` image.

Key config:
```yaml
containers:
  app:
    image:
      repository: ghcr.io/open-webui/pipelines
      tag: main  # pin with digest after testing
    env:
      PORT: "9099"
      PIPELINES_API_KEY: "from-1password"  # or generate one
    ports:
      http:
        port: 9099
persistence:
  pipelines:
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 1Gi
    storageClass: ceph-block
    globalMounts:
      - path: /app/pipelines
```

Service URL will be: `open-webui-pipelines.cortex.svc.cluster.local:9099`

### 2b. Connect Pipelines to Open WebUI

1. Open **Open WebUI** in your browser: `https://open-webui.${SECRET_DOMAIN}`
2. Go to **Admin Panel** (gear icon, top-right) → **Settings** → **Connections**
3. Click the **+** button to add a new OpenAI API connection
4. Enter:
   - **API URL**: `http://open-webui-pipelines.cortex.svc.cluster.local:9099`
   - **API Key**: the `PIPELINES_API_KEY` value you set above
5. Save — look for a **Pipelines** icon to confirm the connection is active

### 2c. Install the mem0 filter pipeline

There are two options. **Option A** (self-hosted, uses your Qdrant + LocalAI directly) has a known Pydantic compatibility issue. **Option B** (talks to the mem0 REST API) is simpler.

#### Option B (recommended): Write a custom filter that calls the mem0 API

Since you already have a self-hosted mem0 API server, the simplest approach is a filter that calls it directly:

1. Go to **Admin Panel** → **Settings** → **Pipelines**
2. Upload this file (save it as `mem0_filter.py` first):

```python
"""
title: mem0 Memory Filter
description: Injects memories from self-hosted mem0 API into conversations
author: cortex-stack
version: 0.1.0
requirements: requests
"""

from typing import Optional
import requests
from pydantic import BaseModel, Field


class Pipeline:
    class Valves(BaseModel):
        pipelines: list[str] = Field(default=["*"])
        priority: int = Field(default=0)
        mem0_api_url: str = Field(default="http://mem0.cortex.svc.cluster.local:8765")
        recall_limit: int = Field(default=5)
        store_every_n: int = Field(default=3)

    def __init__(self):
        self.valves = self.Valves()
        self._message_count: dict[str, int] = {}

    async def on_startup(self):
        print("[mem0-filter] Started")

    async def on_shutdown(self):
        print("[mem0-filter] Stopped")

    async def inlet(self, body: dict, user: Optional[dict] = None) -> dict:
        """Before LLM: search memories and inject as system context."""
        if not user:
            return body

        user_id = user.get("id", user.get("email", "default"))
        messages = body.get("messages", [])
        if not messages:
            return body

        last_msg = messages[-1].get("content", "")
        if not last_msg:
            return body

        # Search for relevant memories
        try:
            resp = requests.post(
                f"{self.valves.mem0_api_url}/api/v1/memories/search/",
                json={
                    "query": last_msg,
                    "user_id": user_id,
                    "limit": self.valves.recall_limit,
                },
                timeout=5,
            )
            if resp.ok:
                data = resp.json()
                # Handle both list and dict responses
                memories = data if isinstance(data, list) else data.get("memories", data.get("results", []))
                if memories:
                    mem_text = "\n".join(
                        f"- {m.get('memory', m.get('text', str(m)))}"
                        for m in memories
                    )
                    system_msg = {
                        "role": "system",
                        "content": (
                            f"Relevant memories about this user:\n{mem_text}\n\n"
                            "Use these memories naturally in your response. "
                            "Do not mention that you retrieved them."
                        ),
                    }
                    # Insert after existing system messages
                    insert_idx = 0
                    for i, m in enumerate(messages):
                        if m.get("role") == "system":
                            insert_idx = i + 1
                        else:
                            break
                    messages.insert(insert_idx, system_msg)
                    body["messages"] = messages
        except Exception as e:
            print(f"[mem0-filter] Search error: {e}")

        # Store messages periodically
        self._message_count[user_id] = self._message_count.get(user_id, 0) + 1
        if self._message_count[user_id] >= self.valves.store_every_n:
            self._message_count[user_id] = 0
            try:
                store_messages = [
                    {"role": m["role"], "content": m["content"]}
                    for m in messages[-6:]  # last 3 exchanges
                    if m.get("role") in ("user", "assistant") and m.get("content")
                ]
                if store_messages:
                    requests.post(
                        f"{self.valves.mem0_api_url}/api/v1/memories/",
                        json={
                            "messages": store_messages,
                            "user_id": user_id,
                            "app_id": "open-webui",
                        },
                        timeout=10,
                    )
            except Exception as e:
                print(f"[mem0-filter] Store error: {e}")

        return body
```

### 2d. Configure the filter valves

1. After uploading, select the filter from the **Pipelines Valves** dropdown
2. Set:
   - `pipelines`: `["*"]` (apply to all models)
   - `mem0_api_url`: `http://mem0.cortex.svc.cluster.local:8765`
   - `recall_limit`: `5`
   - `store_every_n`: `3`
3. Save

### 2e. Verify

1. Open a new chat in Open WebUI
2. Tell it something personal: "I'm working on deploying LocalAI in my homelab"
3. Send a few more messages (to trigger the store cycle)
4. Start a **new chat** and ask: "What have I been working on?"
5. Check Pipelines container logs for `[mem0-filter]` messages

---

## Step 3: OpenClaw — mem0 Plugin for Discord

OpenClaw has a plugin slot system. The `memory` slot controls which plugin handles conversation memory.

### 3a. Choose a plugin

| Plugin | Install | Per-User? | Notes |
|--------|---------|-----------|-------|
| `@mem0/openclaw-mem0` (official) | `npm install` | Static userId | Simplest, but no per-Discord-user isolation |
| `tensakulabs/openclaw-mem0` | `git clone` | Static userId | Better OSS mode config, same limitation |
| `kshidenko/openclaw-mem0-v2` | `git clone` | Identity map file | Maps Discord users to mem0 user_ids via JSON config |

**Recommended**: `kshidenko/openclaw-mem0-v2` — it supports an identity map that lets you scope memories per Discord user.

### 3b. Install the plugin

Exec into the OpenClaw pod or use the code-server at `cortex-code.${SECRET_DOMAIN}`:

```bash
# From inside the OpenClaw container
cd ~/.openclaw/extensions
git clone https://github.com/kshidenko/openclaw-mem0-v2.git memory-mem0
cd memory-mem0
npm install
```

Or install via the OpenClaw CLI:
```bash
openclaw plugins install github:kshidenko/openclaw-mem0-v2
openclaw plugins enable mem0-memory
```

### 3c. Create the identity map

Create `/home/node/.openclaw/identity-map.json`:

```json
{
  "identities": [
    {
      "canonical": "gavin",
      "aliases": ["discord:YOUR_DISCORD_USER_ID"],
      "label": "Gavin"
    },
    {
      "canonical": "wife",
      "aliases": ["discord:WIFE_DISCORD_USER_ID"],
      "label": "Wife"
    }
  ]
}
```

Replace `YOUR_DISCORD_USER_ID` with your actual numeric Discord user ID. You can find it by enabling Developer Mode in Discord (Settings → Advanced → Developer Mode), then right-click your name → Copy User ID.

### 3d. Update the OpenClaw config

The OpenClaw config is managed via the `openclaw-config` ExternalSecret. You need to add a `plugins` section to the config JSON.

Edit the ExternalSecret at `kubernetes/apps/cortex/openclaw/app/externalsecret.yaml` — add the plugins block to the `openclaw.json` template:

```json
"plugins": {
  "enabled": true,
  "load": {
    "paths": ["/home/node/.openclaw/extensions"]
  },
  "slots": {
    "memory": "mem0-memory"
  },
  "entries": {
    "mem0-memory": {
      "enabled": true,
      "config": {
        "mode": "open-source",
        "userId": "openclaw",
        "identityMapPath": "/home/node/.openclaw/identity-map.json",
        "autoCapture": true,
        "autoRecall": true,
        "recallLimit": 5,
        "recallThreshold": 0.4,
        "oss": {
          "llm": {
            "provider": "openai",
            "config": {
              "apiKey": "not-needed",
              "baseURL": "http://local-ai-intel.cortex.svc.cluster.local:8080/v1",
              "model": "mistral-7b-instruct"
            }
          },
          "embedder": {
            "provider": "openai",
            "config": {
              "apiKey": "not-needed",
              "baseURL": "http://local-ai-intel.cortex.svc.cluster.local:8080/v1",
              "model": "nomic-embed-text"
            }
          },
          "vectorStore": {
            "provider": "qdrant",
            "config": {
              "host": "qdrant.cortex.svc.cluster.local",
              "port": 6333,
              "collectionName": "openclaw-memories"
            }
          }
        }
      }
    }
  }
}
```

**Alternative (simpler)**: If you'd rather have OpenClaw talk to the mem0 API server instead of directly to Qdrant, use this config instead:

```json
"plugins": {
  "enabled": true,
  "load": {
    "paths": ["/home/node/.openclaw/extensions"]
  },
  "slots": {
    "memory": "mem0-memory"
  },
  "entries": {
    "mem0-memory": {
      "enabled": true,
      "config": {
        "baseUrl": "http://mem0.cortex.svc.cluster.local:8765",
        "userId": "openclaw",
        "identityMapPath": "/home/node/.openclaw/identity-map.json",
        "autoCapture": true,
        "autoRecall": true,
        "recallLimit": 5
      }
    }
  }
}
```

### 3e. Verify

1. Restart the OpenClaw pod (or let Flux reconcile after pushing config changes)
2. In Discord, mention the bot in the configured channel
3. Tell it something: "@CORTEX I'm working on Cilium BGP peering"
4. In a new message, ask: "@CORTEX What have I been working on?"
5. Check pod logs: `kubectl logs -n cortex deploy/openclaw -c app | grep mem0`

---

## Step 4: Claude Code — mem0 MCP Server

The OpenMemory server exposes an SSE-based MCP endpoint. Claude Code can connect to it.

### 4a. Expose mem0 via Tailscale or port-forward

The mem0 service is cluster-internal. You need to make it reachable from your local machine. Options:

**Option A — Add a route (recommended if you want persistent access):**

Add to the mem0 HelmRelease:
```yaml
route:
  app:
    annotations:
      internal-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}
    hostnames:
      - mem0.${SECRET_DOMAIN}
    parentRefs:
      - name: internal
        namespace: network
        sectionName: https
```

**Option B — Port-forward (quick testing):**
```bash
KUBECONFIG=/home/gavin/home-ops/kubeconfig kubectl port-forward -n cortex svc/mem0 8765:8765
```

### 4b. Add the MCP server to Claude Code

The MCP endpoint URL format is:
```
http://mem0.${SECRET_DOMAIN}:8765/mcp/claude/sse/gavin
```

Where `claude` is the app name and `gavin` is the user_id.

**Method 1 — CLI (recommended):**
```bash
claude mcp add --transport sse --scope user openmemory \
  "http://mem0.${SECRET_DOMAIN}/mcp/claude/sse/gavin"
```

If SSE transport doesn't work directly, use the supergateway bridge:

**Method 2 — Bridge via supergateway:**
```bash
claude mcp add --scope user openmemory -- \
  npx -y supergateway --sse "http://mem0.${SECRET_DOMAIN}/mcp/claude/sse/gavin"
```

**Method 3 — Manual JSON in `~/.claude.json`:**
```json
{
  "mcpServers": {
    "openmemory": {
      "command": "npx",
      "args": [
        "-y",
        "supergateway",
        "--sse",
        "http://mem0.nerdz.cloud/mcp/claude/sse/gavin"
      ]
    }
  }
}
```

### 4c. Verify

```bash
claude mcp list
```

You should see `openmemory` listed. Start a new Claude Code session and the MCP tools should appear:
- `add_memories` — store memories
- `search_memory` — semantic search
- `list_memories` — list all memories

Test with: "Remember that I prefer Cilium over Calico for CNI"

Then in a new session: "What CNI do I prefer?"

---

## Step 5: Verify Cross-Interface Memory

This is the whole point. Once all three are wired:

1. **Discord**: Tell CORTEX "I'm debugging a Ceph OSD issue on node ms-01-c"
2. **Open WebUI**: Ask "What am I debugging?" — should recall the Ceph issue
3. **Claude Code**: Ask "What infrastructure issues am I working on?" — should recall both

All three interfaces write to the same mem0 instance, scoped by `user_id = gavin`. Memories stored from Discord are searchable from Open WebUI and Claude Code.

---

## Troubleshooting

| Problem | Check |
|---------|-------|
| mem0 config resets to OpenAI defaults on restart | Re-send the PUT `/api/v1/config/openmemory` — known upstream issue |
| "embedding_dims mismatch" error | Ensure vector_store `embedding_model_dims` = embedder `embedding_dims` = 768 (for nomic-embed-text) |
| Pipelines connection fails in Open WebUI | Verify the service URL uses the k8s internal DNS name, not localhost |
| OpenClaw plugin not loading | Check `openclaw plugins list` in the pod, verify plugin path matches `load.paths` |
| Claude Code MCP not connecting | Try the supergateway bridge; check if the mem0 route is accessible from your machine |
| Memories not found cross-interface | Verify all three use the same `user_id` string (e.g., "gavin") |
| Search returns empty | Check Qdrant has a `mem0` collection: `curl http://qdrant:6333/collections` |

---

## Architecture Summary

```
Discord → OpenClaw → mem0 plugin → mem0 API (:8765) → Qdrant + LocalAI
Browser → Open WebUI → Pipelines (:9099) → mem0 filter → mem0 API (:8765) → Qdrant + LocalAI
Terminal → Claude Code → MCP (SSE) → mem0 API (:8765) → Qdrant + LocalAI
```

All paths converge at the mem0 API server. All memories scoped by `user_id`.
