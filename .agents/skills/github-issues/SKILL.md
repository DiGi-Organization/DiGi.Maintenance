---
name: github-issues
description: "Use when creating, editing, commenting on, filtering or closing GitHub issues - --body-file with UTF-8 LF bodies, the \\r\\r\\n table trap and PowerShell decoding corruption (edit through a Python script), GraphQL revision recovery, mandatory labels and default assignee ZiolkowskiJakub, verifying an issue's premises before implementing it, resolution comments with production runs as follow-up issues, FilterIssues.ps1, blocked_by dependencies."
---

# AI Guidelines: GitHub Issues & Comments

## 1. Writing bodies through `gh` — files only, UTF-8, LF
**Never pass markdown inline** (`--body "..."`): in PowerShell the backtick is the escape character (`` `a `` in
`` `api.digiproject.uk` `` becomes a bell, `` `n `` a newline), `$` expands and quotes break. Write the body to a scratch
`.md` file (UTF-8 **without BOM**, LF) and pass `--body-file <path>` / `-F "body=@<path>"`; delete it afterwards
(`GitHub - Branches and Commits.md` §6).
```bash
# New issue: mandatory type + priority + ai labels (GitHub - Labels.md) and default assignee ZiolkowskiJakub (unless the user names another)
gh issue create --repo <owner>/<repo> --title "<Title>" --body-file <path> --label "type: <type>,priority: <priority>,ai: <tier>" --assignee ZiolkowskiJakub
gh issue edit <number> --repo <owner>/<repo> --add-assignee ZiolkowskiJakub     # if created without one (gh api, scripts)
gh issue comment <number> --repo <owner>/<repo> --body-file <path>
gh issue close <number> --repo <owner>/<repo>                                   # after the resolution comment (§3)
gh api -X PATCH repos/<owner>/<repo>/issues/comments/<comment_id> -F "body=@<path>"
```
Sub-issues/sub-tasks for a feature: the tracking-issue pattern (`GitHub - Sub-Issues.md`), never a flat pile.

**The `\r\r\n` trap:** Windows text mode turns `\n` into `\r\n`, so text already holding `\r\n` is written as `\r\r\n`,
which GitHub reads as a blank line — and a blank line inside a table breaks it into raw pipes. Write explicitly:
```python
with open(path, 'w', newline='\n', encoding='utf-8') as f:
    f.write(markdown_content)
```
```powershell
[System.IO.File]::WriteAllText($path, ($content -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
```
Table rows (header, separator, data) stay contiguous; UTF-8 without BOM keeps `—`, `–`, `§`, `→`, `·` intact.

**Reading an existing body corrupts it in PowerShell.** Native output (`gh issue view --json body`, `gh api`) is decoded
with `[Console]::OutputEncoding` (an OEM/ANSI code page), so every multi-byte character becomes `�` or mojibake
(`ÔÇö`) the moment it enters a variable or pipeline — and saving it writes the damage permanently. `python -c "..."` inside
PowerShell is mangled the same way. Edit through a standalone `.py` script:
```python
import json, subprocess

res = subprocess.run(["gh", "api", "repos/<owner>/<repo>/issues/<number>"], capture_output=True, text=True, encoding="utf-8")
body = json.loads(res.stdout)["body"]

target = "- [ ] **S8 · Add a `building_data` write endpoint"
assert target in body, "Target text not found"
body = body.replace(target, target.replace("- [ ]", "- [x]", 1))

assert "�" not in body and "ÔÇ" not in body and "â" not in body, "Encoding corruption"   # also check tables stay contiguous
with open("temp_body.md", "w", newline="\n", encoding="utf-8") as f:
    f.write(body)
subprocess.run(["gh", "issue", "edit", "<number>", "--repo", "<owner>/<repo>", "--body-file", "temp_body.md"], check=True)
```
**Recovery:** never reconstruct a corrupted body by hand — GitHub keeps every revision; take the pristine text from
`userContentEdits` and re-apply the change as above:
```graphql
query { repository(owner: "<owner>", name: "<repo>") { issue(number: <number>) { userContentEdits(first: 5) { nodes { editedAt diff } } } } }
```

## 2. Verify an issue's premises before implementing it
The problem statement is a hypothesis — including one you wrote. An issue wrong about the cause is usually wrong about the
fix.
- **Does the "missing" optimization already exist?** Open the file it names. DiGi.Geometry#2 asked for spatial
  partitioning against 15–60 s; `Difference.cs` already held an `STRtree`, the `< 3.0 s` criterion was met at ~1.3 s, and
  the real defect was a crash on dense input — as written it would have added a second index and two packages.
- **Does a feature "already working" produce output?** Wired flags are not a rendered result: DiGi.GIS.WebAPI.UI#43 said
  shade was "emitted and received" while no shadow had ever reached the screen. Verify the observable effect
  (`Coding - Browser Testing.md` §5).
- **Is a quoted latency reproducible?** Run the repository's benchmark fact in isolation (`Coding - Performance.md` §2).
- **Does the failure reproduce?** Write the reproducing fact first (`Coding - Automatic Tests.md` §4).
- **Is a compile-time claim true?** Probe it with a scratch console app (`Coding - General.md` §1.17; in `DiGi.Core#5` the
  summary and review each "corrected" the issue wrongly).
- **Does one rule fit every consumer named?** Look at the shape of what each writes: DiGi.GIS.PostgreSQL#77 proposed one
  rule for three consumers of nested subdivisions — the report could count a building under every container, the
  one-row-per-building tables needed exactly one (decided on write), the municipality aggregate its own polygon.

A wrong claim is corrected **in a comment with the evidence** (a closed issue keeps teaching what it last said).
**After a design change, sweep the open issues written against the old design:** when a public type is removed or
re-parented, a `_type` renamed or a member moved (`TypologyAppearanceCollection.Key` → `Query.Key`), search each consuming
repository (`gh issue list --search "<TypeName>"`, `FilterIssues.ps1`) and post **one comment per affected issue** — a
shared before/after table plus the effect on its premises, approach and acceptance — without editing the body (the
2026-09-11 `DiGi.Typology.Visual` redesign invalidated DiGi.Typology #20, #21 and DiGi.GIS.WebAPI.UI #16, #17, #19).

## 3. Resolution comment, then close
Cover: (1) commit SHA(s), version branch, repository; (2) technical summary and modified/added files; (3) facts added and
commands run; (4) live verification against deployed services, or "Live verification: not run — see #N".

**Production runs are a follow-up issue, not part of the code issue's plan.** Everything that happens on a server later —
deploying, tray-task runs, re-deriving data, before/after tallies, guideline/README propagation — is filed as its own issue
(mandatory labels and assignee) with a `blocked_by` dependency on the code issue (§5); the plan ends with "Out of scope —
tracked in #N" and the code issue closes on its own (`DiGi.GIS.PostgreSQL#77` → `#78`). Delete the implementation plan
on closure (`GitHub - Branches and Commits.md` §6).

## 4. Searching (`FilterIssues.ps1`) — 1–2 lines per issue instead of raw JSON
```powershell
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/FilterIssues.ps1" -Repo "DiGi.Core" -Labels "ai: standard, priority: high"
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/FilterIssues.ps1" -Labels "standard, high"          # all repositories
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Search "subdivision"
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Issue 42 -Detail
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/FilterIssues.ps1" -Labels "critical" -Json
```
Shorthands: `high` → `priority: high`, `standard` → `ai: standard`, `bug` → `type: bug`, `in-progress`/`parked` →
`status: …`. It does not show dependencies yet (§5).

## 5. Blocking relationships — GitHub issue dependencies (mandatory)
When an issue cannot complete until another lands, record a **dependency** ("blocked by"/"blocking"), not only prose. It
works across repositories; prose references (`owner/repo#N`) keep the *why*. Set it when:
- several issues share one root cause or missing capability — file the blocker in the lowest repository of the chain and
  block every dependent (`DiGi.Analytical#3` blocks `DiGi.GLTF#1` and `DiGi.GIS.PostgreSQL#84`);
- a sub-issue waits for a sibling (`GitHub - Sub-Issues.md` §6);
- a production-run issue follows a code issue (§3);
- an issue waits on an upstream fix (also the `TODO [Marker]` removal condition).
```bash
gh api repos/<owner>/<repo>/issues/<blocker_number> --jq .id                                                         # node id, not the number
gh api -X POST repos/<owner>/<dependent_repo>/issues/<dependent_number>/dependencies/blocked_by -F issue_id=<blocker_id>   # 201
gh api repos/<owner>/<repo>/issues/<number>/dependencies/blocked_by --jq '.[] | "\(.repository.full_name)#\(.number) \(.state)"'
gh api repos/<owner>/<repo>/issues/<number>/dependencies/blocking  --jq '.[] | "\(.repository.full_name)#\(.number) \(.state)"'
gh api -X DELETE repos/<owner>/<dependent_repo>/issues/<dependent_number>/dependencies/blocked_by/<blocker_id>
```
`-F` sends the id as a number (`-f` sends a string, rejected); an empty `[]` from the GET proves the API is available.
1. **Set it when the blocker is filed** (same session, right after `gh issue create`) and post one linking comment per
   dependent: the shared root and how its own scope narrows — never edit the dependent bodies.
2. **Verify with the `blocking` GET** on the blocker; never report the link from the POST alone.
3. **A blocked issue is not started** until its blockers close — read `blocked_by` first. A workaround shipped meanwhile is
   `TODO [Marker]` code whose removal condition is the blocker's closure (`gltf-viewer-core.js` for `DiGi.GLTF#1`).
4. **Closing a blocker does not close dependents** — resume or comment each `blocking` entry. Closing a dependent while a
   blocker is open needs a comment and the dependency `DELETE`d.
5. Parent ↔ child is the Sub-issues table; dependencies order issues that are not parent and child.
