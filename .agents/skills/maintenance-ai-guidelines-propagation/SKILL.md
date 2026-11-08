---
name: maintenance-ai-guidelines-propagation
description: "Use when adding, splitting, merging, renaming or removing an AI Guideline, or regenerating .agents/skills - one file per task trigger, stable section anchors cited from code, the five hand-synced targets ($descriptions, .agents/AGENTS.md, the AI Guidelines README, files/README - Coding Guidelines.md, DiGi/CLAUDE.md), description conventions, the \\r\\r\\n guard, what UpdateAgents.ps1 deletes and rewrites."
---

# AI Guidelines: Authoring & Propagating AI Guidelines (Skills)

`DiGi.Maintenance/documentation/AI Guidelines/` is the **single source of truth**. Every `.agents/skills/*/SKILL.md` in every
`DiGi.*` repository — and the machine-global `AGENTS.md` when `GLOBAL_AGENTS_FILE` is set — is generated from it; editing a
generated file is always wrong (it is deleted and regenerated). A new, renamed or removed guideline is **not done** until
the source and all five hand-synced targets (§2) are updated and the generator has run once.

## 1. Authoring
1. **One file per task trigger**, `Category - Topic.md` (or `Category.md`). A skill loads whole, so a file's size is paid
   on every task routed to it: split task-specific bulk out of a frequently loaded file, merge small files that are always
   loaded together. The skill name is derived by `UpdateAgents.ps1`: lower case, ` - ` and spaces → `-`
   (`Coding - WebAPI GLTF.md` → `coding-webapi-gltf`, `XML Documentation.md` → `xml-documentation`). `README.md` is the
   index and never a skill.
2. **Stable anchors:** code comments across the workspace cite guidelines as `File.md §n` (grep the workspace before
   renaming a file or renumbering a section). Moving a section leaves a one-line pointer under the old number.
3. Relative paths only — never `C:\Users\...`; cross-repository paths are workspace-relative and say so.
4. UTF-8 without BOM, stored LF, staged with a plain `git add` (`Maintenance - Scripts.md` §6). `UpdateAgents.ps1` writes
   CRLF itself; a stray `\r\r\n` in any source **fails the whole sync** (pre-flight guard) — fix it byte-level first.
5. **Content:** the rule, its *why*, the failure symptom, a detection recipe (`rg`/`grep`), one canonical example. Dense and
   task-shaped; **one canonical home per rule** — elsewhere a one-line pointer by file name and section, never a restatement.
6. **What deserves a guideline:** a trap that fails silently, a workflow an agent must reproduce exactly, a per-machine
   fact. Not a style preference already covered, not a one-off finding.

## 2. The five hand-synced targets (no script derives them)
| Target | Update | Failure if skipped |
|---|---|---|
| `$descriptions` in `Scripts/UpdateAgents.ps1` | Key = derived skill name (alphabetical); value = `Use when <task> - <key traps>`, one line, ≤ ~60 words | Only a **warning**; the skill ships everywhere as `Use for tasks related to <name>.` and is never routed to |
| `DiGi.Maintenance/.agents/AGENTS.md` | A bullet under the right `###`: `**<skill-name>:** Use when … — specifics.` | Agents never learn the skill exists |
| `documentation/AI Guidelines/README.md` | A row in the matching routing section | The human index misses it |
| `files/README - Coding Guidelines.md` | **Always** a row in the Full Guideline Set table; an always-applicable rule also into the condensed block (a parallel document, not a concatenation). Its first line stays the `## 💻 Coding Guidelines…` marker (`UpdateReadmes.ps1` hard-fails otherwise) | Every repository README omits it, and the two drift |
| `DiGi/CLAUDE.md` (workspace root, in no repository) | A routing-table row; re-sync any always-apply essential; fix paths on a move/rename | Claude Code routes to a missing file or never learns of it |

Also update references to a renamed **skill** in `DiGi/.opencode/agents/*.md` ("Load the <skill> skill").

**The description is all an agent sees before loading a skill:** open with `Use when <doing X>` (a task, not a topic),
then the concrete traps as comma-separated fragments, one line. The script emits a double-quoted YAML scalar (escaping `\`
and `"`), so `': '`, `' #'` and leading special characters are safe — never hand-edit generated frontmatter. Inside the
PowerShell string a literal `$` is `` `$ `` and a literal `"` is `""`.

## 3. Regenerate — once, deliberately
```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1"            # commits per repository
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateReadmes.ps1"           # only when the README block changed
```
Decide `-NoCommit` vs committing **before** the run — the dry-run trap (`Maintenance - Scripts.md` §3). Per `DiGi.*`
repository `UpdateAgents.ps1` rewrites `.agents/AGENTS.md`, **deletes every folder under `.agents/` other than `skills/`**,
deletes and re-creates `.agents/skills/` (renamed or removed guidelines leave no stale skills), writes each `SKILL.md` as
UTF-8 no BOM + CRLF, then `git -c core.autocrlf=false add .agents` and commits unless `-NoCommit`. It refreshes
`GLOBAL_AGENTS_FILE` when configured. Neither script pushes.

## 4. Verify
1. Source: the file exists, the five targets carry it, no `\r\r\n`, `git ls-files --eol` unchanged (`i/lf`).
2. `.agents/skills/<skill-name>/SKILL.md` has the right `name:` and a non-generic `description:` (`Use for tasks related
   to` = missing or misspelled `$descriptions` key).
3. After a committing run: `git -C <repo> status --porcelain .agents` clean in every repository, nothing unrelated staged.
