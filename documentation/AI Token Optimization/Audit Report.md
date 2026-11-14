# AI Token Optimization — Audit Report

Audit of 2026-11-14: what an AI agent pays, in context, to work in the DiGi workspace, and what was changed. Sizes are
bytes; tokens ≈ bytes / 4. Re-measure at any time with `Scripts/MeasureAgentContext.ps1`. Paths are relative to the
workspace root unless they start with `Scripts/` or `documentation/` (then relative to `DiGi.Maintenance`).

## 1. Where the tokens went

| # | Cost | Size before | Paid |
|---|---|---|---|
| 1 | `CLAUDE.md` (workspace root) | 15 272 | every Claude Code session |
| 2 | OpenCode instructions: `CLAUDE.md` + `DiGi.Maintenance/.agents/AGENTS.md` + 31 skill descriptions | 35 583 | every OpenCode session — the skill list was loaded three times (routing table, `AGENTS.md` bullets, skill frontmatter) |
| 3 | Generic `.agents` consumers: `AGENTS.md` + 31 skill descriptions | 20 311 | every session |
| 4 | A guideline read for a task: 31 files, 273 736 in total, the eight largest 10 792–24 221 | whole file | per task; a skill body loads whole, and no file had a summary to read first |
| 5 | Workspace-wide search | 75 hits for one guideline phrase | every search — each repository carries a generated copy (292 KB × 72) |
| 6 | Public API lookup | a namespace page of `documentation/API`, up to 915 KB (`DiGi.Core.Classes.md`) | per lookup, or the `.cs` file instead |
| 7 | Build and test logs | MSBuild minimal log × ~75 solutions; raw `dotnet test` output | per verification |
| 8 | Git state across repositories | `git status` × 72 | before a commit, pull or sweep |
| 9 | Rules without a mechanical check | re-reading changed files against the guidelines | per change |
| 10 | Maintaining the guideline set | five hand-synced lists of the 31 guidelines | per guideline change, five edits and their drift |

Findings that are not costs but were surfaced by the audit:
- The guidelines are already dense. Dated incident narrative is real but interleaved clause by clause; moving it out of
  `Coding - General.md` freed only 1.6 KB of 24 KB. **The lever is reading less of a file, not making the file smaller.**
- `DIGI0001` (`DiGi.Maintenance.Analyzers`) is referenced by no repository — the `<= 7` parameters rule is not enforced
  by any build.
- `XML Documentation.md` §2 promised "no CS1591" while the template `.editorconfig` switches CS1591 off — corrected in
  the guideline (the missing-comment check is the author's).
- Rules already enforced by the build (`var`, block-scoped namespaces, `new()`, `[]`, `CA1068`) need no LLM attention
  beyond one line.

## 2. What changed, measured

| Target | Before | After | Note |
|---|---|---|---|
| OpenCode always-loaded | 35 583 | 25 207 (−29 %) | one instruction file; descriptions 14 284 → 8 725 incl. 5 workflow skills |
| Generic always-loaded | 20 311 | 17 933 (−12 %) | shorter descriptions; `AGENTS.md` gained the script and reading-protocol lines |
| Claude Code always-loaded | 15 272 | 17 567 (+15 %) | reading protocol, script list and 5 skill descriptions added; **the slimmed `CLAUDE.md` (12 318 → about 13 400 with skills, −12 %) is proposed, not applied** — §4 |
| First read of a large guideline (17 files) | 210 876 whole | 34 139 checklists (−84 %) | a section is read on demand; the files themselves grew 8 % (273 736 → 296 512) |
| Search hits for a guideline phrase | 75 | 4 | workspace-root `.ignore` |
| Lists of guidelines kept by hand | 5 | 1 manifest + 1 coverage-checked README block | `Guidelines.json` |
| API lookup | up to 915 KB page | a few lines | `GetApi.ps1` |
| Build / test verification | raw logs | failures and diagnostics only | `BuildAll.ps1 -Summary`, `TestSummary.ps1` |

The "first read" row is the dominant per-task saving: a task routed to `Coding - General.md` now loads 3.4 KB instead of
24.2 KB unless it needs a section.

## 3. Losslessness
- No rule was removed or reworded away. `Scripts/CheckGuidelineLossless.ps1 -BaseRef c9482d6` compares every guideline
  with the pre-change commit: every line of a code block, every backticked span, issue reference, date, number and
  numbered section of the old text exists in the new guideline or its `Evidence/` file — **0 lost**. Four backticked
  words of the old hand-written index (`README.md`, now generated from the manifest) are reported as *moved*: they
  exist only in the guidelines the index points to.
- Section numbers are unchanged (`File.md §n` citations in code still resolve); the six end-of-file checklists moved to
  the top leave a pointer under their old number.
- Checklist lines state the rule itself, so an agent that reads only the checklist still has every rule; the section
  adds the why, the symptom, the code and the detection recipe.

## 4. Open decisions
1. **Slim `CLAUDE.md`** — a proposal is at `user files/reports/CLAUDE.proposed.md` (12.3 KB against 16.5 KB now; the
   pre-change file is saved beside it). It keeps every always-apply C# rule and every silent trap as one line with its
   guideline, and drops the paragraphs that restate a routed guideline (serialization, tests, browser testing, XML
   documentation). The 9 KB target of the plan is not reachable without cutting routing trigger words — the generated
   routing table alone is 5.6 KB. It changes what every session knows unprompted, so it is yours to approve.
2. **Regenerate the 72 repositories** (`UpdateAgents.ps1`, one commit per repository, no push). Until then only
   `DiGi.Maintenance/.agents` carries the checklist-first skills.
3. **Wire `DIGI0001` into the repositories** and port the text checks of `CheckGuidelineRules.ps1` to Roslyn — with
   `TreatWarningsAsErrors` this can break builds, so it needs its own issue.
4. **The README "Coding Guidelines" block** (about 13 KB in each of 72 READMEs) was left as it is, by decision.

## 5. Not done
- Checklists were added to the 17 guidelines above ~8 KB that are task-routed often; `GitHub - Workspace Setup.md`
  (10.7 KB) and `Coding - WebAPI Simple Authorization.md` (10.5 KB) still load whole, as do the 12 files under 7 KB
  (a checklist there would only add bytes).
- Evidence was split out for `Coding - General.md` and the propagation guideline only (see §1, first finding).
- The end-to-end spot check of the plan (one real C# task under the slimmed `CLAUDE.md`) waits for decision 1.
