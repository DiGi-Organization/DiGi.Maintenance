# AI Guidelines: Branch Synchronization & Versioning

Merge release branches into `main` and bump patch versions across DiGi repositories.
**The workflow runs only on explicit user instruction — it is never a default consequence of any other task** (§1.1).

---

## 1. Trigger Conditions (All Mandatory)

1. **Explicit User Instruction:** the user MUST have clearly asked for this workflow — a version bump, a release, or a branch sync (e.g. "bump the version", "cut 0.8.11", "sync the branches"). It is **not** triggered by completing an implementation, closing an issue, or a general "proceed" / "commit and push" instruction. "Commit and push the changes" commits the work to the branch it is on; it does not authorize a merge into `main`, a version bump, or a new version branch. When the work is done but the user has not asked for a bump, commit to the active version branch and note that the bump is available on request. Which branch to commit to, and why no feature branch is created, is `GitHub - Working Branch.md`. *(Learned 2026-09-28: closing DiGi.GIS.WebAPI.UI#62 bumped to `0.8.11` and pushed both branches without such a request.)*
2. **Bare SemVer Branch:** Active branch MUST strictly match `*.*.*` (e.g., `0.8.2`, `1.12.0`). Skip branches containing text, prefixes, or suffixes (`main`, `v0.8.2`, `feature/*`, `0.8.2-beta`).
3. **Differs from Main:** Run ONLY if active version branch has unmerged commits relative to `main`. Skip identical repos.

---

## 2. Synchronization & Release Pipeline

Execute sequentially per qualifying repository:

1. **Merge into Main:** Merge the active version branch into `main` to align codebases.
2. **Bump Patch Version:** Increment the 3rd SemVer digit by 1 (e.g., `0.8.2` → `0.8.3`).
3. **Branch Creation:** Create a new branch off `main` named after the bumped version (`0.8.3`).
4. **Update Project Metadata:** If `Directory.Build.props` exists, update `<Major>`, `<Minor>`, and `<Build>` properties to match the new version and commit changes on the new branch.
5. **Push Remote Tracking:** Push both `main` and the new version branch to `origin`:
   ```bash
   git push origin main
   git push -u origin <new_version_branch>
   ```

The pushes in step 5 are part of this workflow and carry the same trigger as everything else in §2: without the explicit instruction of §1.1, no step runs.
