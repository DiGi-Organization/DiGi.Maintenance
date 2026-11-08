<#
.SYNOPSIS
    Regenerates the '.agents' rules and skills of every DiGi repository from the canonical AI Guidelines.

.DESCRIPTION
    1. Copies 'DiGi.Maintenance/.agents/AGENTS.md' (the reference rules file) into every 'DiGi.*' repository.
    2. Turns every guideline in 'DiGi.Maintenance/documentation/AI Guidelines' (except README.md) into a
       '.agents/skills/<skill-name>/SKILL.md' with YAML frontmatter.
    3. Optionally refreshes an external, machine-global AGENTS.md whose path is configured as
       GLOBAL_AGENTS_FILE in 'user files/Directories.conf'. Everything up to and including the
       '## Summary of Core Coding & Testing Guidelines' heading is preserved; the compiled guidelines follow.
    4. Commits the change in every repository that has a .git directory, unless -NoCommit is specified.

    All generated files are written as UTF-8 without BOM using CRLF line endings.

.PARAMETER NoCommit
    If specified, files are updated but no git commit is created.

.PARAMETER Message
    Commit message used when committing updated '.agents' folders.
#>
param (
    [switch]$NoCommit,

    [string]$Message = "Sync rules and skills (.agents) with latest AI Guidelines"
)

$ErrorActionPreference = "Stop"

# Workspace root, resolved relative to this script
$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path
Write-Host "Base directory resolved to: $baseDir" -ForegroundColor Cyan

$guidelinesDir = Join-Path $baseDir "DiGi.Maintenance\documentation\AI Guidelines"
$referenceAgentsFile = Join-Path $baseDir "DiGi.Maintenance\.agents\AGENTS.md"

if (-not (Test-Path $guidelinesDir)) {
    Write-Error "AI Guidelines directory not found: $guidelinesDir"
    exit 1
}

if (-not (Test-Path $referenceAgentsFile)) {
    Write-Error "Reference AGENTS.md not found at: $referenceAgentsFile"
    exit 1
}

# Pre-flight guard: fail when a source file carries a stray '\r\r\n' line ending. Without
# this, the sync below would silently propagate the sequence into every generated file
# (see 'GitHub - Issues.md' section 1 - the \r\r\n trap).
$guardFiles = @(Get-ChildItem -Path $guidelinesDir -Filter "*.md" | ForEach-Object { $_.FullName })
$guardFiles += $referenceAgentsFile
$guardFiles += Join-Path $baseDir "DiGi.Maintenance\README.md"
$guardFiles += Join-Path $baseDir "DiGi.Maintenance\files\README - Coding Guidelines.md"
$corrupted = @()
foreach ($guardFile in $guardFiles) {
    if (-not (Test-Path $guardFile)) {
        continue
    }
    if ([System.IO.File]::ReadAllText($guardFile).Contains("`r`r`n")) {
        $corrupted += $guardFile
    }
}
if ($corrupted.Count -gt 0) {
    Write-Host "Stray '\r\r\n' line endings detected in:" -ForegroundColor Red
    foreach ($corruptedFile in $corrupted) {
        Write-Host "  - $corruptedFile" -ForegroundColor Yellow
    }
    Write-Error "Fix the files above (byte-level '\r\r\n' -> '\r\n' replacement) before syncing."
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-TextFile {
    param (
        [string]$Path,
        [string]$Text
    )

    # Strip every CR first: a CRLF -> LF step leaves a stray '\r' from '\r\r\n' behind,
    # which the LF -> CRLF step then re-doubles - the round-trip is the identity on '\r\r\n'.
    $normalizedText = ($Text -replace "`r", "").TrimEnd("`n") + "`n"
    $normalizedText = $normalizedText -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($Path, $normalizedText, (New-Object System.Text.UTF8Encoding($false)))
}

# Description shown in the SKILL.md frontmatter, keyed by generated skill name
$descriptions = @{
    "coding-automatic-tests"         = "Use when writing or adding xUnit facts - Facts partial class layout, shared fixtures in DiGi.Test/files/, reports in DiGi.Test/user files/reports/, building the changed library before dotnet test (HintPath means it never rebuilds), Short/Medium/Long duration attributes and DIGI_TEST_MAX_DURATION, culture-scoped key facts, reproducing a defect before fixing it, proving a guard can fail, database facts on their own *_Test.conf that restore what they write, phantom Test Explorer entries."
    "coding-background-tasks"        = "Use when writing or changing a tray-application background task (DiGi.GIS.PostgreSQL.UI) - PostgreSQL<X>Task : ReportableBackgroundTask<long>, options property named after its type, an Error log before every return false, progress and cancellation, the UI<Task> wrapper showing its options window inside Dispatcher.Invoke on a copy, registration in Create.VisualBackgroundTasks, client <Type>sPostTask uploads with CountyIds."
    "coding-browser-testing"         = "Use when verifying interactive front-end behaviour in a real browser - Playwright (Python) driving an installed Chromium browser to test toggles, drag-resize clamps, keyboard, localStorage, responsive and phone (375x812) layouts, and rendered output by screenshot statistics and GPU timer queries rather than state flags; the hidden attribute losing to a display rule. Confirm the toolchain on this machine first; run with the host shell, never a sandbox."
    "coding-computesharp"            = "Use when writing or changing a ComputeSharp IComputeShader (DiGi.ComputeSharp) - constant buffer layout (12-byte header, free slot at offset 12, declaration order is layout order), the NVIDIA defect where an odd root constant count with an odd resource count silently corrupts doubles (reorder or pad, never drop a resource), the layout guard and parity facts, GPU fact conventions, probing a suspected driver defect."
    "coding-deployed-webapi"         = "Use when checking a change against the live WebAPI at api.digiproject.uk or deciding which server runs what - per-prefix Swagger documents (fetch one operation, not the full document), the deployed build lagging the repository (commit hash in InformationalVersion), the county-reference-building GET recipe, sequential querying, cold-partition timeouts, CRLF id lists giving 000, the database server vs web server vs development machines and where each log lives. Manual curl only, never DiGi.Test."
    "coding-general"                 = "Use whenever writing or editing C# in this workspace - English, no var, type-prefixed naming (acronyms lowercase only the first letter), <= 7 parameters on one line, CancellationToken last with named arguments after skipped defaults, the Query/Modify/Create/Convert architecture, cheap constructors with Create factories, one member per file, enums, constants, tolerances, files vs user files, Serilog.Modify.Log templates, the cancellation catch filter, TODO [Marker] temporary code, same-named extension and name-binding traps."
    "coding-geometry"                = "Use when orienting, closing, triangulating, hashing or sweeping DiGi.Geometry / DiGi.Solar geometry - SunDirection points away from the sun (negate before dotting), Vector3D.Unit is never null, no cosine via Angle, asymmetric orientation fixtures, IsClosed is not monotonic in tolerance, sub-tolerance corners before Triangulate, NetTopologySuite triangulators, rounded and sequentially mixed hash keys, PolygonalFace2DPointRelationSolver for point sweeps."
    "coding-gis-administrative-data" = "Use when touching administrative_areal_2d, building_2d or anything keyed by a county code or id - a code is not a key (406 polygon parts for 380 counties, never deduplicate them), the key-resolution matrix and mandatory ORDER BY, countyids writes resolved per item, fallbackByReference: true on reads, pruning spatial reads by every sibling part, building_data fill rate vs usable data, PRG address points, the nested Subdivision layer (smallest container, never a sum)."
    "coding-grasshopper"             = "Use when writing or changing a Grasshopper/Rhino plug-in component (DiGi.*.Rhino) - VariableParameterComponent anatomy, a fixed ComponentGuid that never changes, name-based Params.IndexOfInputParam lookups (a typo silently returns -1), Goo and Param pairs per file, Inspect methods, RhinoInfo, and the .csproj (Grasshopper IncludeAssets compile;build, OutputPath ..\bin, .gha copy)."
    "coding-host-dependencies"       = "Use when adding a NuGet package, when a deployed host throws FileNotFoundException or delivers a partial result, or on a CS0012/CS0246 build wall - HintPath references drop transitive packages (re-declare them on the host at the same version), checking the already-referenced package and its runtime variant first, extension hosts as one probing set, a stale deps.json after a library reference change, CheckHostDependencies.ps1, rebuilding every consumer after a public-surface change."
    "coding-laya"                    = "Use when working on the Laya decision model (DiGi.Python, DiGi.Laya, consumers) - checkpoint identity by DirectorySHA256 of the whole folder (never write inside a checkpoint), training outside the workspace, mandatory fine-tune and calibration, releasing to LAYA_MODELS_DIRECTORY and deploying with DeployLaya.ps1 (allowlist, manifest, -Remove only), the host venv from InstallPythonEnvironment.ps1 outside the synced directory."
    "coding-performance"             = "Use when optimizing code or measuring it - no caching unless the request allows it, benchmark facts measured in isolation (in-suite figures are not comparable), warm-up and ranges, A/B against a real baseline with both sides on the intended binary (Debug/Release, harness dll copies, cp/mv mtimes), parity tests bounded by a percentile plus an invariant, and the wiki Benchmark.md page format."
    "coding-postgresql"              = "Use when writing Npgsql/PostgreSQL code - converters and idempotent DDL, NULLS NOT DISTINCT keys, batching with ANY(@array), commandTimeout and tokens actually forwarded, no IS NULL OR optional filters on partitioned tables, disposing connections a method creates, one reader per connection, whitelisted identifiers, physical-order ctid walks, NULL meaning unknown, missing tables answering null, production only through the API, *_Test.conf databases, Main vs Storage."
    "coding-postgresql-distributed-queue-processing" = "Use when designing or maintaining a distributed claim/acknowledge update queue in PostgreSQL - schema (claimed_at, attempts DEFAULT 0, natural uniqueness by county part), DDL on every path, the parenthesised FOR UPDATE SKIP LOCKED claim ordered to its index, lease longer than the slowest batch, acknowledging only stored work (idempotent target or owner-checked), re-enqueue during a claim, poison-row retirement, read-only observation, coverage measured on the target."
    "coding-project-setup"           = "Use when creating a project or repository from templates/ or changing build configuration - the GitHub-created .gitignore that leaks user files, the new-repository checklist (labels, BuildAll order, version branch), Directory.Build.props (LangVersion latest, latest-recommended analyzers) and the behavior-preserving analyzer fixes and site suppressions, .editorconfig from the template (overrides only under [*.cs], never above the first section), Solution Items, Roslyn analyzer project split (DIGI0001)."
    "coding-references"              = "Use when comparing, matching, keying or de-duplicating an IReference/IUniqueReference - == between two interface-typed references is a silent reference comparison, use Core.Query.Equals, accessors clone per call, and how to detect and fix existing occurrences."
    "coding-serialization"           = "Use when creating or changing a SerializableObject type or a *Options class, or debugging a JSON round trip - marker interfaces, readonly [JsonInclude] fields with nameof, the three constructors, DateTimeOffset, JsonValue kinds, serializer traps (document-order setters, name collisions, base private set, dictionaries, byte[] arrays, Clone is a JSON round trip), mutable options, SerializationCheck plus a direct copy-constructor assertion."
    "coding-webapi-contracts"        = "Use when changing a WebAPI route, parameter, controller or extension, or writing an HTTP client of one - renamed query parameters break clients silently, omitted parameters keep default(T), enum sentinels and integers on the wire, camelCase JSON bodies, /Query client plumbing, failures named by status (503/502) never read as empty, timeout layering, Modify.InitializeAsync entry point, one public constructor, Content(...) instead of Ok(x), no [Produces] over string errors."
    "coding-webapi-gltf"             = "Use when building or extending a Web API on the DiGi.GLTF 3D framework - the pipeline, onboarding a consumer, IGLTFNodeConverter in WORLD coordinates, batched payloads, gltf-viewer-core.js edited only in DiGi.GLTF.WebAPI and committed in both repositories, live marquee selection, and what the payload does not carry (no normals, winding, shadow contract)."
    "coding-webapi-simple-authorization" = "Use when implementing or auditing API-key tiered authorization on a WebAPI - deny by default, [Feature]Configuration with an Open escape hatch, fail-closed factory, constant-time IsAuthorized, the key in a request header, singleton registration, a second gate indistinguishable from the first, what a .NET 7+ WebApplication inserts ([Authorize] without a scheme answers 500), committed defaults vs secrets, deny-branch facts."
    "coding-wpf-deferred-loading"    = "Use when a WPF window or dialog needs slow data, or when verifying WPF layout without its host - open at once, read from the constructor without awaiting, bottom-left progress bar and status label, refresh in place, cancel and dispose on Closed (OK included; the server keeps running until commandtimeout, DiGi.GIS.WebAPI#77), no ConfigureAwait(false) in the window, null means unknown, STA facts with a DispatcherSynchronizationContext, the off-screen render harness."
    "coding-yolo"                    = "Use when working on the YOLO Year Built detector (DiGi.YOLO, DiGi.GIS.YOLO.UI and its runner) - model.pt path resolution and SHA-256, the first-confident-detection predictor, training data and scratch outside the workspace (never in user files/), chunked scratch folders and score-only runs reading results.bbrf, deploying the runner extension from an allowlist (only model.pt)."
    "github-branches-and-commits"    = "Use before the first edit and before every commit in a DiGi repository - commit on the active version branch (no branch, worktree or PR unless asked), git branch --show-current and git pull --ff-only, the pre-commit sweep that keeps plan/scratch *.md out, push only when asked, deleting the plan when its issue closes, pulling every repo to its highest SemVer branch; the version bump / release workflow runs ONLY on an explicit user request."
    "github-issues"                  = "Use when creating, editing, commenting on, filtering or closing GitHub issues - --body-file with UTF-8 LF bodies, the \r\r\n table trap and PowerShell decoding corruption (edit through a Python script), GraphQL revision recovery, mandatory labels and default assignee ZiolkowskiJakub, verifying an issue's premises before implementing it, resolution comments with production runs as follow-up issues, FilterIssues.ps1, blocked_by dependencies."
    "github-labels"                  = "Use when applying or syncing GitHub labels or choosing an issue's mandatory 'ai: *' tier - the 21-label Type/Priority/Status/AI taxonomy, Type + Priority + one ai tier on every new issue, open issues only by default, the tier criteria and capability bands (err higher for core abstractions), SyncLabelsAllRepos.ps1."
    "github-sub-issues"              = "Use when creating sub-issues or sub-tasks for a feature - the tracking-issue pattern: a parent with the shared spec, a Sub-issues table in dependency order and end-to-end acceptance, one self-contained sub-issue per repository opening with its Context sentence, sibling order as blocked_by dependencies (canonical example DiGi.GIS.PostgreSQL #83)."
    "github-wiki"                    = "Use when editing a GitHub wiki page or a wiki Home.md - wiki clones under DiGi/wiki/ on master, generated API pages never hand-edited, the CI sync, linking every page from Home, the five Home blocks and the SyncWiki.ps1 parser rules."
    "github-workspace-setup"         = "Use when setting up a new machine or changing the local GitHub folder layout - one folder per owner (DiGi, DigiProject, ZiolkowskiJakub), SetupWorkspace.ps1, restoring user files/ (CopyUserFiles.ps1 -Reverse), AI-app root files, migrating from the pre-2026-10-14 layout, the WIKI_SYNC_PAT organization secret."
    "maintenance-ai-guidelines-propagation" = "Use when adding, splitting, merging, renaming or removing an AI Guideline, or regenerating .agents/skills - one file per task trigger, stable section anchors cited from code, the five hand-synced targets (`$descriptions, .agents/AGENTS.md, the AI Guidelines README, files/README - Coding Guidelines.md, DiGi/CLAUDE.md), description conventions, the \r\r\n guard, what UpdateAgents.ps1 deletes and rewrites."
    "maintenance-scripts"            = "Use when running or writing DiGi.Maintenance scripts or making scripted/bulk file edits - `$PSScriptRoot paths, non-uniform exit codes (0/1/2 for new scripts), user files/*.conf keys, *AllRepos sweeps and the -NoCommit dry-run trap, BuildAll's hard-coded order, Deploy/SyncDirectory semantics, editing bytes not lines, the autocrlf add flag deciding the stored line ending, checking diffs for unexpected deletions."
    "xml-documentation"              = "Use when reading a type's public API (documentation/API/ before .cs), adding missing XML doc comments, or auditing existing ones against current signatures - every public member documented, params in signature order, one summary, no blank lines (<para>), no docs on partial declarations, full summaries on overrides, issue citations."
}

# Guideline files, in a stable order (README.md is an index, not a guideline)
$guidelineFiles = Get-ChildItem -Path $guidelinesDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name

# Refresh the external machine-global AGENTS.md, if one is configured
$confPath = Join-Path $PSScriptRoot "..\user files\Directories.conf"
$globalAgentsPath = ""

if (Test-Path $confPath) {
    foreach ($line in Get-Content $confPath) {
        $line = $line.Trim()
        if ($line.StartsWith("#") -or $line -eq "") { continue }
        $index = $line.IndexOf("=")
        if ($index -lt 0) { continue }
        $key = $line.Substring(0, $index).Trim()
        if ($key -ne "GLOBAL_AGENTS_FILE") { continue }
        $globalAgentsPath = $line.Substring($index + 1).Trim().Trim('"')
    }
}

if ($globalAgentsPath -eq "") {
    Write-Host "GLOBAL_AGENTS_FILE is not configured in 'user files/Directories.conf' - skipping global AGENTS.md." -ForegroundColor DarkGray
} elseif (-not (Test-Path $globalAgentsPath)) {
    Write-Warning "Global AGENTS.md not found at: $globalAgentsPath"
} else {
    Write-Host "Updating global AGENTS.md: $globalAgentsPath" -ForegroundColor Yellow

    $headerLines = @()
    foreach ($line in Get-Content $globalAgentsPath) {
        $headerLines += $line
        if ($line -match '## Summary of Core Coding & Testing Guidelines') {
            break
        }
    }

    $compiledSections = @()
    foreach ($guidelineFile in $guidelineFiles) {
        $compiledSections += "<!-- Source: $($guidelineFile.Name) -->`n`n" + ([System.IO.File]::ReadAllText($guidelineFile.FullName)).TrimEnd()
    }

    Write-TextFile -Path $globalAgentsPath -Text (($headerLines -join "`n") + "`n`n" + ($compiledSections -join "`n`n---`n`n"))
    Write-Host "Global AGENTS.md updated successfully." -ForegroundColor Green
}

$referenceAgentsText = [System.IO.File]::ReadAllText($referenceAgentsFile)

$targetDirectories = Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*"

foreach ($dir in $targetDirectories) {
    $dirPath = $dir.FullName
    $dirName = $dir.Name
    $agentsDir = Join-Path $dirPath ".agents"
    $skillsDir = Join-Path $agentsDir "skills"

    Write-Host "Processing repository: $dirName" -ForegroundColor Cyan

    if (-not (Test-Path $agentsDir)) {
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
    }

    # Clean up legacy folders directly under .agents that are not 'skills'
    Get-ChildItem -Path $agentsDir -Directory | Where-Object { $_.Name -ne "skills" } | ForEach-Object {
        Write-Host "    Cleaning up legacy folder: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item $_.FullName -Recurse -Force
    }

    # Re-create/clean skills folder so removed guidelines do not leave stale skills behind
    if (Test-Path $skillsDir) {
        Remove-Item $skillsDir -Recurse -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $agentsDir "AGENTS.md") -Text $referenceAgentsText

    foreach ($guidelineFile in $guidelineFiles) {
        # 'Coding - Deployed WebAPI.md' -> 'coding-deployed-webapi'
        $skillName = ($guidelineFile.BaseName -replace '\s+-\s+', '-' -replace '\s+', '-').ToLower()

        $description = $descriptions[$skillName]
        if (-not $description) {
            Write-Warning "No description registered for skill '$skillName' - using a generic one."
            $description = "Use for tasks related to $skillName."
        }

        $skillFolder = Join-Path $skillsDir $skillName
        New-Item -ItemType Directory -Path $skillFolder -Force | Out-Null

        # YAML frontmatter: emit the description as a double-quoted scalar with proper escaping,
        # because the plain-scalar form is invalid when the text contains ': ' (e.g. "'ai: *'")
        # or lossy when it contains ' #' (parsed as a comment) or starts with a special character.
        $yamlBackslash = [string][char]92
        $yamlQuote = [string][char]34
        # Escape for a double-quoted YAML scalar: double every backslash, then prefix every quote with one backslash.
        $yamlDescription = $description.Replace($yamlBackslash, $yamlBackslash + $yamlBackslash).Replace($yamlQuote, $yamlBackslash + $yamlQuote)
        $skillText = "---`nname: $skillName`ndescription: `"$yamlDescription`"`n---`n`n" + [System.IO.File]::ReadAllText($guidelineFile.FullName)
        Write-TextFile -Path (Join-Path $skillFolder "SKILL.md") -Text $skillText
    }

    if ($NoCommit) {
        continue
    }

    $gitDir = Join-Path $dirPath ".git"
    if (-not (Test-Path $gitDir)) {
        continue
    }

    Push-Location $dirPath
    $status = git status --porcelain .agents
    if ($status) {
        Write-Host "    Committing updated rules and skills in: $dirName" -ForegroundColor Cyan
        # '-c core.autocrlf=false' keeps the CRLF bytes in the committed blob (repo convention)
        # and avoids a whole-file line-ending diff when the machine has core.autocrlf=true.
        git -c core.autocrlf=false add .agents
        git commit -m $Message | Out-Null
    } else {
        Write-Host "    No changes in .agents for: $dirName" -ForegroundColor Gray
    }
    Pop-Location
}

Write-Host "`nSynchronization complete!" -ForegroundColor Green
