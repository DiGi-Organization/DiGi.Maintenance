---
name: maintenance-scripts
description: "Use when running or writing DiGi.Maintenance workspace scripts (BuildAll, Deploy, CheckHostDependencies, CopyUserFiles, CommitAllRepos and the other *AllRepos sweeps, InvestigateServer) - execution conventions ($PSScriptRoot path resolution, exit-code contract 0/1/2, host shell only), machine configuration in user files/*.conf (Directories.conf keys, opt-in booleans, never printing conf contents), cross-repository sweep conventions (narrow staging, core.autocrlf=false, the -NoCommit dry-run trap), the build & deploy flow with its HintPath and runtime-asset traps, and the house conventions for a new script."
---

# AI Guidelines: Maintenance Scripts & Workspace Operations

Scope: `DiGi.Maintenance/Scripts/*.ps1` and the workspace-wide build/deploy flow they drive.
`DiGi.Maintenance/Scripts/README.md` is the canonical command catalog — read it for the exact
invocation of a script; this file carries the **conventions, machine configuration, and traps** the
README does not.

---

## 1. Execution Model

1. **Run from the `Scripts` directory** with
   `PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\Script.ps1" -Switch`. `-NoProfile`
   matters when timing or comparing runs — a loaded profile changes the environment.
2. **Paths resolve from `$PSScriptRoot`, not from the current directory.** Workspace-rooted scripts
   default `-Root` to `"$PSScriptRoot\..\.."` (the `DiGi` workspace root); config lives at
   `"$PSScriptRoot\..\user files\..."`. Relative `-OutputDirectory`-style parameters, however, DO
   bind to the current directory — pass absolute paths for those.
3. **Run with the host shell, never an isolated sandbox** — these scripts touch sibling
   repositories, `git`, `gh`, the network and `localhost`, none of which a file-sandboxed shell
   reaches reliably.
4. **Exit-code contract:** `0` success, `1` failure, `2` invalid invocation. A filter that matches
   nothing must fail, not vacuously pass — e.g. `CheckHostDependencies.ps1 -Unit <unknown>` exits 2
   and lists the known units rather than auditing nothing and returning 0. Trust exit codes only
   from scripts you have not modified; `-FailOnMissing`-style switches exist precisely because the
   default for audits is to report, not to fail.

## 2. Machine Configuration — `DiGi.Maintenance/user files/*.conf`

Machine-specific settings live in key=value `.conf` files under `user files/` (git-ignored;
templates in `files/`). Scripts parse them by hand and **warn-and-skip, not fail**, when a key is
missing — so a silently missing setting looks like a script that "does nothing".

| File | Keys | Used by |
|------|------|---------|
| `Directories.conf` | `SOFTWARE_DIRECTORY`, `USER_FILES_BACKUP_DIRECTORY`, `GLOBAL_AGENTS_FILE`, `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION`, `INCLUDE_LAYA_MODELS`, `LAYA_MODELS_DIRECTORY` | `Deploy.ps1`, `CopyUserFiles.ps1`, `UpdateAgents.ps1`, `DeployLaya.ps1` |
| `WebAPI_Diagnostics.conf` | diagnostic key | `InvestigateServer.ps1` (overridable with `-Key`) |

Rules:
- **Never hardcode a machine path in a script** and never add a custom `.gitignore` record instead —
  add a key to `Directories.conf` (template in `files/`, documented in `Scripts/README.md`).
- Booleans are opt-in: `true`, `1`, `yes`; anything else is off.
- **Never print the contents of a `user files/` conf** (it can hold tokens and connection
  secrets); print only the key name or a redacted value. Secrets for `SetSecretsAllRepos.ps1` come
  from a hidden prompt or the clipboard — never from the command line.

## 3. Cross-Repository Sweeps

Scripts named `*AllRepos` walk `Get-ChildItem -Directory -Filter "DiGi.*"` under the workspace root
and `Push-Location`/`Pop-Location` into each repository. When writing or changing one:

1. **Mutating scripts commit per repository unless `-NoCommit`/`-DryRun` is passed**, and they stage
   narrowly (`git add .agents`, `git add README.md`) so unrelated work in a checkout is untouched.
2. **Use `git -c core.autocrlf=false add <path>`** for files the script generates with CRLF bytes —
   a machine with `core.autocrlf=true` otherwise turns the commit into a whole-file line-ending diff.
3. Check `git status --porcelain <path>` before committing and skip clean repositories.
4. **The dry-run trap:** a `-NoCommit` run followed by a committing run **commits nothing** — the
   second run finds the files already up to date, reports `Updated repositories: 0`, and leaves the
   dirty trees behind. Decide before the first run: dry-run only (`-NoCommit`, commit manually per
   repository afterwards) or one committing run. Neither sweep pushes.
5. The workspace layout (one folder per owner, `DiGi\` = organization repos) is defined in
   `GitHub - Workspace Setup.md`; `SetupWorkspace.ps1` clones/repairs it (`-IncludeWikis`,
   `-UpdateRemotes`).

## 4. Build & Deploy Flow

- **`BuildAll.ps1`** builds every `DiGi.*` solution in Release. Do **not** force
  `--no-incremental` across the sweep: it can delete `DiGi.Core\bin` before the solutions that
  `HintPath` it are compiled (`Coding - General.md`, Build-Time Symptoms). Build incrementally, or
  `DiGi.Core` first.
- **`-CheckDependencies`** runs `CheckHostDependencies.ps1` over the produced output. It exists
  because `HintPath` references are opaque to NuGet and a host missing a library's transitive
  package fails as a **partial result, not an error** (`Coding - General.md`, host
  `PackageReference`). A reviewed exception declared inside the script must state its reason — an
  unexplained entry re-hides exactly the bug class the audit finds.
- **`Deploy.ps1`** builds (unless `-SkipBuild`; a failed build stops before anything is copied),
  syncs `bin` closures to `SOFTWARE_DIRECTORY`, and purges `logs` from software destinations unless
  `-RemoveLogs:$false`. Extension hosts (`DiGi.*.WebAPI` under `DiGi.WebAPI.WindowsService\bin\extensions\`)
  share one probing set with their host. Machine opt-ins from `Directories.conf`:
  `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION` (YOLO runner + `model.pt`, `Coding - YOLO.md`) and
  `INCLUDE_LAYA_MODELS` (calls `DeployLaya.ps1`, `Coding - Laya.md`).
- **`SyncDirectory.ps1`** exclusion semantics: `runtimes`, satellite resource folders, and any top-
  level folder mirroring a subfolder of the source's `files`/`user files` are runtime assets — they
  must travel with the `bin` or must not be purged.
- **`CopyUserFiles.ps1`** backs up / restores every repository's `user files/` to
  `USER_FILES_BACKUP_DIRECTORY`, always excluding `reports/`. Run it before machine migrations;
  restore with `-Reverse`.
- **Live-server checks are `InvestigateServer.ps1` / manual `curl` only** — never add deployed-API
  probes to `DiGi.Test` (`Coding - Deployed WebAPI.md`).

## 5. Writing a New Maintenance Script

House conventions, as exhibited by the existing scripts:

1. Comment-based help (`<# .SYNOPSIS .DESCRIPTION .PARAMETER ... #>`) above a `param(...)` block
   with defaults; `$ErrorActionPreference = "Stop"` immediately after.
2. `Write-Host -ForegroundColor`: Cyan = step start, Yellow = actionable warning, Red = failure,
   Green = final success, DarkGray = skipped-by-configuration.
3. A `user files/` conf is loaded with a small hand-rolled key=value loop (trim, skip `#`/blank,
   split on the first `=`) — parameter overrides conf, missing conf warns and skips the feature.
4. Idempotent re-runs are the norm (`InstallPythonEnvironment.ps1` no-ops on unchanged
   requirements; `DeployLaya.ps1` skips unchanged models, removes only with `-Remove`).
5. Add a section with the invocation examples to `Scripts/README.md` in the same change; that file
   is what humans and agents read first.
6. If the script codifies a rule or workflow agents must follow, write the matching guideline in
   `documentation/AI Guidelines/` too (`Maintenance - AI Guidelines Propagation.md`).
