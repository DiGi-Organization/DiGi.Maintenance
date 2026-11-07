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
# (see 'GitHub - Issues.md' - Line Endings, \r\r\n Translation & Markdown Table Integrity).
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
    "coding-api-documentation"       = "Use when looking up a type's public API - consult the generated documentation/API/ markdown before opening .cs source to check signatures, namespaces, or <summary> descriptions."
    "coding-automatic-tests"         = "Use when writing or adding xUnit tests for C# classes, structs, or extension methods - Facts partial class structure, naming, shared test-data fixtures in DiGi.Test/files/, test reports and diagnostic dumps written to DiGi.Test/user files/reports/, and serialization, tolerance-boundary, and performance test patterns. Also covers measuring a benchmark Fact in isolation (a figure read off a full-suite run is contaminated by xUnit parallel collections and is not comparable to an isolated one), opening a defect fix with a Fact that reproduces the reported symptom on the unmodified code, and proving a kept fallback unreachable before deleting it. Also covers making sure both sides of an A/B ran the intended binary (a Debug/Release mismatch in bin, a scratch harness copying its HintPath dll at its own build time, a cp/mv-restored file keeping its old mtime so the incremental build skips it - build --no-incremental then dotnet test --no-build), asymmetric fixtures for orientation facts (a rectangle mirrors onto itself), phantom Test Explorer entries persisted in .vs/.../TestStore after a rename, and the WPF off-screen render harness (Measure/Arrange/RenderTargetBitmap, pump the dispatcher, walk the visual tree rather than only screenshotting)."
    "coding-computesharp"            = "Use when writing or changing a ComputeSharp IComputeShader struct (DiGi.ComputeSharp) - how ComputeSharp 3.2 lays out the constant buffer (12-byte dispatch header, free 4-byte slot at offset 12, declaration order is layout order) and how to read ConstantBufferSize without a GPU, the NVIDIA RTX 5090 defect where an odd root constant count combined with an odd resource count silently corrupts double-precision results (fix by reordering or padding fields, never by dropping a resource), the ComputeShader_ConstantBufferLayout guard fact and cell-for-cell parity facts required for any layout change, GPU fact conventions (device gate, FP64 exception, non-vacuous hit/miss mix), and probing a suspected GPU defect (WARP on a reduced shader, dxc -dumpbin DXIL diff, echo-then-bisect, debug layer, mutation-test mtime trap)."
    "coding-yolo"                    = "Use when working on the YOLO Year Built detector (DiGi.YOLO, DiGi.YOLO.ONNX, DiGi.GIS.YOLO.UI and its ConsoleApp runner, the tray's prediction/training tasks) - model.pt path resolution and SHA-256, the first-detection year built predictor (no regressor in the scoring path), keeping training data, alternative weights and training scratch outside the workspace (never in user files/), ScratchDirectory/CleanScratchDirectory and score-only runs reading results.bbrf, and deploying the runner extension from an allowlist (only YOLO\models\model.pt)."
    "coding-laya"                    = "Use when working on the Laya decision model (DiGi.Python, DiGi.Laya and their consumers) - checkpoint identity by DirectorySHA256 of the whole folder (never write a manifest, calibration or training output inside a checkpoint), training outside the workspace, mandatory fine-tune and calibration before trusting thresholds, releasing to LAYA_MODELS_DIRECTORY and deploying with DeployLaya.ps1 (allowlist, manifest skip, calibration side file, -Remove only), and the host venv from InstallPythonEnvironment.ps1 kept outside the synced software directory."
    "coding-browser-testing"         = "Use when verifying interactive front-end behaviour in a real browser instead of only static code inspection - Playwright (Python) driving an installed Chromium-based browser headless (e.g. Microsoft Edge) to test panel toggles, drag-resize with min/max clamps, keyboard operability, localStorage persistence, responsive stacking and shared header/footer collapse, and verifying rendered output by screenshot statistics and GPU timer queries rather than by state flags. Also covers the hidden attribute losing to any author display rule (a transparent overlay still swallowing pointer events; check document.elementFromPoint). Confirm the toolchain on THIS machine first (availability is per-machine), and run with the host shell, never the isolated sandbox."
    "coding-deployed-webapi"         = "Use when verifying a client or server change against the live WebAPI at api.digiproject.uk - swagger as the source of truth (fetch the per-prefix document /swagger/<prefix>/swagger.json, or one operation out of it, rather than the full one to keep context small), the county to reference to building GET test recipe, access rules and gotchas. Adds triage: a uniform 000 from a sweep is a client bug until proven otherwise (CRLF id lists make malformed URLs - normalise and print %{time_total}), and a hung API is told from a UI regression with one /information/health timing call. Manual curl checks only, never added to DiGi.Test."
    "coding-editor-config"           = "Use when configuring, auditing, or enforcing .editorconfig code styles, explicit typing (no var), block-scoped namespaces, collection expressions, target-typed new(), diagnostic severity overrides (ignored above the first [section] header), and Visual Studio 2026 / C# 13/14 formatting rules across DiGi repositories."
    "coding-geometry"                = "Use when orienting, closing, triangulating, hashing or sweeping DiGi.Geometry / DiGi.Solar geometry - SunDirection is a propagation vector (negate before dotting with a normal), Vector3D.Unit never returns null, cosine not via Angle, asymmetric orientation fixtures, IsClosed is not monotonic in tolerance, sub-tolerance corners before Triangulate, spatial hash keys (round, mix sequentially), PolygonalFace2DPointRelationSolver for point sweeps."
    "coding-general"                 = "Use whenever writing or editing C# code in this workspace - naming/typing rules, CancellationToken ordering, member-access simplification, the DiGi.Core Query/Modify/Create/Convert architecture, cheap constructors with validation and normalisation moved into a Create factory, the one-member-per-file layout for Query/Modify/Create and nested types, files vs user files assets, the SerializableObject serialization pattern, the host PackageReference rules for NuGet dependencies that HintPath references drop (a runtime FileNotFoundException that shows up as a partial result, not an error), checking what an already-referenced package exports before adding a new NuGet one (read the package XML docs beside the DLL, and check the target framework the consuming project actually builds for), and TODO [Marker] tags for temporary code including workarounds for defects in another DiGi repository, and the line-ending rules for scripted edits and the commit side (edit bytes, not lines; detect the stored convention from the blob, not the working tree; the autocrlf add-flag direction that decides which bytes land in the blob). Also the name-resolution traps that refuse to compile (an extension cannot reuse a property name on its receiver - CS1955; a method shadows a same-named namespace in expression position - CS0119; Razor views have no enclosing DiGi.* namespace), no caching in an optimization unless the request explicitly allows it, the build-time symptoms of HintPath opacity (CS0012 fixed in the .csproj, a CS0246 wall that vanishes under -m:1, a HintPath probing the whole bin closure), never printing a user files/ conf until the redaction is proven, and the DiGi serializer traps (setters run in JSON document order; same-named members de-duplicate with the derived one winning; a base private set is skipped on derived deserialization; byte[] is a number array; Clone is a JSON round trip)."
    "coding-gis-administrative-data" = "Use when touching administrative_areal_2d, building_2d, or anything keyed by a county code or id - why a county code is not a key (BDOT10k stores one row per polygon part, so 406 county rows cover 380 codes), why those rows must never be deduplicated, the key-resolution matrix and the mandatory ORDER BY on any LIMIT/FirstOrDefault, plus the AdministrativeArealType wire gotchas. Also the nested Subdivision layer (404 of 406 county parts): subdivision_id is the smallest containing subdivision and a per-building key, the buildings of a subdivision are read by its polygon, a municipality is never a sum over nested subdivisions, and a building occupancy share comes from the smallest figured container. Also why a spatial read pruned to an id from a subdivision/code resolve can silently empty (prune by every sibling part sharing the code) and why a building_data fill rate is not usable data (compare the distribution's exact zeros with -Distribution -All)."
    "coding-postgresql"                                     = "Use when designing database schemas or executing queries with Npgsql / PostgreSQL in DiGi solutions - Classes/Converter/ architecture, NULLS NOT DISTINCT composite unique indexes for nullable columns, query batching (batchSize = 1000, ANY(@array)), commandTimeout parameter standard, and connection asset isolation in user files/. Also whole-partition reads of wide tables in physical order with bounded ctid windows (Tid Range Scan, REPEATABLE READ for an exact walk), the Main vs Storage database split (no join across them), running a skipped integration fact with the confs beside the executing assembly, and NULL in a resolved-later column meaning ""unknown"" (filter sources, COALESCE the update, grep every sibling upsert)."
    "coding-postgresql-distributed-queue-processing"         = "Use when designing or maintaining distributed bulk update queues in PostgreSQL - table schema (claimed_at, created_at, natural uniqueness), running the queue DDL from every path that touches the table (TableExistsAsync is column-blind), atomic lease claims with FOR UPDATE SKIP LOCKED ordered to match the composite claim index, native interval arithmetic (@minutes * interval '1 minute'), explicit batch acknowledgment (DELETE ... WHERE id = ANY(@ids)), poison-row retirement with an attempt counter and retirement ceiling, crash recovery, and non-destructive queue observation."
    "coding-references"              = "Use when comparing, matching, keying or de-duplicating an IReference/IUniqueReference - why == between two interface-typed references is a silent bug, what to use instead, and how to detect and fix existing occurrences."
    "coding-templates"               = "Use when creating a new project/solution from a template, or adding/modifying templates in the workspace's default templates/ folder."
    "coding-webapi-contracts"        = "Use when changing a WebAPI controller's route, parameter names or validation, or when writing or maintaining an HTTP client of one - why a renamed query parameter breaks clients with no compile error and no runtime error (ASP.NET silently ignores an unknown parameter and returns the unfiltered result), the binding traps where an omitted parameter keeps default(T) and an enum sentinel that is not 0 makes the obvious guard dead code, sending enum values as integers, the client base-URI constant and /Query plumbing pattern, gating an endpoint that is not deployed yet, and the three controller-side defects (exactly one public constructor - a second one 500s every action via ActivatorUtilities; DiGi objects returned as Content(Core.Convert.ToSystem_String(x), ""application/json"") rather than Ok(x); no action-level [Produces] over string-bodied error paths, where 406 masks the error) plus the timeout layering (PostOptions.Delay 20 s per attempt, HttpClient.Timeout >= server commandtimeout)."
    "coding-webapi-simple-authorization" = "Use when implementing or auditing lightweight API-key-based tiered authorization for WebAPI controllers - deny-by-default IsAuthorized, [Feature]Configuration model with an Open escape hatch, files/*.conf vs user files/ secrets, [FromHeader(Name = ""key"")] binding, constant-time key comparison, singleton registration on the host, MSBuild copy targets, Deploy.ps1 deployment synchronization, and what a .NET 7+ WebApplication actually inserts into the pipeline (authentication/authorization middleware added automatically; [Authorize] without a registered scheme answers 500, not 401; GetService<...>() != null gates are vacuous)."
    "coding-webapi-gltf"             = "Use when building or extending an ASP.NET Core Web API on the DiGi.GLTF 3D framework - the decoupled pipeline, onboarding a new consuming project, adding a 3D object type via IGLTFNodeConverter, batching/streaming performance rules, the rule that gltf-viewer-core.js is edited only in its owner DiGi.GLTF.WebAPI and synced to the consumer (the consumer copy is a build artifact; a fingerprint that does not change means the served file is stale; commit both repositories), box selection highlighting live in both window and crossing directions, and what the batched payload does not carry (no NORMAL attribute, inconsistent winding, on-change shadow map contract)."
    "coding-wpf-deferred-loading"    = "Use when a WPF window or dialog needs data that takes noticeably long to read (over about half a second, or unbounded) - the default mechanism: open at once, start the read from the constructor as a Func<CancellationToken, Task<T?>> without awaiting it, show a status label plus an indeterminate progress bar in the bottom-left corner of the button row, apply the result through a public Set method that refreshes items in place (selection and scroll kept), cancel and dispose the token source on Closed (raised by OK too), hide the bar in finally, and what a close before the data arrives does end to end (the controller must pass its CancellationToken to the converter or the server query runs on; throttled batches keep the SemaphoreSlim alive across Task.WhenAll). Also the traps: no ConfigureAwait(false) in the window (cross-thread exception), never read inside Dispatcher.Invoke or before ShowDialog, null means unknown and never an empty answer, the Query read returns null on every failure and bounds itself with a linked CancelAfter equal to the server commandtimeout, and the STA facts for no-read/pending/completed/failed reads plus the closed-before-data fact (install a DispatcherSynchronizationContext, Close, pump a DispatcherFrame)."
    "github-ai-issue-classification" = "Use when assigning the mandatory 'ai: *' complexity tier to a GitHub issue - the four tiers (light, standard, heavy, ultra), the criteria and capability band of each, and the decision procedure (estimate files touched and depth of architectural understanding, and err to the higher tier when core abstractions or core business logic are involved)."
    "github-branch-pull"             = "Use when scanning local DiGi repositories, identifying SemVer branches, selecting the highest version, and pulling/syncing the local machine with the latest remote state."
    "github-branch-synchronization"  = "Use ONLY when the user explicitly asks for the version-branch to main merge and patch-bump release workflow (a bump, a release, or a branch sync) - syncing a bare SemVer branch into main, bumping the patch version, and pushing both branches. Completing or closing an issue, or a general 'commit and push', never triggers it: the work goes on the active version branch and the bump is offered on request."
    "github-issues"                  = "Use when querying, filtering, creating, managing, commenting on, or closing GitHub issues/PRs - filtering issues by labels via FilterIssues.ps1 to reduce token usage, avoiding PowerShell pipeline decoding mangling on existing issue bodies via dedicated Python scripts, verifying an issue's stated premises against the code before implementing it (including that a feature said to 'already work' produces observable output), mandatory Type, Priority and AI Complexity labels plus default assignee (ZiolkowskiJakub) on all new issues, mandatory --body-file usage, blocking relationships as GitHub issue dependencies (gh api .../dependencies/blocked_by, cross-repository, set when the blocker is filed and verified with the blocking GET), GraphQL revision recovery, and filing server-side production runs/deploys/re-derivations as their own follow-up issue with a blocked_by dependency (the code issue closes on its own)."
    "github-labels"                  = "Use when standardizing, applying, or syncing GitHub issue and PR labels across repositories - Type, Priority, Status and AI Complexity taxonomy, requiring Type, Priority and an 'ai: *' tier on every new issue, and updating labels only on open issues by default."
    "github-plan-files"              = "Use when an implementation plan exists or a commit/push is about to happen in a DiGi repository - plans live in the local plans folder outside the working tree, a pre-commit sweep keeps plan/scratch *.md out of every commit and push, and the default action is deleting the temporary implementation plan in the same session the issue closes (no archiving into the repo; explicit user instruction wins)."
    "github-sub-issues"              = "Use when creating sub-issues or sub-tasks, or breaking a feature into per-repository work items - the tracking-issue pattern (a parent tracking issue with a Sub-issues table plus one self-contained sub-issue per repository, each referencing the parent, sibling ordering recorded as GitHub issue dependencies; canonical example DiGi.GIS.PostgreSQL #83)."
    "github-wiki-benchmark"          = "Use when creating or updating a repo's Benchmark GitHub wiki page - required page structure, reproducible-numbers conventions, and the checklist for adding a new benchmark entry."
    "github-wiki-general"            = "Use when editing any GitHub wiki page - repo layout, local clones under DiGi/wiki/, hand-authored vs auto-generated pages, and CI sync mechanics."
    "github-wiki-home"               = "Use when creating or editing a repository's Wiki Home page - template structure, parsing/preservation rules for the sync script, and the standard DiGi ecosystem footer."
    "github-working-branch"          = "Use when deciding where an AI agent commits or branches in a DiGi repository - the current active version branch (the highest bare SemVer branch) is the working branch: commit there as the work completes, push only when asked ('commit and push' goes to the same branch), never open a feature/issue branch, worktree or PR unless the user explicitly asks for that task only, and never base work on main (it is only the release target of the branch-synchronization workflow). Before the first edit run git branch --show-current and git pull --ff-only; after the user merges or deploys, pull before any rebuild."
    "github-workspace-setup"         = "Use when setting up a new machine or changing the local GitHub folder layout - one folder per GitHub owner (DiGi, DigiProject, ZiolkowskiJakub), Scripts/SetupWorkspace.ps1, restoring user files/, migrating from the pre-2026-10-14 layout, and the WIKI_SYNC_PAT wiki sync secret."
    "maintenance-ai-guidelines-propagation" = "Use when adding, renaming or removing an AI Guideline, or when generated skills (.agents/skills) must be regenerated - the guideline source file plus the five hand-synced targets (`$descriptions in UpdateAgents.ps1, .agents/AGENTS.md, the AI Guidelines README routing table, the Full Guideline Set table in files/README - Coding Guidelines.md, the workspace-root DiGi/CLAUDE.md routing table), skill-name derivation and description conventions (Use when <task> - concrete traps), the \r\r\n pre-flight guard, the -NoCommit dry-run trap, and what UpdateAgents.ps1 rewrites or deletes per repository (the skills folder and every other folder under .agents)."
    "maintenance-scripts"            = "Use when running or writing DiGi.Maintenance workspace scripts (BuildAll, Deploy, CheckHostDependencies, CopyUserFiles, CommitAllRepos and the other *AllRepos sweeps, InvestigateServer) - execution conventions (`$PSScriptRoot path resolution, exit codes not uniform across existing scripts with the 0/1/2 contract for new ones, host shell only), machine configuration in user files/*.conf (Directories.conf keys, opt-in booleans, never printing conf contents), cross-repository sweep conventions (narrow staging, core.autocrlf=false for generated output only - never for a hand-edited LF source, the -NoCommit dry-run trap), the build & deploy flow (BuildAll.ps1 builds only its hard-coded solution list) with its HintPath and runtime-asset traps, and the house conventions for a new script."
    "xml-documentation-audit"        = "Use when auditing or synchronizing existing XML docs against current signatures - a superset of xml-documentation-create that also rewrites stale summaries and fixes mismatched param/returns tags."
    "xml-documentation-create"       = "Use when adding missing XML <summary> docs to public members without touching existing docs or code logic."
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
