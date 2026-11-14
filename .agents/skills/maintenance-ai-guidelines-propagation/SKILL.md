---
name: maintenance-ai-guidelines-propagation
description: "Use when adding, splitting, renaming or removing an AI Guideline or regenerating .agents/skills - the Guidelines.json manifest, checklist-first layout with Evidence files, stable section anchors, UpdateAgents.ps1."
---

# AI Guidelines: Authoring & Propagating AI Guidelines (Skills)

`DiGi.Maintenance/documentation/AI Guidelines/` is the **single source of truth**. Every `.agents/skills/*/SKILL.md` in every
`DiGi.*` repository — and the machine-global `AGENTS.md` when `GLOBAL_AGENTS_FILE` is set — is generated from it; editing a
generated file is always wrong (it is deleted and regenerated). A new, renamed or removed guideline is **not done** until
the source, its `Guidelines.json` entry and the hand-written targets (§2) are updated and the generator has run once.
History of the five hand-synced targets this replaced: [Evidence](evidence.md).

## 1. Authoring
1. **One file per task trigger**, `Category - Topic.md` (or `Category.md`). Split task-specific bulk out of a frequently
   loaded file, merge small files that are always loaded together. The skill name is derived by `UpdateAgents.ps1`: lower
   case, ` - ` and spaces → `-` (`Coding - WebAPI GLTF.md` → `coding-webapi-gltf`, `XML Documentation.md` →
   `xml-documentation`). `README.md` is the index and never a skill.
2. **Stable anchors:** code comments across the workspace cite guidelines as `File.md §n` (grep the workspace before
   renaming a file or renumbering a section). Moving a section leaves a one-line pointer under the old number.
3. Relative paths only — never `C:\Users\...`; cross-repository paths are workspace-relative and say so.
4. UTF-8 without BOM, stored LF, staged with a plain `git add` (`Maintenance - Scripts.md` §6). `UpdateAgents.ps1` writes
   CRLF itself; a stray `\r\r\n` in any source **fails the whole sync** (pre-flight guard) — fix it byte-level first.
5. **Content:** the rule, its *why*, the failure symptom, a detection recipe (`rg`/`grep`), one canonical example. Dense and
   task-shaped; **one canonical home per rule** — elsewhere a one-line pointer by file name and section, never a restatement.
6. **What deserves a guideline:** a trap that fails silently, a workflow an agent must reproduce exactly, a per-machine
   fact. Not a style preference already covered, not a one-off finding.
7. **Checklist first (files above ~8 KB).** The first heading is `## Checklist`: one line per actionable rule, each naming
   its section (`(§3)`), so an agent reads ~1 KB and opens only the section its change touches. The numbered sections
   follow unchanged. The generator ships such a guideline as a small `SKILL.md` (introduction + checklist) plus the
   whole text as `guideline.md` beside it — a skill body loads whole, the sections on demand. A file without
   `## Checklist` ships whole; do not add one to a small file (it only adds bytes).
8. **Incidents and measurements go to `Evidence/<same name>.md`** when they are paragraph-sized: keyed by the section
   number, linked once from the guideline's introduction, read only when a rule is disputed or changed. The rule keeps
   a one-clause why and its symptom. The generator copies it beside the skill as `evidence.md`.
9. **Prove an edit lost nothing:** `CheckGuidelineLossless.ps1 -BaseRef HEAD -Name "<File>.md"` — every code line,
   backticked span, issue reference, date, number and numbered section of the base version must still exist in the
   guideline, its evidence file, or (reported as *moved*) another guideline. A fact that is deliberately retired moves
   to the evidence file with a note, it is not deleted.

## 2. The manifest and the hand-written targets
`documentation/AI Guidelines/Guidelines.json` lists every guideline once, in routing order:

| Field | Becomes |
|---|---|
| `file` | the guideline file name; the skill name is derived from it |
| `category` | the heading it is listed under (one of `categories`) |
| `description` | the `SKILL.md` frontmatter, the `.agents/AGENTS.md` bullet and the `README.md` index cell — `Use when <task> - <key traps>`, one line, ≤ ~35 words |
| `route` (+ optional `routeNote`) | the task cell of the `DiGi/CLAUDE.md` routing table (and a suffix after the file name) |

`UpdateAgents.ps1` rewrites the blocks between `<!-- guidelines:begin -->` and `<!-- guidelines:end -->` in
`documentation/AI Guidelines/README.md`, `DiGi.Maintenance/.agents/AGENTS.md` and `DiGi/CLAUDE.md` (workspace root, in no
repository) — never edit inside them. It **fails before writing anything** when a guideline file has no entry, an entry
has no file, a description does not start with `Use`, or `files/README - Coding Guidelines.md` does not name a file.

Still hand-written:
| Target | Update | Failure if skipped |
|---|---|---|
| `files/README - Coding Guidelines.md` | **Always** a row in the Full Guideline Set table; an always-applicable rule also into the condensed block (a parallel document, not a concatenation). Its first line stays the `## 💻 Coding Guidelines…` marker (`UpdateReadmes.ps1` hard-fails otherwise) | The generator fails (file not named); the condensed block drifts silently |
| `DiGi/CLAUDE.md` outside the routing table | Re-sync any always-apply essential | Claude Code misses an always-apply rule |
| `DiGi.Maintenance/.agents/AGENTS.md` above the skill list | Priorities and always-apply lines | Other agents miss them |

Also update references to a renamed **skill** in `DiGi/.opencode/agents/*.md` ("Load the <skill> skill").

**The description is all an agent sees before loading a skill:** open with `Use when <doing X>` (a task, not a topic),
then the concrete traps as comma-separated fragments, one line. Every description is loaded by every session of a
skill-aware agent, so each word is paid thousands of times — `MeasureAgentContext.ps1` shows the total. The script
emits a double-quoted YAML scalar (escaping `\` and `"`), so `': '`, `' #'` and leading special characters are safe —
never hand-edit generated frontmatter. In the JSON a literal `"` is `\"` and a literal `\` is `\\`.

**Workflow skills** (`DiGi.Maintenance/files/skills/<name>/SKILL.md`, hand-written, ≤ ~40 lines) call the maintenance
scripts and point at guideline checklists instead of restating rules. The generator copies them into every
`.agents/skills` and into `DiGi/.claude/skills` (Claude Code); a name colliding with a guideline skill fails the run.

## 3. Regenerate — once, deliberately
```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -Repo "DiGi.Maintenance" -NoCommit   # generated blocks + one repository, to review
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1"            # commits per repository
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateReadmes.ps1"           # only when the README block changed
```
Decide `-NoCommit` vs committing **before** the run — the dry-run trap (`Maintenance - Scripts.md` §3). Per `DiGi.*`
repository (and `templates/DiGi.Template`) `UpdateAgents.ps1` rewrites `.agents/AGENTS.md`, **deletes every folder under
`.agents/` other than `skills/`**, deletes and re-creates `.agents/skills/` (renamed or removed guidelines leave no stale
skills), writes each `SKILL.md` (and `guideline.md`, `evidence.md`) as UTF-8 no BOM + CRLF, then
`git -c core.autocrlf=false add .agents` and commits unless `-NoCommit`. It refreshes `GLOBAL_AGENTS_FILE` when
configured. Neither script pushes. The generated blocks of the three source files are committed by hand.

## 4. Verify
1. Source: the file exists, `Guidelines.json` and `files/README - Coding Guidelines.md` carry it, no `\r\r\n`,
   `git ls-files --eol` unchanged (`i/lf`), `CheckGuidelineLossless.ps1` green.
2. `.agents/skills/<skill-name>/SKILL.md` has the right `name:` and `description:`; a checklist guideline has
   `guideline.md` beside it.
3. After a committing run: `git -C <repo> status --porcelain .agents` clean in every repository, nothing unrelated staged.
4. `MeasureAgentContext.ps1`: the always-loaded totals did not grow without a reason.
