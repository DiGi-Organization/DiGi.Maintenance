# AI Guidelines: Working Branch

Where an AI agent commits its work: the branch the repository is on, not a new one.
**This is the default for every task. Only an explicit user instruction changes it** (§4).

---

## 1. Default

1. **Work on the current branch.** The current branch is the active version branch (a bare SemVer branch such as `0.8.0`, see `GitHub - Branch Pull.md` §2) - the highest one the repository has. Commit there.
2. **Do not create** a feature/issue branch, a git worktree or a pull request. An issue number in the task (`#132`) is not a reason to branch.
3. **`main` is not the working branch.** It is only the target of the release workflow (`GitHub - Branch Synchronization.md`) and may lag a long way behind the version branch. Never open a PR against it, and never base work on it, unless asked.

---

## 2. Before the first edit

1. `git branch --show-current`. A shared checkout can be switched by another session or by the user, so check it at the start of every task, not once per conversation.
2. If it is not the active version branch (a merged feature branch, a branch left by another session): **switch to the version branch** after `git fetch`, or ask. Do not create a branch to get around it.
3. If the branch is behind its remote, `git pull --ff-only` before editing - the checkout, the commits and any build deployed from the checkout must agree.
4. Uncommitted changes that are not yours (generated documentation, another session's work): leave them alone, stage only your own files, and say so.

---

## 3. Commit, push, merge

1. **Commit** on the working branch as the work completes. The commit message states the issue number.
2. **Push** only when the user asks ("commit and push"). The push goes to the same branch.
3. **Pull request** only when the user asks for one; it then targets the active version branch. Merging is done only when the user asks.
4. After the user merges or deploys something, `git pull --ff-only` the checkout **before** any rebuild: a build from a checkout that never pulled the merge ships the old code. *(Learned 2026-10-23, bodyplan #126/#135: two feature branches, a worktree and two PRs were opened although the preference was already known; the redeployed `bodyplan.WebAPI.dll` was built from a checkout one merge behind and silently lacked the new endpoint.)*

---

## 4. When the user says otherwise

An explicit instruction wins: "create a branch for this", "open a PR", "work in a worktree", "bump the version". Follow it for that task only; the default returns for the next one. A general "proceed" or "implement the issue" is **not** such an instruction.

The release workflow in `GitHub - Branch Synchronization.md` creates a new version branch; it runs only on the explicit request described there and is the one place a new branch is part of the job.
