# AI Token Optimization — Automation Strategy

What is decided deterministically by a script instead of by an LLM reading files. Commands and switches:
`Scripts/README.md`; conventions for new scripts: `documentation/AI Guidelines/Maintenance - Scripts.md` §5 and §7.

## 1. Principle
A script answers a question; the agent reads the answer. Every agent-facing script is read-only, prints one line per
finding and nothing for what is fine, uses workspace-relative paths, and offers `-Json` as one compressed line. A tool's
log is captured and reduced to its diagnostics — the log itself never reaches the context.

## 2. Context scripts (in `Scripts/`)

| Script | Replaces | Output shape |
|---|---|---|
| `StatusAllRepos.ps1` | `git status` in 72 repositories | `DiGi.Core  0.8.5 (expected 0.8.6)  dirty=3  behind=1`; clean repositories omitted; one count line |
| `GetApi.ps1 -Assembly -Match` | reading a namespace page of `documentation/API` (up to 915 KB) or the source | member name, then `signature  // summary`; capped by `-Max` |
| `TestSummary.ps1 -Library -Project [-Filter]` | `dotnet build` + `dotnet test` logs; also enforces build-before-test (`HintPath`) | `TESTS <project>: 412 passed, 1 failed, 3 skipped (38.2 s)`, then per failure its name, 4 message lines and `at file:line`; a build failure prints `error CS0000 file:line message` |
| `BuildAll.ps1 -Summary [-Solution]` | the MSBuild log of ~75 solutions | only `FAIL`/`WARN <solution>` with de-duplicated diagnostics; one count line |
| `CheckGuidelineRules.ps1 -Repo [-Changed]` | re-reading changed files against the guidelines | `<Rule> <path>:<line> <detail>` for: one public method per `Query`/`Modify`/`Create` file, private methods there, `Get` prefix in `Query`, `using Xunit;`, `TODO` without `[Marker]`, machine paths in markdown, `.gitignore` record, `.editorconfig` preamble |
| `FilterIssues.ps1` (existing; `-Json` now compressed) | raw `gh` JSON | two lines per issue |

Tested on 2026-11-14: each script against `DiGi.Core` and `DiGi.Maintenance`, an unknown argument (exit 2), a seeded
violation per rule, a failing and a non-compiling scratch test project, a filter matching nothing.

## 3. Guideline pipeline

| Piece | Role |
|---|---|
| `documentation/AI Guidelines/Guidelines.json` | the one list of guidelines: `file`, `category`, `description` (skill), `route` (`CLAUDE.md` cell) |
| `UpdateAgents.ps1` | validates manifest ↔ files ↔ README block, rewrites the generated blocks of the guidelines `README.md`, `.agents/AGENTS.md` and `CLAUDE.md`, emits skills (`SKILL.md` = introduction + checklist, `guideline.md` = whole text, `evidence.md`), copies workflow skills to `.agents/skills` and `.claude/skills`, writes the workspace `.ignore`; `-Repo` scopes the sweep |
| `CheckGuidelineLossless.ps1 -BaseRef` | guard: a guideline edit may move a fact, never lose one |
| `MeasureAgentContext.ps1` | guard: what every session loads, per tool, and what each guideline costs |

A guideline change is now: edit the file (and its manifest entry when it is new or renamed) → lossless check →
`UpdateAgents.ps1` → measure. The workflow skill `digi-guideline-change` carries exactly that.

## 4. What stays with the LLM
Deliberately not scripted, because a text check would be wrong often enough to cost more than it saves: naming by type,
explicit typing beyond what the compiler enforces, the content of XML documentation, whether a constructor does work,
whether a rule's exception applies. `CheckGuidelineRules.ps1` reports candidates; it does not judge.

## 5. Follow-ups (not implemented)
1. **Analyzers in every build:** reference `DiGi.Maintenance.Analyzers` (`DIGI0001`) from the template
   `Directory.Build.props`, then port `OnePublicMethod`, `PrivateMethod`, `QueryGetPrefix` and `XunitUsing` to Roslyn so
   the build, not a script, reports them. Needs a decision: with `TreatWarningsAsErrors` existing violations (8 candidates
   in `DiGi.Core` alone) break builds until fixed or suppressed.
2. **A compact API index per assembly** generated at build time (one line per member) would make `GetApi.ps1` a plain
   `grep`; today it parses the DefaultDocumentation pages on each call (well under a second per assembly).
3. **`StatusAllRepos.ps1` in `FilterIssues.ps1` style for dependencies:** `FilterIssues.ps1` still does not show
   `blocked_by` (`GitHub - Issues.md` §4).
4. **Checklists for the two remaining large guidelines** (`GitHub - Workspace Setup.md`,
   `Coding - WebAPI Simple Authorization.md`).
