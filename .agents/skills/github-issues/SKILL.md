---
name: github-issues
description: "Use when creating, editing, commenting on, filtering or closing GitHub issues - --body-file encoding traps, mandatory labels and assignee ZiolkowskiJakub, verifying premises, resolution comments, FilterIssues.ps1, blocked_by dependencies."
---

# AI Guidelines: GitHub Issues & Comments

## Checklist
Read this first; open a section only when its line applies to the task.
- Bodies only through `--body-file` (UTF-8 without BOM, LF), never inline; new issue = Type + Priority + `ai:` labels and assignee `ZiolkowskiJakub` (§1).
- Never read a body into a PowerShell variable or pipeline — edit through a standalone `.py` script; recover a corrupted body from `userContentEdits` (§1).
- Verify the issue's premises against the code before implementing it; correct a wrong claim in a comment with the evidence; after a design change, comment on every open issue written against the old design (§2).
- Close with a resolution comment (commits, summary, facts, live verification); production runs are a follow-up issue with a `blocked_by` dependency (§3).
- List and read issues with `FilterIssues.ps1` (1–2 lines per issue) (§4).
- Blocking = a GitHub issue dependency, set when the blocker is filed and verified with the `blocking` GET; a blocked issue is not started; closing a blocker does not close dependents (§5).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
