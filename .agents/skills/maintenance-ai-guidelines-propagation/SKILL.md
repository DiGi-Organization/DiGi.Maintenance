---
name: maintenance-ai-guidelines-propagation
description: "Use when adding, renaming or removing an AI Guideline, or when generated skills (.agents/skills) must be regenerated - the five sync points (guideline source file, $descriptions in UpdateAgents.ps1, .agents/AGENTS.md, the AI Guidelines README routing table, files/README - Coding Guidelines.md for always-applicable rules), skill-name derivation and description conventions (Use when <task> - concrete traps), the \\r\\r\\n pre-flight guard, the -NoCommit dry-run trap, and what UpdateAgents.ps1 rewrites or deletes per repository."
---

# AI Guidelines: Authoring & Propagating AI Guidelines (Skills)

The guideline markdowns in `DiGi.Maintenance/documentation/AI Guidelines/` are the **single source
of truth**. Every `.agents/skills/*/SKILL.md` in every `DiGi.*` repository is *generated* from them;
so is the machine-global `AGENTS.md` when `GLOBAL_AGENTS_FILE` is configured. Editing a generated
file is always wrong — it is deleted and regenerated on the next sync.

A new guideline is **not done** until all five sync points below are updated and the generation
script has been run once. Knowledge that stops at the source file never reaches another agent.

---

## 1. Author the Guideline (source)

1. **Location & name:** one file per topic in `documentation/AI Guidelines/`, named
   `Category - Topic.md`. The skill name is derived mechanically by `Scripts/UpdateAgents.ps1`:
   `Coding - WebAPI GLTF.md` → `coding-webapi-gltf` (lowercase, ` - ` and spaces → `-`).
   `README.md` in that folder is the index and never becomes a skill.
2. **Portability rule:** relative paths only — never `C:\Users\...` or any machine path. Paths that
   cross repositories are stated relative to the workspace root and say so.
3. **Line endings:** UTF-8 (no BOM), CRLF. A stray `\r\r\n` sequence **fails the whole sync**
   (`UpdateAgents.ps1` pre-flight guard); fix it byte-level before running anything.
4. **Content style:** rules with their *why* and the failure symptom, tables, detection recipes
   (`rg` patterns), one canonical example. The skill is loaded on demand — keep it dense and
   task-shaped; do not restate another guideline, link it by file name instead.
5. **What deserves a guideline:** a trap that fails silently, a workflow an agent must reproduce
   exactly, or a per-machine fact. Not a style preference already in `files/README - Coding
   Guidelines.md` and not a one-off finding.

## 2. The Four Hand-Synced Targets (scripts do NOT derive them)

| Target | What to update | Failure if skipped |
|--------|----------------|--------------------|
| `$descriptions` in `Scripts/UpdateAgents.ps1` | Add a key = the derived skill name; value = the `description:` frontmatter: start `Use when <task> -` and enumerate the specific traps. | The script only **warns** and ships the guideline everywhere with `Use for tasks related to <name>.` — an agent can never route to it. |
| `DiGi.Maintenance/.agents/AGENTS.md` | A bullet under the right `###` section: `**<skill-name:** Use when … — specifics.` | The routing index lies; agents never learn the skill exists. |
| `documentation/AI Guidelines/README.md` | A row in the matching Routing Table section (`Coding` / `XML Documentation` / `GitHub & Wiki` / `Maintenance`) with the trigger task. | The human index and next maintainer miss it. |
| `files/README - Coding Guidelines.md` | Only if the rule is *always applicable*: write it into the condensed block (it is a parallel document, NOT a concatenation) and into its §9 Full Guideline Set table. Its first line must stay the `## 💻 Coding Guidelines…` marker — `UpdateReadmes.ps1` hard-fails otherwise. | The README block and the guidelines silently diverge. |

Additionally re-sync `DiGi/CLAUDE.md` (the workspace-root Claude Code condensation) whenever it
disagrees with the guideline folder.

## 3. Description Quality = Skill Routing

The `description` string is the *only* thing an agent sees before loading the skill. Conventions
extracted from the existing registry:

- Open with `Use when <doing X>` — a task trigger, not a topic label.
- Then list the concrete traps/symptoms the skill covers (comma-separated fragments), so the
  description doubles as the routing table.
- Keep it one line. The script emits it as a **double-quoted YAML scalar** with `\` and `"` escaped,
  which is what makes `': '`, `' #'` and leading special characters safe — do not hand-edit
  generated frontmatter to "fix" this.

## 4. Regenerate (import) — Once, Deliberately

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -NoCommit
# or, when a commit in every repository is actually wanted:
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1"
```

1. Decide `-NoCommit` vs committing **before the run**: the dry-run trap applies — a `-NoCommit` run
   followed by a committing run commits nothing (everything is already up to date; the dirty trees
   just stay). Either run once with commits, or commit the generated `.agents` folders yourself per
   repository.
2. What the script does per `DiGi.*` repository: rewrites `.agents/AGENTS.md`, **deletes and
   re-creates `.agents/skills/`** (renamed or deleted guidelines leave no stale skills), writes each
   `SKILL.md` as UTF-8 no BOM + CRLF, then `git -c core.autocrlf=false add .agents` + commit unless
   `-NoCommit`. It never pushes.
3. It also refreshes `GLOBAL_AGENTS_FILE` (concatenation of all guidelines under a preserved header)
   when configured — see `Maintenance - Scripts.md` §2.
4. Run `UpdateReadmes.ps1` the same way only when `files/README - Coding Guidelines.md` changed.

## 5. Verify

1. In the source repository: `documentation/AI Guidelines/<File>.md` exists, the four hand-synced
   targets carry the new entry, and no `\r\r\n` remains (the script would have refused).
2. `.agents/skills/<skill-name>/SKILL.md` exists with correct `name:` and a non-generic
   `description:` — a `Use for tasks related to` description means the `$descriptions` key is
   missing or its spelling does not match the derived name.
3. If the run committed: `git -C <repo> status --porcelain .agents` is clean in every swept
   repository and no unrelated file was staged (the script stages narrowly by design).
