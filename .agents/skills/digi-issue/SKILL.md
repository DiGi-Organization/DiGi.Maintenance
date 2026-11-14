---
name: digi-issue
description: "Use when listing, reading, creating or closing DiGi GitHub issues - FilterIssues.ps1 invocations for compact listings and the mandatory checks, instead of raw gh output."
---

# Issues with compact output

From `DiGi.Maintenance/Scripts`:
```powershell
# List: two lines per issue (label shorthands: standard, high, bug ...)
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "<Repo>" -Labels "ai: standard, priority: high"
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Labels "high" -Search "<keyword>"
# One issue: -Detail = 10-line preview, -Full = whole body (only when you will work on it)
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "<Repo>" -Issue <n> -Detail
```
`-Json` prints one compressed line. Prefer the listing, then `-Detail`, then `-Full` - in that order.

Before acting, read the Checklist of `GitHub - Issues.md` (and `GitHub - Labels.md` for the tier). The checks that
are never skipped:
- **Verify the issue's premises** against the code before implementing it.
- **Blocked?** A blocked issue is not started - verify with the `blocking` GET, not the body text.
- **New issue:** Type + Priority + one `ai:` label, assignee `ZiolkowskiJakub`, body through `--body-file`
  (UTF-8, LF).
- **Closing:** a resolution comment; a production run still owed becomes a follow-up issue. Closing an issue is
  not a request to bump a version.
