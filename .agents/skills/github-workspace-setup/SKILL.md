---
name: github-workspace-setup
description: "Use when setting up a new machine or changing the local GitHub folder layout - one folder per owner (DiGi, DigiProject, ZiolkowskiJakub), SetupWorkspace.ps1, restoring user files/ (CopyUserFiles.ps1 -Reverse), AI-app root files, migrating from the pre-2026-10-14 layout, the WIKI_SYNC_PAT organization secret."
---

# GitHub - Workspace Setup

> [!IMPORTANT]
> Relative paths and `%USERPROFILE%`-style placeholders only — never an absolute user path.

## 1. One folder per GitHub owner
Every repository lives in the folder named after its owner, directly under the GitHub root (typically
`%USERPROFILE%\GitHub`):

| Local folder | GitHub owner | Contents |
|---|---|---|
| `DiGi\` | [DiGi-Organization](https://github.com/DiGi-Organization) | every `DiGi.*` library + the workspace files below |
| `DiGi\templates\` | DiGi-Organization | `DiGi.Template`, `DiGi.WebAPI.GLTF.Template` |
| `DiGi\wiki\` | DiGi-Organization | `<repo>.wiki` clones (on demand, `GitHub Wiki.md`) |
| `DigiProject\` | [DigiProject-Organization](https://github.com/DigiProject-Organization) | client projects: `bodyplan`, `Uponor`, `TimGreatrexArchitect`, `EtexGroup` |
| `ZiolkowskiJakub\` | [ZiolkowskiJakub](https://github.com/ZiolkowskiJakub) | personal repositories worked on locally |
| `SAM-BIM\` | [SAM-BIM](https://github.com/SAM-BIM) | SAM repositories (managed separately) |

"All DiGi repositories" = every repository directly inside `DiGi\`; the Maintenance scripts (`*AllRepos.ps1`,
`UpdateAgents.ps1`, `UpdateReadmes.ps1`, `BuildAll.ps1`) treat the parent of `DiGi.Maintenance` as the root.
- **DiGi repositories stay siblings** — relative `HintPath`s (`..\..\DiGi.Core\bin\DiGi.Core.dll`) depend on it.
- **Outside `DiGi\`, reach DiGi through the GitHub root:** from `DigiProject\bodyplan\<Folder>\<Project>\` a DiGi assembly is
  `..\..\..\..\DiGi\DiGi.Core\bin\DiGi.Core.dll`; bodyplan's `Scripts\Deploy.ps1` defaults `-Root` to `..\..\..\DiGi`,
  `bodyplan.WebAPI.UI.csproj` copies `gis-theme.css` from `..\..\..\..\DiGi\DiGi.GIS.WebAPI.UI\`, and
  `CheckHostDependencies.ps1` finds bodyplan at `..\DigiProject\bodyplan\`.
- **The workspace root `DiGi\` holds only AI-app configuration and shared clones:** `CLAUDE.md` (Claude Code; a
  condensation of the AI Guidelines, re-synced from them), `AGENTS.md` (LM Studio Bionic only — other agents read
  `<repo>/.agents/AGENTS.md`), `opencode.jsonc` + `.opencode/`, `.claude/` (launch configurations, permissions),
  `templates/`, `wiki/`. **These root files are in no repository** — cloning does not restore them (§2.5). Reports and
  scratch files go in a repository's `user files/`, never the root.
- Repositories hosted elsewhere (a Bitbucket clone under `Uponor\`) sit beside the owner folders, outside this convention.

## 2. New machine
### 2.1 Prerequisites
Git for Windows (with Git Bash), the GitHub CLI logged in as a member of **both** organizations (check
`gh repo list DiGi-Organization --limit 5` and the same for `DigiProject-Organization`; grant the CLI OAuth access where an
organization restricts it), Visual Studio 2026 and the solutions' .NET SDK (`dotnet --list-sdks`), PowerShell 7 (`pwsh`,
required by `SetSecretsAllRepos.ps1`). Organization secrets need `gh auth refresh -h github.com -s admin:org`.

### 2.2 Clone everything
```powershell
New-Item -ItemType Directory "$env:USERPROFILE\GitHub\DiGi" -Force | Out-Null
git clone https://github.com/DiGi-Organization/DiGi.Maintenance.git "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance"
& "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance\Scripts\SetupWorkspace.ps1" -WhatIf
& "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance\Scripts\SetupWorkspace.ps1"
```
It creates the owner folders and clones every repository of both organizations (templates into `DiGi\templates\`) plus
`$personalRepositories`; it never re-clones, so re-run it after a new repository appears.

| Parameter | Effect |
|---|---|
| `-WhatIf` | print what would be cloned/changed |
| `-IncludeWikis` | also clone every DiGi wiki into `DiGi\wiki\<repo>.wiki` |
| `-UpdateRemotes` | point `origin` of existing clones (and wiki clones) at the current owner; compared by owner + name, so an ssh or `.git`-less remote already naming the right repository is left alone, and ssh stays ssh |
| `-Only <names>` | restrict to the named repositories |
| `-Root <path>` | GitHub root; defaults to the parent of the `DiGi` folder the script runs from, else the current directory |

Then check out the newest version branch everywhere (`GitHub - Branches and Commits.md` §5).

### 2.3 Restore the git-ignored `user files/`
1. Copy `DiGi.Maintenance/files/Directories.conf` to `DiGi.Maintenance/user files/` and set
   `USER_FILES_BACKUP_DIRECTORY` (and `SOFTWARE_DIRECTORY` if this machine deploys).
2. `Scripts/CopyUserFiles.ps1 -Reverse` restores from the backup. It covers only the DiGi workspace — back up and copy
   project repositories' `user files/` (bodyplan's) separately.

Without a backup, recreate them by hand:

| Repository | `user files/` |
|---|---|
| DiGi.Maintenance | `Directories.conf`, `GitHub.conf` (`URL` = `https://github.com/DiGi-Organization`; token with organization access) |
| DiGi.GIS.PostgreSQL, DiGi.GIS.UI | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Storage.conf` |
| DiGi.GIS.PostgreSQL.UI | the two above, `GIS_WebAPI_Client.conf`, `User_PostgreSQL_Main.conf` |
| DiGi.GIS.WebAPI | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Storage.conf`, `GIS_WebAPI.conf` |
| DiGi.GIS.YOLO.UI | `GIS_WebAPI_Client.conf`, `YearBuiltPredictionPipelineOptions*.json` |
| DiGi.User.PostgreSQL, DiGi.User.WebAPI | `User_PostgreSQL_Main.conf` |
| DiGi.WebAPI, DiGi.WebAPI.WindowsService | `WebAPI_Diagnostics.conf` |
| DiGi.Test | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Main_Test.conf`, `GIS_PostgreSQL_Storage_Test.conf`, `User_PostgreSQL_Main.conf`, `PostgreSQL_Table.conf`, `PostgreSQL_UniqueReference.conf`, `PostgreSQL_PartitionReference.conf`, `PostgreSQL_PartitionUniqueReference.conf`, `DiGi.YOLO_Preflight.conf`, `DiGi.YOLO.ONNX_Parity.conf` — a `*_Test.conf` never names a production database (`Coding - PostgreSQL.md` §6) |
| DigiProject\bodyplan | `Directories.conf` (`SOFTWARE_DIRECTORY` for `Scripts\Deploy.ps1`), `Bodyplan_PostgreSQL_Main.conf`, `Bodyplan_PostgreSQL_Test.conf`, `Bodyplan_WebAPI.conf`; `UI/user files/`: `Bodyplan_WebAPI_UI.conf` |

### 2.4 Build
`Scripts/BuildAll.ps1` in dependency order (from `DiGi.Core`); a library builds before anything referencing it by
`HintPath` (`Coding - Host Dependencies.md`).

### 2.5 AI apps
Copy the root files from the old machine or a backup: `CLAUDE.md`, `AGENTS.md`, `opencode.jsonc`, `.opencode\agents\`,
`.opencode\package.json`, `.claude\` (`launch.json`, `settings.local.json`); reinstall `.opencode\node_modules` with
`npm install` inside `.opencode\`.
- **Claude Code:** start sessions in `DiGi\` so `CLAUDE.md` and `.claude/` load. Memory and history are keyed by the launch
  folder — `%USERPROFILE%\.claude\projects\<key>\`, the path with every `:`, `\` and `.` turned into `-`
  (`GitHub\DiGi` → `C--Users-<user>-GitHub-DiGi`); copy those folders to keep them.
- **OpenCode:** `opencode.jsonc` loads `CLAUDE.md` and `DiGi.Maintenance/.agents/AGENTS.md`.
- `.agents/` in every repository is generated (`UpdateAgents.ps1`) and committed — it arrives with the clone.

### 2.6 Check
`SetupWorkspace.ps1 -WhatIf` reports nothing to do (except repositories deliberately not kept here); `BuildAll.ps1` builds,
then the project repositories (bodyplan last); `dotnet test DiGi.Test\DiGi.Test.slnx --settings DiGi.Test\TestDuration.Short.runsettings`
passes (database/model facts skip without their confs).

## 3. Migrating a machine from the pre-2026-10-14 layout
Before 2026-10-14 every repository was owned by `ZiolkowskiJakub` and the DiGi repositories lived in `GitHub\DigiProject\`.
On 2026-10-14, 73 `DiGi.*` repositories moved to DiGi-Organization and `bodyplan`, `Uponor`, `TimGreatrexArchitect`,
`EtexGroup` to DigiProject-Organization (issues, PRs, wikis, Actions secrets, dependencies and assignees preserved; old URLs
redirect until a same-named repository reappears on the personal account); every link, workflow and path was rewritten,
and `sync-wiki.yml` checks out `${{ github.repository_owner }}/DiGi.Maintenance`.
1. Close Visual Studio and terminals; `git -C <repo> fsmonitor--daemon stop` in each repository.
2. Rename `GitHub\DigiProject` → `GitHub\DiGi`; create `GitHub\DigiProject` (bodyplan, Uponor, TimGreatrexArchitect) and
   `GitHub\ZiolkowskiJakub` (personal) and move them in.
3. Pull `DiGi.Maintenance` (`main`) first (older checkouts lack `SetupWorkspace.ps1`), then run
   `SetupWorkspace.ps1 -UpdateRemotes` (repoints every `origin`, clones what is missing).
4. Pull everything (`PullBranchesAllRepos.ps1`; `git pull` in project repositories).
5. Fix `DiGi.Maintenance/user files/GitHub.conf` `URL` and any personal configuration naming `GitHub\DigiProject\DiGi…`.
6. Claude Code: copy `…\C--Users-<user>-GitHub\memory\` and/or `…-GitHub-DigiProject\` into `…-GitHub-DiGi\`, rename
   `…-GitHub-DigiProject-DiGi-*` to `…-GitHub-DiGi-DiGi-*` (bodyplan/Uponor folders keep their names), move launch and
   permission rules from `GitHub\.claude\` into `GitHub\DiGi\.claude\` with paths relative to `DiGi\`.
7. Repoint shortcuts, scheduled tasks, startup entries or services running from `GitHub\DigiProject\DiGi.*\bin` (e.g. the
   tray application); `.vs\` layouts are harmless.
8. Check as in §2.6 and run `CheckHostDependencies.ps1` once (a wrong path shows as a missing output folder). The Claude
   Code cloud environment uses `documentation/Claude Cloud Enviroment Script.txt` (one level above this file).

## 4. Wiki sync secret (`WIKI_SYNC_PAT`)
Every repository's `sync-wiki.yml` pushes `documentation/API/` to its wiki on a push to `main`/`master` with
`${{ secrets.WIKI_SYNC_PAT || secrets.GITHUB_TOKEN }}`; `GITHUB_TOKEN` cannot push to a wiki.
- **One organization secret** (DiGi-Organization, visibility *all*); no repository copies — a repository secret would
  override it and keep failing after renewal. A new repository needs nothing.
- **The token** is a classic PAT with `public_repo` (40 characters, `ghp_…`); wiki repositories are public (an organization
  secret does not reach private ones on GitHub Free). When it expires every wiki push fails.
- **Renew:** regenerate, copy with the copy button, `Scripts/SetSecretsAllRepos.ps1 -FromClipboard` (needs `admin:org`); it
  validates the token with the API and refuses a bad one. `-RemoveRepositorySecrets` deletes stale repository copies.
- **A new wiki exists only after its first page** is created in the web UI (*Wiki* → *Create the first page*).

| *Run Wiki Sync Script* error | Cause |
|---|---|
| `Repository not found` on clone | the wiki has no first page |
| `Permission to ... denied to github-actions[bot]` (403) | no `WIKI_SYNC_PAT` reached the job |
| `Invalid username or token` | expired, revoked or partially pasted token |
