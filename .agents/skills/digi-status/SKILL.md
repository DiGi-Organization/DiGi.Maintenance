---
name: digi-status
description: "Use before the first edit, a commit, a pull or any cross-repository sweep in the DiGi workspace - one script reports branch, expected version branch, uncommitted files and ahead/behind for all repositories."
---

# Workspace status in one call

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/StatusAllRepos.ps1"
```
Prints one line per repository that needs attention (`-Repo "<Repo>" -All` for one repository, `-Json` for a compact
array); a repository that is clean, in sync and on its expected branch is not listed. It does not fetch.

Read the line, then act by `GitHub - Branches and Commits.md` (Checklist):
- `(expected X)` - the repository is not on its active version branch: switch to it or ask; never branch around it.
- `dirty=N` that is not yours - leave it, stage only your own paths, say so.
- `behind=N` - `git pull --ff-only` before editing or rebuilding.
- `ahead=N` - unpushed commits; push only when asked.

Commit on the active version branch, explicit paths only, never a new branch, worktree or PR unless asked; a
version bump or release only on an explicit request.
