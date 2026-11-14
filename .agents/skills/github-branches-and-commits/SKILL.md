---
name: github-branches-and-commits
description: "Use before the first edit and before every commit - commit on the active version branch (no branch, worktree or PR unless asked), pre-commit sweep, push only when asked, plan files, release bump only on explicit request."
---

# AI Guidelines: Branches and Commits

**Default for every task: commit on the current active version branch — no feature branch, worktree or pull request
unless the user explicitly asks for that task.** A *version branch* is a bare SemVer name (`0.8.5`, `1.12.0`) — not
`main`, `v0.8.5`, `feature/*` or `0.8.5-beta`; the *active* one is the numerically highest. (DiGi.Maintenance itself has
no version branch and works on `main`.)

## 1. Where to commit
1. Commit on the active version branch. An issue number in the task (`#132`) is no reason to branch.
2. `main` is not a working branch: it is only the release target (§4), may lag far behind, and is never a PR target or a
   base for work unless asked.
3. An explicit instruction ("create a branch", "open a PR", "work in a worktree", "bump the version") wins **for that task
   only**; a general "proceed" or "implement the issue" is not one.

## 2. Before the first edit, and around builds
1. `git branch --show-current` at the start of **every** task — another session or the user may have switched it. On the
   wrong branch: `git fetch` and switch to the version branch, or ask; never branch around it.
2. Behind the remote: `git pull --ff-only` before editing.
3. Uncommitted changes that are not yours (generated docs, another session's work): leave them, stage only your files, say
   so.
4. After the user merges or deploys, `git pull --ff-only` **before any rebuild** — bodyplan #126/#135 redeployed a
   `bodyplan.WebAPI.dll` built one merge behind, silently missing the new endpoint (after two branches, a worktree and two
   PRs were opened against the known preference).

## 3. Committing
1. **Pre-commit sweep (mandatory):** `git status --porcelain` and `git diff --name-only --cached`. Exclude and delete every
   plan, draft or scratch `*.md` (`plan.md`, `TODO-*.md`, `temp_body.md`, analysis dumps); legitimate documentation
   (`README.md`, `documentation/**`, wiki sources) stays. Unsure? "Permanent project artifact, or working paper of this
   session?"
2. Stage explicit paths — never a blind `git add .`/`-A`. Check `git diff --stat` for unexpected deletions
   (`Maintenance - Scripts.md` §6).
3. The message states the issue number. **Push only when asked** ("commit and push"), to the same branch. A PR only when
   asked, targeting the active version branch; merge only when asked.
4. A plan already tracked by an earlier session is `git rm`-ed in the commit that makes it stale. A `.gitignore` entry for
   scratch names hides the mistake; the rule is delete.

## 4. Release — version bump & branch synchronization (explicit request only)
**Runs only when the user explicitly asks for a bump, a release or a branch sync** ("bump the version", "cut 0.8.11").
Completing or closing an issue, "proceed" or "commit and push" never triggers it: commit to the version branch and note
that the bump is available on request (2026-09-28: closing DiGi.GIS.WebAPI.UI#62 bumped to `0.8.11` and pushed both
branches unasked). Per repository whose active branch is a bare SemVer branch **with commits not in `main`**:
1. Merge the version branch into `main`.
2. Bump the patch (`0.8.2` → `0.8.3`) and create that branch off `main`.
3. If `Directory.Build.props` exists, set `<Major>`/`<Minor>`/`<Build>` to match and commit on the new branch.
4. `git push origin main` and `git push -u origin <new_version_branch>`.

## 5. Pulling every repository to its active version branch
Per `DiGi.*` repository under the workspace root: `git fetch --all --prune`, `git checkout <highest SemVer branch>`,
`git pull origin <that branch>`. Prefer the script (resolves the root from its own location):
```powershell
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/PullBranchesAllRepos.ps1"
```
A sweep takes minutes — give the shell call **≥ 180 s** (`timeout: 180000`), or it aborts partway and silently leaves the
later repositories (`DiGi.SAM`…) un-pulled. It checks out branches across dozens of repositories: run only when asked.
Plain pull of each current branch, from the workspace root (depth-limited so nested `.git` folders are skipped):
```bash
find . -mindepth 2 -maxdepth 2 -name ".git" -type d -exec sh -c 'cd "{}"/.. && pwd && git pull' \;
```

## 6. Plan files
Plans are session working papers: they live in the local plans folder outside every working tree (named in the
machine-level `AGENTS.md`), never in a repository, and scratch `--body-file` bodies go to the scratch folder.
- **Delete the plan when its issue closes**, in the same session (a sub-issue's plan with that sub-issue, the tracking
  issue's with the parent), and say so in one line of the summary. The closed issue, its resolution comment and the
  commits are the record; promote any decision worth keeping to the issue, wiki or `documentation/` first.
- An open issue keeps its plan in the plans folder so the next session can resume.
- Exception — the user asks to commit a plan: name it like documentation, put it under `documentation/`, link it from the
  README or wiki. When in doubt ask "keep this plan, or delete it now that the issue is closed?".
