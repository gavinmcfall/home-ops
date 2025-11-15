# Homelab Guidance for Claude/Codex

You are a thinking partner, not a shell runner. Use this playbook before editing `/home/gavin/home-ops`.

---

## Step 1: Read the Foundation Docs (in order)
1. **`TOOLS.md`** – Learn the search strategy (`rg`, `task`, `flux diff`) and how to verify claims.
2. **`README.md`** – Understand the knowledge base’s purpose, navigation pattern, and invariants.
3. **`ARCHITECTURE.md`** – Internal mental model for GitOps/Talos/Flux, decisions, constraints, failure modes.
4. **`DOMAIN.md`** – Domain rules, lifecycle diagrams, glossary.
5. **`CONTRACTS.md`** – Integration guarantees for Taskfile, Flux, ExternalSecrets.
6. **`WORKFLOWS.md`** – Operational runbooks for HelmRelease onboarding and rolling updates.
7. **`TEMPLATE_GUIDE.md`** – Placeholder inventory, evidence standards, maintenance cadence.
8. **`QUESTIONS.md`** – Known gaps to prioritize.

Do not start coding until you can restate the GitOps pipeline (Taskfile → Flux → ExternalSecrets) and cite where placeholders live.

---

## Step 2: Discover the Repository Surface
Before reading random files, inventory the repo:
```bash
ls bootstrap talosconfig kubernetes/apps scripts
rg -n "helmrelease" kubernetes/apps --files
rg -n "\${SECRET_DOMAIN}" kubernetes/apps -g"*.yaml"
```
- Map `kubernetes/apps/<area>/app` directories and their `kustomization.yaml` parents.
- Identify placeholder usage (`${SECRET_DOMAIN}`, `${MEDIA_SERVER}`, `PLANE_*`) via `rg`.
- Use `task --list` or read `Taskfile.yaml` to see orchestration entry points.

Only after you know what exists should you drill into a specific app or script.

---

## Step 3: Work Within These Rules
- **Stay scoped** to `/home/gavin/home-ops`. No cross-repo edits or assumptions.
- **Never leak secrets**: keep hostnames/paths abstract (`${SECRET_DOMAIN}`, `${DB_URI}`).
- **Cite sources**: every architectural claim in `.codex/Homelab` must reference files like `Taskfile.yaml`, `kubernetes/apps/games/romm/app/helmrelease.yaml`, or `README.md`.
- **Prefer omission over speculation**: if you can’t verify something, add it to `QUESTIONS.md` rather than guessing.
- **Run commands intentionally**: `task configure`, `task kubernetes:kubeconform`, and `flux diff` are the validation tools; don’t invent new ones without reason.

Following these steps recreates the disciplined workflow this knowledge base expects for the homelab repo.
