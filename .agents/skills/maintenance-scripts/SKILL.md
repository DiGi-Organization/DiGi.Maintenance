---
name: maintenance-scripts
description: "Use when running or writing DiGi.Maintenance scripts or making scripted edits - context scripts first, conf keys, *AllRepos sweeps and the -NoCommit trap, BuildAll order, deploy, editing bytes not lines, line endings."
---

# AI Guidelines: Maintenance Scripts, Workspace Operations & Scripted Edits

Scope: `DiGi.Maintenance/Scripts/*.ps1` and the build/deploy flow they drive, plus any scripted or bulk file edit.
`Scripts/README.md` is the command catalog (exact invocations); this file holds conventions and traps.

## Checklist
Read this first; open a section only when its line applies to the task.
- **Context scripts first** — before reading files or logs, run the script that answers the question in a few lines: `StatusAllRepos`, `GetApi`, `TestSummary`, `BuildAll -Summary`, `CheckGuidelineRules`, `FilterIssues`, `MeasureAgentContext` (§7).
- Run from `Scripts` with `-NoProfile -ExecutionPolicy Bypass -File`, host shell, absolute output paths; read a script before trusting its exit code (§1).
- Machine settings come from `user files/*.conf` keys; never print a conf, never hard-code a path (§2).
- Cross-repository sweeps commit per repository; decide `-NoCommit` before the run — a dry run followed by a committing run commits nothing (§3).
- `BuildAll.ps1` builds its hard-coded order, never `--no-incremental` across it; `Deploy.ps1`/`SyncDirectory.ps1` semantics (§4).
- A new script: comment-based help, `param()`, `$ErrorActionPreference = "Stop"`, exit 0/1/2, idempotent, documented in `Scripts/README.md` (§5).
- Scripted edits: edit bytes and assert the match count, never `sed -i`; the `git add` flag decides the stored line ending; check `git diff --stat` for deletions you did not make (§6).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
