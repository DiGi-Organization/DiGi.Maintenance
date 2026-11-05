---
name: github-workspace-setup
description: "Use when setting up a new machine or changing the local GitHub folder layout - one folder per GitHub owner (DiGi, DigiProject, ZiolkowskiJakub), Scripts/SetupWorkspace.ps1, restoring user files/, migrating from the pre-2026-10-14 layout, and the WIKI_SYNC_PAT wiki sync secret."
---

# GitHub - Workspace Setup

> [!IMPORTANT]
> **Portability Rule:** this file uses relative paths and `%USERPROFILE%`-style placeholders only. Never add an
> absolute user path to it.

How the local GitHub folder is organised, how to set it up on a new machine, and what the
2026-10-14 reorganisation changed.

## 1. Convention: one folder per GitHub owner

Every repository lives in the folder named after the GitHub owner it belongs to, directly under the
GitHub root folder (typically `%USERPROFILE%\GitHub`):

| Local folder | GitHub owner | Contents |
|---|---|---|
| `DiGi\` | [DiGi-Organization](https://github.com/DiGi-Organization) | Every `DiGi.*` library, plus the workspace files (below) |
| `DiGi\templates\` | DiGi-Organization | `DiGi.Template`, `DiGi.WebAPI.GLTF.Template` |
| `DiGi\wiki\` | DiGi-Organization | `<repo>.wiki` clones (on demand, see `GitHub Wiki - General.md`) |
| `DigiProject\` | [DigiProject-Organization](https://github.com/DigiProject-Organization) | Client projects: `bodyplan`, `Uponor`, `TimGreatrexArchitect`, `EtexGroup` |
| `ZiolkowskiJakub\` | [ZiolkowskiJakub](https://github.com/ZiolkowskiJakub) | The personal repositories that are worked on locally |
| `SAM-BIM\` | [SAM-BIM](https://github.com/SAM-BIM) | SAM repositories (managed separately) |

"All DiGi repositories" therefore means every repository directly inside `DiGi\`; the Maintenance scripts
(`DiGi.Maintenance/Scripts/*AllRepos.ps1`, `UpdateAgents.ps1`, `UpdateReadmes.ps1`, `BuildAll.ps1`, ...) treat
the parent of `DiGi.Maintenance` as the workspace root and process its `DiGi.*` folders.

Rules that follow from the layout:

- **DiGi repositories must stay siblings.** Every DiGi project references the others through relative
  `HintPath`s such as `..\..\DiGi.Core\bin\DiGi.Core.dll`, so `DiGi.*` folders never move into sub-folders.
- **Projects outside `DiGi\` reach DiGi through the GitHub root.** From
  `DigiProject\bodyplan\<Folder>\<Project>\<Project>.csproj` a DiGi assembly is
  `..\..\..\..\DiGi\DiGi.Core\bin\DiGi.Core.dll`. bodyplan is the only such project; its other
  cross-folder references follow the same rule: `Scripts\Deploy.ps1` defaults `-Root` to `..\..\..\DiGi`
  (for `DiGi.Maintenance\Scripts` and `DiGi.WebAPI.WindowsService\bin`), `bodyplan.WebAPI.UI.csproj` copies
  `gis-theme.css` from `..\..\..\..\DiGi\DiGi.GIS.WebAPI.UI\`, and `CheckHostDependencies.ps1` finds the
  bodyplan units at `..\DigiProject\bodyplan\` relative to the DiGi workspace.
- **The workspace root (`DiGi\`) holds only AI-app configuration and shared clones:**
  `CLAUDE.md` (Claude Code), `AGENTS.md` (LM Studio Bionic's global preferences - by its own rule for
  Bionic only; the per-repository rules for other agents are `<repo>/.agents/AGENTS.md`),
  `opencode.jsonc` + `.opencode/` (OpenCode), `.claude/` (Claude Code launch configurations and permissions),
  `templates/` and `wiki/`. Reports, dumps and scratch files belong in a repository's git-ignored
  `user files/`, never at the workspace root.
- **The workspace root files are in no repository.** `CLAUDE.md`, `AGENTS.md`, `opencode.jsonc`,
  `.opencode/` and `.claude/` exist only on the machine; cloning does not bring them back (§2.5). `CLAUDE.md`
  is a condensation of `DiGi.Maintenance/documentation/AI Guidelines/` and is re-synced from it.
- **Repositories hosted elsewhere** (for example a Bitbucket clone under `Uponor\`) sit in their own folder
  beside the owner folders and are outside this convention and `SetupWorkspace.ps1`.

## 2. New machine

### 2.1 Prerequisites

- Git for Windows (with Git Bash) and the GitHub CLI.
- `gh auth login` as a member of **both** organizations. Check with
  `gh repo list DiGi-Organization --limit 5` and `gh repo list DigiProject-Organization --limit 5`; if an
  organization restricts OAuth apps, grant the GitHub CLI access to it.
- Visual Studio 2026 and the .NET SDK used by the solutions (`dotnet --list-sdks`).
- PowerShell 7 (`pwsh`) to run the Maintenance scripts (`Scripts/SetSecretsAllRepos.ps1` requires it).
- Only for organization settings and secrets (§5): `gh auth refresh -h github.com -s admin:org`.

### 2.2 Clone everything

Get `SetupWorkspace.ps1` either by cloning DiGi.Maintenance first or by downloading the script on its own,
then run it with the GitHub root:

```powershell
New-Item -ItemType Directory "$env:USERPROFILE\GitHub\DiGi" -Force | Out-Null
git clone https://github.com/DiGi-Organization/DiGi.Maintenance.git "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance"
& "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance\Scripts\SetupWorkspace.ps1" -WhatIf
& "$env:USERPROFILE\GitHub\DiGi\DiGi.Maintenance\Scripts\SetupWorkspace.ps1"
```

`SetupWorkspace.ps1` creates the owner folders and clones every repository of both organizations (the two
templates into `DiGi\templates\`) plus the personal repositories listed in `$personalRepositories` inside the
script. It never re-clones an existing folder, so it is safe to re-run after a new repository is created on
GitHub. Options:

| Parameter | Effect |
|---|---|
| `-WhatIf` | Prints what would be cloned or changed, touches nothing |
| `-IncludeWikis` | Also clones the wiki of every DiGi repository that has one into `DiGi\wiki\<repo>.wiki` |
| `-UpdateRemotes` | Points `origin` of existing clones (and of existing `DiGi\wiki\*.wiki` clones) at the current owner. Remotes are compared by owner and repository name, so an ssh remote or one without `.git` is left alone when it already names the right repository, and an ssh remote stays ssh when it is rewritten |
| `-Only <names>` | Restricts the run to the named repositories (owner folders with nothing to clone are not created) |
| `-Root <path>` | GitHub root folder; defaults to the parent of the `DiGi` folder the script runs from, or to the current directory when the script is not inside a `DiGi` workspace |

Then check out the newest version branch in every repository - see
`GitHub - Branch Pull.md` (`Scripts/PullBranchesAllRepos.ps1`).

### 2.3 Restore the git-ignored `user files/`

Connection strings, API keys and machine-specific paths live in git-ignored `user files/` folders and are
**not** cloned. Restore the DiGi ones from the backup made with `Scripts/CopyUserFiles.ps1`:

1. Copy `DiGi.Maintenance/files/Directories.conf` to `DiGi.Maintenance/user files/Directories.conf` and set
   `USER_FILES_BACKUP_DIRECTORY` (and `SOFTWARE_DIRECTORY` if this machine deploys).
2. Run `Scripts/CopyUserFiles.ps1 -Restore`.

`CopyUserFiles.ps1` covers only the DiGi workspace. The project repositories' `user files/` (bodyplan's,
below) have to be backed up and copied separately.

Without a backup, recreate the files by hand. The ones in use:

| Repository | `user files/` |
|---|---|
| DiGi.Maintenance | `Directories.conf`, `GitHub.conf` (`URL` = `https://github.com/DiGi-Organization`; its token needs access to the organization) |
| DiGi.GIS.PostgreSQL, DiGi.GIS.UI | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Storage.conf` |
| DiGi.GIS.PostgreSQL.UI | the two above, `GIS_WebAPI_Client.conf`, `User_PostgreSQL_Main.conf` |
| DiGi.GIS.WebAPI | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Storage.conf`, `GIS_WebAPI.conf` |
| DiGi.GIS.YOLO.UI | `GIS_WebAPI_Client.conf`, `YearBuiltPredictionPipelineOptions*.json` |
| DiGi.User.PostgreSQL, DiGi.User.WebAPI | `User_PostgreSQL_Main.conf` |
| DiGi.WebAPI, DiGi.WebAPI.WindowsService | `WebAPI_Diagnostics.conf` |
| DiGi.Test | `GIS_PostgreSQL_Main.conf`, `GIS_PostgreSQL_Main_Test.conf`, `GIS_PostgreSQL_Storage_Test.conf`, `User_PostgreSQL_Main.conf`, `PostgreSQL_Table.conf`, `PostgreSQL_UniqueReference.conf`, `PostgreSQL_PartitionReference.conf`, `PostgreSQL_PartitionUniqueReference.conf`, `DiGi.YOLO_Preflight.conf`, `DiGi.YOLO.ONNX_Parity.conf`. A database fact connects through its own `*_Test.conf`, which must never name a production database (`AI Guidelines/Coding - PostgreSQL.md` §6) |
| DigiProject\bodyplan | `user files/`: `Directories.conf` (`SOFTWARE_DIRECTORY` for `Scripts\Deploy.ps1`), `Bodyplan_PostgreSQL_Main.conf`, `Bodyplan_PostgreSQL_Test.conf`, `Bodyplan_WebAPI.conf`; `UI/user files/`: `Bodyplan_WebAPI_UI.conf` |

### 2.4 Build

Build in dependency order with `Scripts/BuildAll.ps1` (it starts from `DiGi.Core`); a library must be built
before anything that references it through a `HintPath` (`Coding - General.md` §4).

### 2.5 AI apps

**Copy the workspace root files from the old machine** (or a backup) into `DiGi\` - they are in no
repository: `CLAUDE.md`, `AGENTS.md`, `opencode.jsonc`, `.opencode\agents\`, `.opencode\package.json` and
`.claude\` (`launch.json`, `settings.local.json`). Leave `.opencode\node_modules` behind and reinstall it with
`npm install` inside `.opencode\`.

- **Claude Code:** start sessions in the `DiGi\` folder so `CLAUDE.md` and `.claude/` load automatically.
  Memory and session history are local and keyed by the launch folder:
  `%USERPROFILE%\.claude\projects\<key>\`, where `<key>` is the launch path with every `:`, `\` and `.` turned
  into `-` (`GitHub\DiGi` → `C--Users-<user>-GitHub-DiGi`, `GitHub\DiGi\DiGi.GIS.ML` →
  `C--Users-<user>-GitHub-DiGi-DiGi-GIS-ML`). To keep them, copy those folders from the old machine; a session
  started in another folder does not see them.
- **OpenCode:** `opencode.jsonc` in `DiGi\` loads `CLAUDE.md` and `DiGi.Maintenance/.agents/AGENTS.md`.
- **Per-repository agents:** `.agents/` in every DiGi repository is generated by `Scripts/UpdateAgents.ps1`
  and is committed, so it arrives with the clone.

### 2.6 Check the result

- `SetupWorkspace.ps1 -WhatIf` reports every repository as already present and nothing to change - apart
  from any repository deliberately not kept on that machine, which it lists as "would clone" (it clones
  every repository of both organizations unless `-Only` narrows the run).
- `Scripts/BuildAll.ps1` builds the chain; then build the project repositories (bodyplan last, it references
  DiGi assemblies).
- `dotnet test DiGi.Test\DiGi.Test.slnx --settings DiGi.Test\TestDuration.Short.runsettings` passes; facts
  that need a database or a model skip without one.

## 3. Migrating an existing machine (pre-2026-10-14 layout)

Before the reorganisation every repository was owned by `ZiolkowskiJakub` and the DiGi repositories lived in
`GitHub\DigiProject\` together with the project repositories.

1. Close Visual Studio, terminals and anything else with a file open in the workspace. Stop the git
   filesystem monitors, which keep watch handles on working trees, by running
   `git -C <repo> fsmonitor--daemon stop` in each repository.
2. Rename `GitHub\DigiProject` to `GitHub\DiGi`.
3. Create `GitHub\DigiProject` and move `bodyplan`, `Uponor` and `TimGreatrexArchitect` into it. Create
   `GitHub\ZiolkowskiJakub` and move the personal repositories into it.
4. Pull `GitHub\DiGi\DiGi.Maintenance` (`main`) first: an older checkout has no `SetupWorkspace.ps1`. The old
   `origin` still works through GitHub's redirect.
5. Run `SetupWorkspace.ps1 -UpdateRemotes` from `GitHub\DiGi\DiGi.Maintenance\Scripts`. It points every
   `origin` at the new owner and clones the repositories that are missing (EtexGroup and the DiGi repositories
   that were never cloned).
6. Pull every repository (`Scripts/PullBranchesAllRepos.ps1` for the DiGi ones, `git pull` in each project
   repository). The commits that repointed bodyplan at `GitHub\DiGi` (HintPaths, theme copy, `Deploy.ps1`)
   and replaced the owner in every link and workflow are on the branches that were current on 2026-10-14.
7. Fix the local, git-ignored configuration: `DiGi.Maintenance/user files/GitHub.conf` `URL` (=
   `https://github.com/DiGi-Organization`), and any personal tool configuration that names
   `GitHub\DigiProject\DiGi...` paths.
8. Claude Code keeps memory and history per launch folder (§2.5), so the move orphans them:
   - copy `%USERPROFILE%\.claude\projects\C--Users-<user>-GitHub\memory\` (sessions started in `GitHub`) and/or
     the contents of `...\C--Users-<user>-GitHub-DigiProject\` (sessions started in the old workspace root)
     into `...\C--Users-<user>-GitHub-DiGi\`;
   - rename every `C--Users-<user>-GitHub-DigiProject-DiGi-*` folder to `C--Users-<user>-GitHub-DiGi-DiGi-*`.
     The `...-GitHub-DigiProject-bodyplan` / `-Uponor` folders keep their names - those paths did not change;
   - move launch configurations and permission rules that name `DigiProject/DiGi.*` from a `GitHub\.claude\`
     into `GitHub\DiGi\.claude\`, with the paths made relative to `DiGi\`.
9. Machine-local references to the old paths: shortcuts, Windows scheduled tasks, startup entries or services
   that run something from `GitHub\DigiProject\DiGi.*\bin` (for example the GIS PostgreSQL tray application
   started from its repository bin). Visual Studio's `.vs\` folders keep the old absolute paths in their
   layout files; they are harmless and rebuilt, or delete them.
10. Check the result as in §2.6, and run `Scripts/CheckHostDependencies.ps1` once - it reports a missing output
    folder when a path it expects is wrong.

## 4. What the 2026-10-14 reorganisation changed

| Change | Detail |
|---|---|
| Repositories transferred | 73 `DiGi.*` repositories → DiGi-Organization; `bodyplan`, `Uponor`, `TimGreatrexArchitect`, `EtexGroup` → DigiProject-Organization. Everything else stayed on `ZiolkowskiJakub`. |
| Preserved by GitHub | Issues, pull requests, wikis, stars, Actions secrets (`WIKI_SYNC_PAT`), issue dependencies and assignees. Old `github.com/ZiolkowskiJakub/<repo>` URLs redirect for the web and for git, until a repository of the same name is created on the personal account again. |
| Local layout | `GitHub\DigiProject` (which held the DiGi repositories) renamed to `GitHub\DiGi`; project repositories moved to a new `GitHub\DigiProject`; personal ones to `GitHub\ZiolkowskiJakub`. |
| References | Owner replaced in every link, issue reference and workflow (`ZiolkowskiJakub/DiGi.*` → `DiGi-Organization/DiGi.*`). Every repository's `sync-wiki.yml` - and the templates that write it (`GitHub Actions/sync-wiki-template.yml`, `ApplyDocumentationSetup.ps1`, `SyncWorkflowToMain.ps1`) - checks out `${{ github.repository_owner }}/DiGi.Maintenance`, so the workflow never names an owner. The Maintenance scripts' owner fallback is `DiGi-Organization`. The default issue assignee is still `ZiolkowskiJakub`. |
| Paths | `DigiProject/...` workspace paths in guidelines, generated skills and READMEs → `DiGi/...`; absolute script header comments removed; `bodyplan` HintPaths and theme copy → `..\..\..\..\DiGi\`, bodyplan `Deploy.ps1 -Root` → `..\..\..\DiGi`, bodyplan units in `CheckHostDependencies.ps1` → `..\DigiProject\bodyplan\`. |
| Wiki sync secret | The per-repository `WIKI_SYNC_PAT` copies were replaced by one **organization** secret with a new token (see §5). |
| Cleanup | Leftover task output removed from the workspace root. `DiGi.Test/DiGi.GIS.WebAPI.xUnit` no longer copies `DiGi.Test\user files` (database confs and reports) into `DiGi\bin\user files` on every build - its facts read the folder directly. |
| New tooling | `Scripts/SetupWorkspace.ps1` and this document. |

Not covered by the reorganisation, still to check:

- **Claude Code cloud environment:** paste the updated `documentation/Claude Cloud Enviroment Script.txt` (one level above this file)
  into the environment settings on claude.ai (the old clone URL keeps working through the redirect meanwhile).

## 5. Wiki sync secret (`WIKI_SYNC_PAT`)

Every DiGi repository's `sync-wiki.yml` pushes the generated API pages (`documentation/API/`) to the
repository's wiki on a push to `main`/`master`, authenticating with
`${{ secrets.WIKI_SYNC_PAT || secrets.GITHUB_TOKEN }}`. `GITHUB_TOKEN` cannot push to a wiki, so the
secret is required.

- **One organization secret.** `WIKI_SYNC_PAT` is a DiGi-Organization Actions secret with visibility
  *all*. Repositories hold no copy of their own: a repository-level secret would override the organization
  one and keep failing after the token is renewed. A new repository needs nothing.
- **The token** is a classic personal access token with the `public_repo` scope (40 characters, `ghp_...`).
  Every DiGi repository with a wiki is public, and on GitHub Free an organization secret does not reach
  private repositories anyway. It has an expiry date: when it lapses, every wiki push fails with
  *Invalid username or token*.
- **Renewing it:** regenerate the token on GitHub, copy it with the copy button, then run
  `Scripts/SetSecretsAllRepos.ps1 -FromClipboard` (needs `gh auth refresh -h github.com -s admin:org`). The
  script checks the token with the GitHub API and refuses to store one GitHub does not accept - a partially
  pasted value fails exactly like an expired one. `-RemoveRepositorySecrets` deletes stale repository-level
  copies.
- **A new repository's wiki** exists only after its first page is created in the GitHub web UI (*Wiki* tab
  → *Create the first page*). Until then its `main` wiki sync fails with *Repository not found*.

Symptoms and causes:

| Error in the *Run Wiki Sync Script* step | Cause |
|---|---|
| `Repository not found` on clone | The wiki has no first page yet |
| `Permission to ... denied to github-actions[bot]` (403) | No `WIKI_SYNC_PAT` reached the job, so `GITHUB_TOKEN` was used |
| `Invalid username or token` | The secret's value is not a valid token (expired, revoked or pasted incompletely) |
