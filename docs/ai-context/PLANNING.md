---
description: Collaborative planning lifecycle for AI-assisted work across any codebase
tags: ["Planning", "RiskAssessment", "PreMortem", "IncidentResponse", "Collaboration"]
audience: ["LLMs", "Humans"]
categories: ["Workflows[100%]", "Philosophy[70%]"]
---

# Collaborative Planning Lifecycle

Structured collaboration between human and AI produces better outcomes than ad-hoc requests. This document captures the lifecycle: **Idea → Planning → Risk Assessment → Execution → Incident Response**.

---

## Philosophy

**Why structure matters**: Complex changes benefit from exploration before action. Rushing to implementation risks missing dependencies, breaking existing functionality, or solving the wrong problem.

**Lightweight, not bureaucratic**: These phases are mental checkpoints, not formal gates. A simple change might flow through all five in minutes. A complex migration might spend hours in planning.

**Portable foundation**: This lifecycle applies to any AI-assisted work—infrastructure, code, documentation, or configuration.

---

## The Five Phases

```
Idea → Planning → Risk Assessment → Execution → Incident Response
  │        │              │              │              │
  │        │              │              │              └─ Learn from failures
  │        │              │              └─ Small steps, verify each
  │        │              └─ What could go wrong?
  │        └─ Explore before proposing
  └─ Problem + outcome, not solution
```

| Phase | Focus | Key Question |
|-------|-------|--------------|
| Idea | Intent | What problem are we solving? |
| Planning | Discovery | What exists? What patterns? |
| Risk | Prevention | What could go wrong? |
| Execution | Progress | Did each step succeed? |
| Incident | Learning | What happened? What did we learn? |

---

## Phase Capsules

### Capsule: IdeaCapture

**Invariant**
State the problem and desired outcome; avoid prescribing implementation.

**Example**
- Good: "Users can't access the app when Tailscale is down"
- Bad: "Add a fallback ingress controller"

The first invites exploration; the second assumes a solution.

**Depth**
- Distinction: Intent describes the problem; solution describes one fix
- Trade-off: Open framing takes longer but finds better solutions
- NotThis: Jumping straight to "add X" or "change Y"
- SeeAlso: ExplorationFirst

---

### Capsule: ExplorationFirst

**Invariant**
Understand the codebase before proposing changes; use tools to discover what exists.

**Example**
```
RepoQL xray → find related files → read existing patterns → propose approach
```
//BOUNDARY: Never propose changes to code you haven't read

**Depth**
- Techniques: RepoQL semantic search, fuzzy grep, cross-namespace scanning
- Trade-off: Time exploring vs missing critical dependencies
- NotThis: Proposing solutions based on assumptions
- SeeAlso: RiskDiscovery

---

### Capsule: RiskDiscovery

**Invariant**
Ask "what could go wrong?" during planning; identify blast radius and dependencies.

**Example**
Before changing a shared resource:
1. What uses this? (grep, RepoQL edges)
2. What breaks if this fails? (blast radius)
3. What's the rollback? (revert path)

//BOUNDARY: Changes with unknown blast radius require explicit acknowledgment

**Depth**
- Questions: What depends on this? What does this depend on? Can we test safely?
- Techniques: Cross-namespace grep, Kustomization dependency chains, HelmRelease dependsOn
- NotThis: Formal pre-mortem sessions (integrate naturally into planning)
- SeeAlso: IncrementalExecution

---

### Capsule: IncrementalExecution

**Invariant**
Make small, verifiable changes; validate before proceeding to next step.

**Example**
Deploying a new app:
1. Create namespace → `kubectl get ns` confirms
2. Add secret → `flux get externalsecrets` shows Ready
3. Deploy HelmRelease → `flux get hr` shows Ready
4. Add route → curl confirms accessible

**Depth**
- Checkpoints: After each logical unit, pause and verify
- Trade-off: Slower execution vs catching issues early
- NotThis: Big-bang deployments that change everything at once
- SeeAlso: RiskDiscovery

---

### Capsule: BlamelessLearning

**Invariant**
When things fail, ask "what happened" and "how", never "who" or "why didn't you".

**Example**
- Good: "What information was missing when that decision was made?"
- Good: "What did you expect to happen? What actually happened?"
- Bad: "Why didn't you check the dependencies first?"

**Depth**
- Focus: System factors and missing information, not individual fault
- Questions: What did you see? What did you expect? What was surprising?
- Goal: Understanding over fixing; learning over blame
- NotThis: Finding someone to blame; rushing to "fix it"
- SeeAlso: Etsy's blameless postmortem philosophy

---

## Risk Discovery Techniques

Lightweight risk assessment integrated into the planning phase. Not a formal pre-mortem—just good habits.

### Dependency Discovery

Before modifying a resource, find what uses it:

```sql
-- RepoQL: Find references to a resource
SELECT uri, symbol, line_start
FROM search('ResourceName', k := 20)
WHERE scope = 'object'
```

Natural language: "Let me check what else references this..."

### Blast Radius Assessment

For each proposed change:
- **If this fails, what stops working?** (downstream impact)
- **If we need to revert, how?** (rollback path)
- **Can we test this safely?** (staging, dry-run)

Check: Kustomization `dependsOn`, HelmRelease `dependsOn`, cross-namespace references

### Gap Detection

Before implementing, search for existing patterns:

```bash
# Fuzzy search for similar implementations
grep -r "similar-pattern" kubernetes/apps/
```

Questions:
- "Are there similar implementations I should follow?"
- "Does this namespace already have this pattern?"

### Explicit Unknowns

When uncertain, say so:
- "I'm not sure how X interacts with Y—should we verify?"
- "This might affect Z but I'd need to check"

Mark confidence: High (verified), Medium (inferred), Low (assumption)

---

## Incident Response Principles

When things go wrong, shift to learning mode.

### The Blameless Mindset

**Core belief**: People make decisions that seem reasonable given the information they have at the time. If an action caused problems, the interesting question is "what made that action seem reasonable?"

### Questions That Help

| Instead of | Ask |
|------------|-----|
| "Why did you do that?" | "What were you trying to achieve?" |
| "Didn't you see the warning?" | "What information did you have at the time?" |
| "Who approved this?" | "What was the review process?" |
| "Why wasn't this tested?" | "What testing was done? What was missed?" |

### Learning Over Fixing

The first instinct after an incident is to fix it immediately. Resist this:

1. **Understand first** - What actually happened? What was the sequence?
2. **Gather perspectives** - What did each person see and think?
3. **Identify gaps** - What information or tooling would have helped?
4. **Then remediate** - Now fix the immediate issue
5. **Finally prevent** - What systemic changes reduce recurrence?

---

## Checklist (Non-Negotiables)

- [ ] State problem and outcome, not solution (IdeaCapture)
- [ ] Explore codebase before proposing changes (ExplorationFirst)
- [ ] Identify what could go wrong and blast radius (RiskDiscovery)
- [ ] Make small changes with verification (IncrementalExecution)
- [ ] Ask "what/how" not "who/why" after failures (BlamelessLearning)

---

## Lessons Learned: Kopia Migration (Dec 2025)

Real-world example of planning failures and recovery during the Volsync Kopia migration.

### Wrong Assumptions Made

| Assumption | Reality | Impact |
|------------|---------|--------|
| MutatingAdmissionPolicy feature gate "just works" | Requires Talos patch for apiServer extraArgs + runtime-config | Had to create patch, regenerate configs, roll out to all nodes |
| K8s 1.33 uses MutatingAdmissionPolicy v1beta1 | Uses **v1alpha1** (v1beta1 is K8s 1.34+) | API server crash, had to fix and reapply |
| ClusterSecretStore named `onepassword` | Named `onepassword-connect` | ExternalSecrets failed to sync |
| app-template creates ConfigMap as `kopia-config` | Creates as `kopia` | Pod stuck in ContainerCreating |
| `task talos:apply` exists | Doesn't exist - use `talosctl apply-config` | Had to look up correct commands |
| Kopia repository pre-exists | NFS path was empty | Kopia server crashed on startup |
| Reference patterns from docs/guides were tested | They were aspirational, not validated | Multiple fixes needed |

### What Would Have Helped

1. **Check feature gate requirements before planning**
   - Search for "how to enable X on Talos/K8s" first
   - Check if alpha features need runtime-config in addition to feature-gates
   - Look at reference repos (Devin, Jory, Kashall) for existing patches

2. **Verify API versions before implementing**
   ```bash
   kubectl api-resources --api-group=admissionregistration.k8s.io
   kubectl api-versions | grep admission
   ```

4. **Check existing resource names**
   ```bash
   kubectl get clustersecretstore
   kubectl get configmaps -n <namespace>
   ```

5. **Look at working implementations first**
   - Check Devin's, Jory's, Kashall's repos for patterns
   - Don't assume docs/guides are tested

6. **Dry-run everything**
   - `talosctl apply-config --dry-run`
   - `kubectl apply --dry-run=server`

7. **Test feature gates on one node first**
   - Rolling upgrade approach saved the cluster

### Capsule: VerifyBeforeImplement

**Invariant**
Check that APIs, resources, and patterns exist before writing manifests.

**Example**
```bash
# Before using MutatingAdmissionPolicy
kubectl api-resources | grep -i mutating

# Before referencing ClusterSecretStore
kubectl get clustersecretstore

# Before referencing ConfigMap by name
helm template <release> | grep -i configmap
```

**Depth**
- Documentation may be outdated or aspirational
- Feature gates have version-specific API versions
- Chart behavior differs from intuition (naming, structure)
- Always cross-reference with working implementations

---

## Sources

- [Atlassian Pre-Mortem Play](https://www.atlassian.com/team-playbook/plays/pre-mortem) - Risk identification methodology
- [Etsy Debriefing Facilitation Guide](https://www.etsy.com/codeascraft/debriefing-facilitation-guide) - Blameless postmortem philosophy
- [PagerDuty Blameless Postmortem](https://postmortems.pagerduty.com/culture/blameless/) - "What/how" questioning techniques
