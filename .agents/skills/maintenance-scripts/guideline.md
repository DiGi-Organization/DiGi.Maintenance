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

## 1. Execution model
1. Run from `Scripts` with `PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\Script.ps1" -Switch` (`-NoProfile`
   matters when timing or comparing runs).
2. Paths resolve from `$PSScriptRoot`: `-Root` defaults to `"$PSScriptRoot\..\.."` (the `DiGi` workspace root), config to
   `"$PSScriptRoot\..\user files\..."`. Relative `-OutputDirectory`-style parameters bind to the **current** directory —
   pass absolute paths.
3. Run with the host shell, never an isolated sandbox (sibling repositories, `git`, `gh`, network, `localhost`).
4. **Exit codes are not uniform in existing scripts** — many exit `1` or only `Write-Error`, some lack
   `$ErrorActionPreference = "Stop"` and carry on after a failed step. Read a script before trusting its exit code; audits
   report rather than fail unless a `-FailOnMissing`-style switch is passed. New scripts: §5.

## 2. Machine configuration — `DiGi.Maintenance/user files/*.conf`
Key=value files, git-ignored, templates in `files/`. A missing key behaves one of two ways:
- **A setting the script exists for fails the run** (`CopyUserFiles.ps1` without `USER_FILES_BACKUP_DIRECTORY`, unless
  `-Destination`).
- **An optional feature is skipped with a DarkGray note** (`GLOBAL_AGENTS_FILE`, the `INCLUDE_*` opt-ins, the
  `InvestigateServer.ps1` key) — a script that "does nothing" usually skipped by configuration.

| File | Keys | Used by |
|---|---|---|
| `Directories.conf` | `SOFTWARE_DIRECTORY`, `USER_FILES_BACKUP_DIRECTORY`, `GLOBAL_AGENTS_FILE`, `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION`, `INCLUDE_LAYA_MODELS`, `LAYA_MODELS_DIRECTORY` | `Deploy.ps1`, `CopyUserFiles.ps1`, `UpdateAgents.ps1`, `DeployLaya.ps1` |
| `WebAPI_Diagnostics.conf` | diagnostic key | `InvestigateServer.ps1` (`-Key` overrides) |

Never hard-code a machine path or add a custom `.gitignore` record — add a key (template in `files/`, documented in
`Scripts/README.md`). Booleans are opt-in (`true`, `1`, `yes`). Never print a conf (`Coding - General.md` §3); secrets for
`SetSecretsAllRepos.ps1` come from a hidden prompt or the clipboard, never the command line.

## 3. Cross-repository sweeps (`*AllRepos`, `UpdateAgents`, `UpdateReadmes`)
They walk `Get-ChildItem -Directory -Filter "DiGi.*"` under the workspace root (layout: `GitHub - Workspace Setup.md`).
1. Mutating sweeps **commit per repository unless `-NoCommit`/`-DryRun`**, staging narrowly (`git add .agents`,
   `git add README.md`); check `git status --porcelain <path>` and skip clean repositories. None pushes.
2. `git -c core.autocrlf=false add <path>` **only for generated output written as CRLF** (`.agents`); hand-edited scripts
   and guidelines are stored LF and staged with a plain `git add` (§6).
3. **The dry-run trap:** a `-NoCommit` run followed by a committing run **commits nothing** — the second run finds the
   files up to date (`Updated repositories: 0`) and leaves the dirty trees. Decide first: one committing run, or a dry run
   and manual commits per repository.

## 4. Build & deploy flow
- **`BuildAll.ps1`** builds its hard-coded `$solutionOrder` in Release — **not** every `DiGi.*` folder; a new solution is
  skipped until added after everything it references by `HintPath`. Never force `--no-incremental` across the sweep (it can
  delete `DiGi.Core\bin` before its consumers compile, `Coding - Host Dependencies.md` §6). `-CheckDependencies` runs
  `CheckHostDependencies.ps1` over the output (§8 there). `-Summary` prints only failed or warning solutions with
  de-duplicated diagnostics instead of the MSBuild log; `-Solution "<Repo>"` builds one entry of the order.
- **`Deploy.ps1`** builds (unless `-SkipBuild`; a failed build copies nothing), syncs `bin` closures to
  `SOFTWARE_DIRECTORY`, purges `logs` from destinations unless `-RemoveLogs:$false`. Opt-ins:
  `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION` (`Coding - YOLO.md` §5), `INCLUDE_LAYA_MODELS` (`Coding - Laya.md` §5).
- **`SyncDirectory.ps1`** clears each destination's top level (so a nested destination is wiped by its parent's sync) but
  keeps top-level `*.conf`; `runtimes`, satellite resource folders and any top-level folder mirroring a subfolder of the
  source's `files`/`user files` are runtime assets that travel with `bin`. `-ExcludeDirectory`/`-ExcludeFile` keep run
  artifacts (`reports/`, logs) out; an output writing unpredictable folder names needs an allowlist.
- **`CopyUserFiles.ps1`** backs up/restores every repository's `user files/` to `USER_FILES_BACKUP_DIRECTORY` (never
  `reports/`); `-Reverse` restores on a new machine.
- Live-server checks are `InvestigateServer.ps1` / manual `curl` only — never `DiGi.Test` (`Coding - Deployed WebAPI.md`).

## 5. Writing a new script
1. Comment-based help above a `param(...)` block with defaults; `$ErrorActionPreference = "Stop"` right after.
2. **Exit codes:** `0` success, `1` failure, `2` invalid invocation. A filter matching nothing fails —
   `CheckHostDependencies.ps1 -Unit <unknown>` exits 2 listing the known units.
3. `Write-Host -ForegroundColor`: Cyan step, Yellow actionable warning, Red failure, Green final success, DarkGray skipped
   by configuration.
4. Load a conf with a small key=value loop (trim, skip `#`/blank, split on the first `=`); a parameter overrides it;
   required → fail, optional → skip (§2).
5. Idempotent re-runs (`InstallPythonEnvironment.ps1`, `DeployLaya.ps1` skip unchanged work).
6. Document the invocation in `Scripts/README.md` in the same change; a rule agents must follow also gets a guideline
   (`Maintenance - AI Guidelines Propagation.md`).
7. **Output an agent reads is compact:** one line per finding (`<Kind> <path>:<line> <detail>`), nothing for what is fine,
   one summary line, workspace-relative paths, a `-Json` switch emitting a single `ConvertTo-Json -Compress` line. Capture a
   tool's log and print its diagnostics, never the log. Keep the file ASCII (Windows PowerShell reads a BOM-less script
   as ANSI) and never redirect a native command's stderr under `$ErrorActionPreference = "Stop"` (it throws).

## 6. Scripted edits, line endings and the commit
The working tree is CRLF (`.editorconfig` `end_of_line = crlf`; `core.autocrlf=true`), and the common tools do not
preserve it. The damage compiles; it costs the review.
- **`sed -i` (Git Bash) rewrites the whole file as LF**; Python's text mode does the same, and
  `io.open(p, encoding="utf-8-sig")` strips a BOM that writing with `"utf-8-sig"` then *adds*. The symptom is a whole-file
  diff with the real edit invisible inside it.
- **Edit bytes and assert the match count**, so a pattern that matched nothing (or twice) fails loudly:
  ```python
  data = path.read_bytes()
  assert data.count(old) == expected
  path.write_bytes(data.replace(old, new))
  ```
  A multi-line search string carries the file's own newline — detect it per file (`.slnx` and some `.csproj` are LF):
  `eol = b"\r\n" if b"\r\n" in data else b"\n"`.
- **Detect:** `grep -c $'\r'` cannot (it matches every line either way); compare `tr -cd '\r' < f | wc -c` with
  `tr -cd '\n' < f | wc -c`. `git diff --stat --ignore-cr-at-eol` shows the real size of a change; a diff that is only
  `\ No newline at end of file` or empty under `git diff --ignore-cr-at-eol -- <file>` is editor noise —
  `git checkout -- <file>`.
- **Before committing, check `git diff --stat` for deletions you did not make** — a truncated file, a dropped BOM or final
  newline (bodyplan `e2ca81b` cut 385 README lines; a BOM dropped in DiGi.GIS `3bb5f7c`).
- **The stored convention is the blob's, and the `git add` flag decides it.** With `autocrlf=true` and no
  `.gitattributes`, an LF blob checks out as CRLF; read the stored ending from the blob (`git cat-file -p HEAD:<path>`,
  byte-level, or `git ls-files --eol`). The same CRLF working file commits as **LF** under the default and as **CRLF**
  under `-c core.autocrlf=false` — so keep a stored-LF file LF by committing with the default. The convention can split
  within one repository (`README.md` LF, `.agents/*` CRLF); a generator must emit the blob's ending and skip with a warning
  when it would differ. `UpdateReadmes.ps1` once committed CRLF over every LF `README.md` — a full rewrite of 66 repos
  for a five-line change ([DiGi.Maintenance#11](https://github.com/DiGi-Organization/DiGi.Maintenance/issues/11)).
- Markdown bodies sent to GitHub have their own `\r\r\n` trap (`GitHub - Issues.md` §1).

## 7. Context scripts — run one before reading files or logs
Read-only, compact output (§5.7). Each replaces a reading that costs far more context than its answer:

| Question | Script | Instead of |
|---|---|---|
| Which repositories are dirty, behind, ahead or on the wrong branch? | `StatusAllRepos.ps1` (`-Repo`, `-All`, `-Json`) | `git status` per repository |
| What is the signature and summary of a type or member? | `GetApi.ps1 -Assembly "DiGi.Core" -Match "Query\.Clone"` | a namespace page of `documentation/API` (up to ~900 KB) or the `.cs` file |
| Do the facts pass after my change? | `TestSummary.ps1 -Library <csproj> -Project <xUnit>` (`-Filter`) — builds the library first | `dotnet build` + `dotnet test` logs |
| Does everything downstream still build? | `BuildAll.ps1 -Summary` (`-Solution "<Repo>"`) | the MSBuild log of ~75 solutions |
| Did I break a rule no analyzer checks? | `CheckGuidelineRules.ps1 -Repo <Repo> -Changed` | re-reading the changed files against the guidelines |
| Which issues match? | `FilterIssues.ps1` (`GitHub - Issues.md` §4) | raw `gh` JSON |
| What does every agent session load? | `MeasureAgentContext.ps1` | — |
| Did a guideline edit lose a fact? | `CheckGuidelineLossless.ps1 -BaseRef HEAD` | diffing by eye |

`CheckGuidelineRules.ps1` is text-based: a reported line is a candidate, not a verdict, and it repeats nothing the build
already fails on. `GetApi.ps1` is as fresh as the last build of the assembly. The same commands are packaged as workflow
skills (`digi-verify`, `digi-status`, `digi-api`, `digi-issue`, `digi-guideline-change`,
`Maintenance - AI Guidelines Propagation.md` §2).
