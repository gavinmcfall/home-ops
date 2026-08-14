---
description: "{{title}} — LLM context: apps, routes, storage, flows"
tags: ["{{DomainCamel}}", "DomainDocs"]
audience: ["LLMs"]
categories: ["Reference[100%]", "DomainContext[95%]"]
---

# {{title}} — Context

<!-- generated:start section=apps -->
## Apps

| App | Namespace | Source | Route | Storage | Backup | Secrets | DependsOn |
|---|---|---|---|---|---|---|---|
| [{{app}}](../../../kubernetes/apps/{{ns}}/{{app}}) | {{ns}} | {{chart-or-image}} | {{host+gateway-or-none}} | {{pvc-class-size-or-none}} | {{volsync-or-none}} | {{es-store-or-none}} | {{dependsOn-or-none}} |
<!-- generated:end -->

<!-- generated:start section=dataflow -->
## Data Flow

```mermaid
{{dataflow-diagram}}
```
<!-- generated:end -->

<!-- generated:start section=integration -->
## Integration Points

- {{other-domain}}: {{one-line-touchpoint-with-links}}
<!-- generated:end -->

<!-- curated -->
## Capsules

<!-- Add capsules per docs/ai-context/writing-capsules.md. Skill never edits below. -->
<!-- /curated -->
