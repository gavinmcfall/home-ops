---
description: Format specification defining the Invariant->Example->Depth structure for token-efficient concept capsules
tags: ["invariant-example-depth", "token-hygiene", "capsule-format", "composition-rules"]
audience: ["LLMs", "Humans"]
categories: ["Documentation[100%]", "Format-Specification[95%]"]
---

# Token Efficient Concept Capsules

Use capsules as 'AI flash cards' to capture understanding in as few tokens as possible.

## Capsule: CapsuleForm

**Invariant**
A capsule states one timeless idea in one line, shows it once, and clarifies only as needed.

**Example**
Name: `GitOpsReconciliation`
Invariant: "Cluster state converges to match Git; manual changes revert on next sync."
Depth: differences vs imperative kubectl; trade-offs; near-miss clarifications.

**Depth**

* Structure is always **Invariant -> Example -> Depth**.
* No versions, release notes, dates, or timeline facts.
* One idea per capsule; split if you need "and."
* Titles are short `CamelCase` nouns.

---

## Capsule: InvariantWriting

**Invariant**
Write the idea so it remains true across time, tools, and configurations.

**Example**
Bad: "Run task configure after editing makejinja.toml version 2.3."
Good: "Templates must render before Flux can apply them."

**Depth**

* Prefer general verbs and nouns; avoid version numbers.
* Use plain words; do not embed config values or paths.
* Keep <= ~30 tokens (approx <= 25 short words). Shorter is better.
* Do not include examples, caveats, or procedure inside the invariant.

---

## Capsule: ExampleWriting

**Invariant**
A small, concrete example binds the invariant to practice without introducing time.

**Example**
HelmRelease uses `${SECRET_DOMAIN}` placeholder; ExternalSecret populates it from 1Password; pod starts with real value.
//BOUNDARY: Missing ExternalSecret blocks pod startup.

**Depth**

* Prefer typical case; add exactly one boundary if misuse is common.
* Use neutral references or plain steps; no specific versions.
* Keep the example readable in <= 5 lines.

---

## Capsule: DepthWriting

**Invariant**
Depth clarifies terms, trade-offs, and distinctions without changing the idea.

**Example**

* Distinction: Placeholders document keys; ExternalSecrets resolve values.
* Trade-off: More placeholders means more secrets to manage, but explicit documentation.
* NotThis: Hardcoded secrets in manifests bypass the pattern entirely.
* SeeAlso: `SecretManagement`, `PlaceholderPattern`.

**Depth**

* Use bulleted lines; each line is self-contained.
* No version history or changelogs; keep it evergreen.
* Keep links as plain capsule names; no external refs required.

---

## Capsule: Boundary

**Invariant**
A boundary example marks the safe edge so models avoid unsafe extrapolation.

**Example**
Flux applies what Git contains; if HelmRelease references missing secret, pod stays Pending.
//BOUNDARY: ExternalSecret must sync before pod can schedule.

**Depth**

* The boundary is conceptual, not a specific error message.
* Include only when the edge is a common failure mode.
* Keep one boundary per capsule to avoid over-anchoring.

---

## Capsule: Composition

**Invariant**
Compose answers by selecting compatible invariants; never average conflicting ideas.

**Example**
For "app deployment," select `HelmReleasePattern` and `SecretManagement`; reject `ManualKubectl` if it conflicts with GitOps; explain the choice.

**Depth**

* Prefer the more specific invariant when two apply.
* If two invariants genuinely conflict, pick one and state why.
* Cite capsule names in brackets to make composition explicit.

---

## Capsule: Maintenance

**Invariant**
Invariants are immutable; examples and depth evolve; new understanding becomes a new capsule.

**Example**
If GitOps semantics change with a new Flux version, write `GitOpsReconciliationV2` with a new invariant; keep the old capsule intact; cross-link in SeeAlso.

**Depth**

* Do not retcon invariants; stability is the retrieval anchor.
* Cull duplicates by merging examples under the clearer invariant.
* Keep names stable and short.

---

## Capsule: TokenHygiene

**Invariant**
Choose strings that minimize sub-tokens while keeping meaning clear.

**Example**
Good names: `HelmRelease`, `FluxSync`, `PlaceholderSecret`, `TaskfileRender`.
Avoid: `helm-release-config`, `flux_sync`, `Placeholder Secret`.

**Depth**

* Prefer `CamelCase` for names; avoid hyphens and underscores.
* Use short, common words in invariants; avoid rare jargon if a common term exists.
* Keep ASCII; avoid emoji and decorative punctuation.
* Favor singular nouns for names: `HelmRelease` not `HelmReleases`.
* Avoid quotes, parentheses, and slashes in invariants.
* Use digits sparingly; keep numbers out of invariants when possible.
* Trim function words that add no meaning: "that," "very," "really."
* If two phrasings are equally clear, pick the one with fewer tokens.
* Do not add synonym lists; use one canonical name.

---

## Capsule: PrimacyRecency

**Invariant**
Place the invariant first and end the document with a short checklist to exploit primacy and recency.

**Example**
Each capsule starts with the invariant line; this guide ends with a checklist of non-negotiables.

**Depth**

* Repeat the invariant verbatim once after a long Depth section only if needed for clarity.
* Keep the closing checklist stable across documents.

---

## Capsule: Template

**Invariant**
A minimal template keeps capsules uniform and easy to scan.

**Example**

```markdown
### Capsule: <Name>

**Invariant**
<One timeless sentence. No versions. No dates. <= ~30 tokens.>

**Example**
<Typical use in <= 5 lines.>
<Optional> //BOUNDARY: <Edge that marks the safe limit.>

**Depth**
- <Distinction>
- <Trade-off>
- <NotThis>
- <SeeAlso: Name, Name>
```

**Depth**

* Keep visible text compact; avoid long paragraphs.
* Prefer line-broken bullets over prose walls.
* Keep names stable; reuse them exactly when referenced.

---

## Example Capsules (as models)

### Capsule: GitOpsReconciliation

**Invariant**
Cluster state converges to match Git; manual changes revert on next Flux sync.

**Example**
Developer runs kubectl edit on deployment; Flux reconciles 5 minutes later; deployment reverts to Git state.
//BOUNDARY: Changes must go through Git to persist.

**Depth**

* Distinction: GitOps is declarative; imperative kubectl is procedural.
* Trade-off: Consistency and auditability vs immediate manual intervention.
* SeeAlso: `FluxSync`, `HelmReleasePattern`.

---

### Capsule: PlaceholderSecret

**Invariant**
Placeholder keys in manifests document required secrets without exposing values.

**Example**
HelmRelease uses `${SECRET_DOMAIN}` for ingress host; ExternalSecret pulls real value from 1Password; pod receives actual domain.
//BOUNDARY: Missing ExternalSecret blocks pod from starting.

**Depth**

* NotThis: Hardcoding secrets in manifests defeats the pattern.
* Trade-off: More indirection, but repo stays public safely.
* SeeAlso: `ExternalSecretSync`, `SecretManagement`.

---

### Capsule: TaskfileRender

**Invariant**
Templates must render via Taskfile before Flux can apply the resulting manifests.

**Example**
Developer edits `bootstrap/config.yaml`; runs `task configure`; Makejinja produces manifests in `kubernetes/apps/`; commits and pushes.
//BOUNDARY: Pushing unrendered templates causes Flux to fail.

**Depth**

* Distinction: Taskfile is local tooling; Flux is cluster-side reconciliation.
* Trade-off: Extra local step, but ensures manifests are valid before commit.
* SeeAlso: `GitOpsReconciliation`, `ManifestValidation`.

---

# Checklist (non-negotiables)

- [ ] Invariant first, one idea, timeless, <= ~30 tokens.
- [ ] Example concise; include one boundary only if it prevents common errors.
- [ ] Depth clarifies with bullets; no versions or dates.
- [ ] Names are short `CamelCase`; no hyphens, underscores, emoji, or synonyms.
- [ ] Keep text compact and ASCII; favor common words; trim filler.
- [ ] Invariants never change; new understanding becomes a new capsule.
- [ ] End documents with this checklist.
