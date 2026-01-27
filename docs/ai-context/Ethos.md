---
description: Documentation philosophy defining hard rules, strong guidance, and values for knowledge capture
tags: ["DocumentationPhilosophy", "HardRules", "StrongGuidance", "KnowledgeCapture", "EvidenceHierarchy"]
audience: ["LLMs", "Humans"]
categories: ["Philosophy[100%]", "Documentation[95%]"]
---

# Ethos: Documentation Philosophy and Principles

**Purpose**: The values, principles, and rules that guide what we capture in this knowledge base.

**Audience**: AI agents and humans contributing to repository documentation.

---

## The Philosophy

This knowledge base exists to answer: **"How does this homelab infrastructure work as a coherent whole?"**

Not "how do I use kubectl?" or "what's the Helm chart syntax?" - those belong in external docs. This is the **context layer** that explains why the system is designed this way, how components relate, and what invariants must be preserved.

**After 10-15 minutes reading**, you should understand:
1. **What it does** - GitOps-managed Kubernetes homelab
2. **How it does it** - Taskfile + Makejinja + Flux + Talos
3. **What must stay true** - Invariants and constraints
4. **How to find more** - Pointers to specific manifests and configs

**This is not classical documentation.** Classical docs explain how to use a tool. This explains how tools work together to manage infrastructure declaratively.

---

## The Hard Rules (Never Violate)

These are non-negotiable. Violating them undermines the entire knowledge base.

### Rule 1: Only Record What You Can Verify

**Why**: Wrong information is worse than missing information.

**Hierarchy of evidence** (prefer higher levels):
1. **Code** - Directly observed in manifests, Taskfile, scripts
2. **Documentation** - Stated in existing docs or READMEs
3. **Synthesis** - Derived from multiple verified sources
4. **User** - Confirmed by the operator
5. **Intuition** - Inferred from patterns (mark as low confidence)

### Rule 2: When in Doubt, Omit

**Why**: Missing information prompts questions. Wrong information causes failed deployments and wasted debugging.

Better to say "see the HelmRelease for details" than guess incorrectly.

**The cost calculation**:
- **Wrong information** - Incorrect manifests, broken deployments, hours of debugging
- **Missing information** - Extra research time, asking for clarification

Missing is recoverable. Wrong is destructive.

### Rule 3: Never Use Actual Domain Names

**Why**: This is a public repository. Actual domain names leak information and create security exposure.

**Always use placeholders**:
- `${SECRET_DOMAIN}` - The primary domain (e.g., in hostnames, URLs, DNS records)
- `${SECRET_CLOUDFLARE_TUNNEL_ID}` - Tunnel identifiers
- `${SECRET_*}` - Any other sensitive values

**In documentation**:
- Write `app.${SECRET_DOMAIN}` not the actual URL
- Write `id.${SECRET_DOMAIN}` not the actual identity provider URL
- Use "DOMAIN" in ASCII diagrams where variable syntax breaks formatting

**The test**: `grep -r "nerdz" docs/` should return zero results.

---

## Strong Guidance (Follow Unless You Have Good Reason)

These patterns create durable, useful documentation. Deviation should be intentional and justified.

### Capture Temporally Stable Information

**Prefer documenting**:
- Architectural patterns (GitOps, Flux reconciliation, Talos immutability)
- Infrastructure constraints (placeholder-based secrets, storage requirements)
- Operational invariants (task configure before push, never edit generated files)
- Critical dependencies (Flux depends on secrets, pods depend on PVCs)

**Avoid documenting**:
- Specific versions ("Flux 2.3.0") - unless they create understanding
- Point-in-time info ("recently added", "planned upgrade")
- Configuration values (belong in manifests)
- Step-by-step tutorials (belong in external docs)

**The test**: Will this still be true in 6 months? If not, consider omitting unless it substantially aids understanding.

### Document Shape, Not Detail

**Good**: "Each app follows the kustomization + HelmRelease + ExternalSecret triad"

**Bad**: "The romm app has env vars ROMM_DB_HOST, ROMM_DB_PORT, ROMM_DB_NAME..."

**Why**: Implementation details change. The conceptual structure persists.

### Focus on Why, Not Just What

**Good**: "Secrets use placeholders because the repo is public and values must not leak"

**Bad**: "Add `${SECRET_DOMAIN}` to the ingress host field"

**Why**: The "why" teaches the principle. The "what" becomes obvious once you understand why.

### Document Patterns, Not Instances

**Good**: "HelmReleases define persistence sections with existingClaim, tmpfs, or NFS mounts"

**Bad**: "romm uses romm-data claim, plane uses plane-data claim, bookstack uses..."

**Why**: Patterns are durable. Instance lists go stale and create maintenance burden.

---

## The Values (These Guide Our Choices)

### We Value Context Over Completeness

Every component must answer: **"Where does this fit in the wider system?"**

Required context:
- What layer? (Flux, Talos, app, infrastructure)
- What depends on this? (blast radius)
- What does this depend on? (prerequisites)
- What breaks if this changes?

### We Provide Trails, Not Destinations

**Good**: "For storage configuration, see `kubernetes/apps/games/romm/app/helmrelease.yaml:102-140`"

**Bad**: Duplicating the entire persistence section here

**Why**: This knowledge base points to specific locations; it doesn't replace reading the actual configs.

### We Document Non-Obvious Truths

Capture things that:
- Surprise newcomers to the system
- Waste significant time when misunderstood
- Reflect infrastructure complexity (not just tooling quirks)
- Matter in operations (not just theory)

Examples:
- Flux reverts manual kubectl changes (GitOps fundamental)
- ExternalSecrets must sync before pods can start (ordering dependency)
- `task configure` must run before push (template pipeline)

---

## The Right Level of Abstraction

### Conceptual Understanding
**Capture**: Mental models that explain behavior across many scenarios

**Example**: "GitOps means the cluster converges to match Git state"

### Structural Relationships
**Capture**: How components relate and depend on each other

**Example**: "Taskfile renders templates, Flux applies them, Talos manages nodes"

### Architectural Constraints
**Capture**: Why the system works this way, not just how

**Example**: "Placeholders keep secrets out of the public repo while documenting required keys"

### Integration Points
**Capture**: How components connect, what protocols, what data flows

**Example**: "ExternalSecrets pull from 1Password, populate Kubernetes secrets, HelmReleases reference them via envFrom"

---

## Success Looks Like

### Quick Orientation (10-15 minutes)
- Understand what the homelab runs
- Know how deployments flow from Git to cluster
- Identify key constraints and invariants
- Find pointers to specific configs

### Confident Decision Making
- Where should new apps go?
- What are the prerequisites for a deployment?
- What invariants must be preserved?
- What breaks if I change this?

### Effective Troubleshooting
- Which components are involved in a failure?
- Where are likely failure points?
- What commands reveal state?
- How do changes flow through the system?

---

## Failure Looks Like

- **False Confidence** - Wrong information leading to broken deployments
- **Analysis Paralysis** - Too much detail without clear patterns
- **Maintenance Burden** - Information that goes stale quickly
- **Knowledge Silos** - Details without context of wider system

---

## When to Break the Guidance

The strong guidance exists to create durable, useful documentation. But **if breaking it aids understanding, break it**.

**Example**: We generally avoid specific counts. But "Flux reconciles every 5 minutes" substantially improves understanding of operational behavior. Keep it.

**The test**: Does this create the "aha!" moment? Does it explain why the system works this way? If yes, keep it even if it technically violates guidance.

**Remember**: The hard rules are never negotiable. The guidance is strong but not absolute. The philosophy explains why we do what we do.

---

## The Meta-Principle

**We document the durable conceptual structure**, not the ephemeral implementation details.

**We capture why the system exists and how components relate**, then point to manifests for specifics.

**We create maps, not transcripts** - wisdom triggers that activate understanding, not dumps of information.

**Test**: Could someone read this and make informed decisions about where new functionality belongs and what the implications would be?

---

**Hierarchy**:
1. **Hard Rules** - Never violate
2. **Strong Guidance** - Follow unless you have good reason
3. **Philosophy** - Understand the why behind our choices
