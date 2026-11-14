# DiGi Maintenance Scripts

This directory contains PowerShell maintenance scripts for managing, building, synchronizing, and setting up DiGi solution repositories.

## Configuration

Configuration settings for maintenance scripts are stored in relative configuration files under the `user files/` directory:

### `user files/Directories.conf`
Copy `files/Directories.conf` to `user files/Directories.conf` and configure the target path variables:
- `SOFTWARE_DIRECTORY`: Target directory for software output binary synchronization (used by `Deploy.ps1`).
- `USER_FILES_BACKUP_DIRECTORY`: Target directory for copying and restoring repository `user files` folders (used by `CopyUserFiles.ps1`).
- `GLOBAL_AGENTS_FILE`: Path to a machine-global `AGENTS.md` outside the workspace, refreshed from the AI Guidelines by `UpdateAgents.ps1`. Leave empty to skip that step.
- `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION`: Opt-in (`true`, `1` or `yes`; anything else is off). Assembles the Year Built prediction runner and its `model.pt` into the tray application's bin (`Deploy.ps1`). Set it only on a machine that deploys to an ML-capable host.
- `INCLUDE_LAYA_MODELS`: Opt-in, parsed the same way. Deploys the Laya runtime package and released checkpoints to `SOFTWARE_DIRECTORY\DiGi.Laya` with `DeployLaya.ps1` after the software syncs (`Deploy.ps1`).
- `LAYA_MODELS_DIRECTORY`: Released Laya checkpoints on this machine, outside the workspace — one subfolder per model, with an optional `<name>.calibration.json` beside it.

---

## Execution Commands

### Build All Solutions
Builds all DiGi solution repositories in Release configuration. Pass `-CheckDependencies` to run
`CheckHostDependencies.ps1` against the produced output once every solution has built, failing when
a host is missing an assembly its libraries reference. Rebuilding a single solution with
`--no-incremental` can delete `DiGi.Core\bin` before compiling against it (`Coding - Host Dependencies.md` §6): build incrementally, or `DiGi.Core` first.
```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Configuration Release

# Build, then audit the host outputs for unresolvable assembly references
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Configuration Release -CheckDependencies

# Summary mode: no MSBuild log - only FAIL/WARN solutions with de-duplicated 'error CS0000 file:line message' lines
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Summary

# One solution of the build order (an unknown name exits with code 2)
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Configuration Debug -Summary -Solution "DiGi.Core"
```

### Agent Context Scripts (compact output instead of raw files and logs)
Read-only scripts whose output is meant to be read by an AI agent (or a person in a hurry): one line per finding,
nothing for what is fine, `-Json` as one compressed line. Use them before reading files or logs
(`Maintenance - Scripts.md` §7).
```powershell
# Which repositories need attention: branch (and the expected version branch), uncommitted files, ahead/behind
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\StatusAllRepos.ps1"
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\StatusAllRepos.ps1" -Repo "DiGi.Core" -All

# Signature + summary of the public members matching a regular expression, from documentation/API
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\GetApi.ps1" -Assembly "DiGi.Core" -Match "Query\.Clone"

# Build the changed library first (HintPath: dotnet test never rebuilds it), run the facts, print counts + failures only
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\TestSummary.ps1" -Library "..\..\DiGi.Core\DiGi.Core\DiGi.Core.csproj" -Project "..\..\DiGi.Core\DiGi.Core.xUnit"
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\TestSummary.ps1" -Project "..\..\DiGi.Core\DiGi.Core.xUnit" -Filter "FullyQualifiedName~SerializationCheck"

# The coding rules no analyzer enforces (one public method per Query/Modify/Create file, no private methods there,
# Get prefix in Query, using Xunit, TODO without [Marker], machine paths in markdown, .gitignore, .editorconfig)
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineRules.ps1" -Repo "DiGi.Core" -Changed
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineRules.ps1" -Repo "DiGi.Core" -FailOnViolation

# What every agent session loads (CLAUDE.md, AGENTS.md, skill descriptions) and what each guideline costs when read
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\MeasureAgentContext.ps1"

# After editing a guideline: no code line, backticked identifier, issue reference, date, number or numbered
# section of the base version may be lost (it may move to the guideline's Evidence file or another guideline)
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineLossless.ps1" -BaseRef HEAD
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineLossless.ps1" -BaseRef HEAD -Name "Coding - General.md" -Detail
```

### Check Host Dependencies
Audits the build output of every deployed host for assembly references that cannot be resolved at
runtime. DiGi repositories reference each other by `HintPath`, which is opaque to NuGet, so a
library's transitive NuGet dependencies never reach a host that consumes it that way — the host
builds clean, the tests pass, and the assembly is missing only at runtime, usually as a *partial
result* rather than an error. Requires a prior build; reviewed exceptions are declared per unit
inside the script. `DiGi.WebAPI.WindowsService` is audited together with `bin\extensions\*`, because
they share one probing set.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CheckHostDependencies.ps1"

# Audit a single deployment unit (an unknown name exits with code 2 and lists the known units,
# rather than auditing nothing and passing). Units include the bodyplan hosts bodyplan.Importer
# and bodyplan.WebAPI.UI, deployed by bodyplan\Scripts\Deploy.ps1.
PowerShell -ExecutionPolicy Bypass -File ".\CheckHostDependencies.ps1" -Unit "DiGi.GIS.WebAPI.UI"

# Exit with code 1 when a gap is found (for use in automation)
PowerShell -ExecutionPolicy Bypass -File ".\CheckHostDependencies.ps1" -FailOnMissing
```

### Sync Output Directories
Builds every solution with `BuildAll.ps1` (unless `-SkipBuild` is specified; a failed build stops before anything is copied), then synchronizes output binary directories across web services and the configured software output directory (`SOFTWARE_DIRECTORY` in `user files/Directories.conf`). By default, purges `logs` directories and log files from software output folders unless `-RemoveLogs:$false` is specified.
```powershell
# Build, sync directories and clean logs in software destinations (default)
PowerShell -ExecutionPolicy Bypass -File ".\Deploy.ps1"

# Sync the bin folders as last built, without building
PowerShell -ExecutionPolicy Bypass -File ".\Deploy.ps1" -SkipBuild

# Build in Debug, then sync
PowerShell -ExecutionPolicy Bypass -File ".\Deploy.ps1" -Configuration Debug

# Sync directories preserving log files
PowerShell -ExecutionPolicy Bypass -File ".\Deploy.ps1" -RemoveLogs:$false
```

### Deploy Laya Models
Deploys the Laya runtime package (`requirements.txt`, `InstallPythonEnvironment.ps1`) and released checkpoints to `<SoftwareDirectory>\DiGi.Laya\`. `Deploy.ps1` calls it when `INCLUDE_LAYA_MODELS` is set; consumer deploy scripts (bodyplan) call it directly. Each checkpoint is copied from an allowlist of the checkpoint layout (everything else is printed on the `Not deployed:` line), its `<name>.calibration.json` is copied beside it, and `models\<name>.manifest.json` is written beside the folder - never inside it, because DiGi.Laya identifies a checkpoint by the SHA-256 of its whole folder. An unchanged model is skipped; a deployed model is removed only by `-Remove`. Exits with code 1 when a model failed. See `Coding - Laya.md`.
```powershell
# Deploy every model in the released checkpoints directory
PowerShell -ExecutionPolicy Bypass -File ".\DeployLaya.ps1" -SoftwareDirectory "<SoftwareDirectory>" -ModelsDirectory "<LayaModelsDirectory>"

# Deploy one model and remove another from the software directory
PowerShell -ExecutionPolicy Bypass -File ".\DeployLaya.ps1" -SoftwareDirectory "<SoftwareDirectory>" -ModelsDirectory "<LayaModelsDirectory>" -ModelNames "recipe_classification" -Remove "recipe_classification_old"
```

### Install the Laya Python Environment (on a host)
Run on each host that runs Laya - never by `Deploy.ps1`. Creates the virtual environment, installs torch from the PyTorch CPU or CUDA (`cu128` by default) wheel index, then `requirements.txt`, and writes `environment.json`. A re-run with the same requirements and torch variant is a no-op. Put the environment **outside** the synced software directory: it is several GB and specific to the host.

Host procedure:
1. Install CPython 3.10 or newer, readable and executable by the account of the service that runs the consumer (`DiGi.WebAPI.WindowsService` on the database server).
2. Run the script below from the deployed `DiGi.Laya` folder.
3. Set the consumer's conf: `PythonPath` = the printed venv `python.exe`, `ModelPath` = `<SoftwareDirectory>\DiGi.Laya\models\<name>`, `CalibrationPath` = `<SoftwareDirectory>\DiGi.Laya\models\<name>.calibration.json`.
4. Run the consumer's preflight (`Query.LayaEnvironmentResult`, e.g. bodyplan's `--check`).
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\InstallPythonEnvironment.ps1" -PythonPath "<python.exe>" -RequirementsPath ".\requirements.txt" -Destination "<VenvDirectoryOutsideSoftwareDirectory>" -Torch cpu
```

### Copy User Files
Copies `user files` configuration folders from all DiGi repositories to the backup data directory (`USER_FILES_BACKUP_DIRECTORY` in `user files/Directories.conf`), excluding `reports` folders, or restores from the backup directory back to matching repositories when `-Reverse` or `-Restore` is specified.
```powershell
# Copy user files to backup directory
PowerShell -ExecutionPolicy Bypass -File ".\CopyUserFiles.ps1"

# Restore user files from backup directory to workspace
PowerShell -ExecutionPolicy Bypass -File ".\CopyUserFiles.ps1" -Reverse

# Override backup directory explicitly via parameter
PowerShell -ExecutionPolicy Bypass -File ".\CopyUserFiles.ps1" -Destination "<PathToBackupDirectory>"
```

### Pull Branches Across All Repositories
Synchronizes all DiGi repositories to their highest SemVer branch and pulls remote changes.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\PullBranchesAllRepos.ps1"
```

### Sync Branches Across All Repositories
Merges active version branch to main, bumps patch version, creates a new branch, and pushes across all repositories.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\SyncBranchesAllRepos.ps1"
```

### Commit All Repositories
Commits pending changes across all DiGi repositories.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CommitAllRepos.ps1" -Message "Update"
```

### Push All Repositories
Pushes commits across all DiGi repositories.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\PushAllRepos.ps1"
```

### Commit and Push Current Branch
Commits and pushes current branch across all DiGi repositories.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CommitAndPushCurrentBranch.ps1" -Message "Update"
```

### Sync Wiki
Synchronizes local documentation and Wiki pages with GitHub wikis.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\SyncWiki.ps1"
```

### Check Wiki Pages
Verifies and checks structure of GitHub wiki pages.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CheckWikiPages.ps1"
```

### Update AI Agents & Guidelines
Regenerates `.agents/AGENTS.md` and `.agents/skills/*/SKILL.md` across all DiGi repositories (and `templates/DiGi.Template`) from `DiGi.Maintenance/documentation/AI Guidelines`, and refreshes the machine-global `AGENTS.md` when `GLOBAL_AGENTS_FILE` is configured. The manifest `documentation/AI Guidelines/Guidelines.json` is the one list of guidelines (category, skill description, `CLAUDE.md` routing cell): the script rewrites the blocks between `<!-- guidelines:begin -->` and `<!-- guidelines:end -->` in the guidelines `README.md`, `.agents/AGENTS.md` and the workspace `CLAUDE.md` from it, copies each guideline's `Evidence/<same name>.md` beside its skill as `evidence.md`, and copies the workflow skills in `files/skills/` into every `.agents/skills` and the workspace `.claude/skills`. Changes are committed per repository unless `-NoCommit` is passed. Fails before writing anything if the manifest and the guideline files disagree (a file not listed, a listed file missing, a file `files/README - Coding Guidelines.md` does not name), or if a source file carries a stray `\r\r\n` line ending - the sequence its own normalisation would otherwise propagate silently.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1"

# Update the files without creating commits
PowerShell -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -NoCommit

# Refresh the generated blocks and one repository only (an unknown name exits with code 2)
PowerShell -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -Repo "DiGi.Maintenance"
```

### Update Solution READMEs
Replaces the shared `## 💻 Coding Guidelines for Developers & AI Agents` block at the end of every `DiGi.*/README.md` with the canonical block from `files/README - Coding Guidelines.md`, preserving the repository-specific content above it. Changes are committed per repository unless `-NoCommit` is passed.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\UpdateReadmes.ps1"

# Update the files without creating commits
PowerShell -ExecutionPolicy Bypass -File ".\UpdateReadmes.ps1" -NoCommit
```

### Set the Wiki Sync Secret
Sets `WIKI_SYNC_PAT` once as a **DiGi-Organization** secret (visibility: all), which every repository's `sync-wiki.yml` uses to push the API pages to its wiki - `GITHUB_TOKEN` cannot push to a wiki. Use a classic personal access token with the `public_repo` scope. The script checks the token with the GitHub API before storing it and takes it from a hidden prompt or the clipboard, never from the command line. Needs `gh auth refresh -h github.com -s admin:org`.
```powershell
# Copy the token, then:
pwsh -File ".\SetSecretsAllRepos.ps1" -FromClipboard

# Also delete stale repository-level copies, which would override the organization secret
pwsh -File ".\SetSecretsAllRepos.ps1" -FromClipboard -RemoveRepositorySecrets
```

### Sync GitHub Workflows to Main
Synchronizes GitHub Actions workflows to `main` branch across all repositories.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\SyncWorkflowToMain.ps1"
```

### Apply Documentation Setup
Applies XML documentation build targets to project files.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\ApplyDocumentationSetup.ps1"
```

### Filter GitHub Issues by Labels
Searches, filters, and inspects GitHub issues across a single repository or all DiGi repositories by labels, repository, state, and search terms with token-efficient output. Automatically normalizes shorthand label names (`standard`, `high`, `bug`, etc.) to standard DiGi taxonomy names.
```powershell
# Filter issues in a specific repository by labels
PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.Core" -Labels "ai: standard, priority: high"

# Filter issues across all repositories using label shorthands
PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Labels "standard, high"

# Search keyword in titles/descriptions
PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Search "subdivision"

# Inspect specific issue with description preview
PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Issue 42 -Detail

# Output clean JSON for programmatic processing
PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Labels "critical" -Json
```

### Sync GitHub Labels Across All Repositories
Synchronizes the standardized 21-label taxonomy across all DiGi repositories on GitHub.
```powershell
# Preview label sync changes across all repositories
PowerShell -ExecutionPolicy Bypass -File ".\SyncLabelsAllRepos.ps1" -DryRun

# Sync labels for a single target repository
PowerShell -ExecutionPolicy Bypass -File ".\SyncLabelsAllRepos.ps1" -Repo "DiGi.Core"

# Sync labels across all DiGi repositories
PowerShell -ExecutionPolicy Bypass -File ".\SyncLabelsAllRepos.ps1"
```

