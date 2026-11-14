<#
.SYNOPSIS
    Regenerates the '.agents' rules and skills of every DiGi repository from the canonical AI Guidelines.

.DESCRIPTION
    The manifest 'DiGi.Maintenance/documentation/AI Guidelines/Guidelines.json' is the one list of guidelines: per
    file its category, its skill description and its CLAUDE.md routing cell. From it and the guideline files:

    1. Rewrites the generated blocks (between '<!-- guidelines:begin -->' and '<!-- guidelines:end -->') of
       'documentation/AI Guidelines/README.md' (index), 'DiGi.Maintenance/.agents/AGENTS.md' (skill list) and the
       workspace 'CLAUDE.md' (routing table; skipped when the file does not exist). Each file keeps its own line
       ending and BOM. 'files/README - Coding Guidelines.md' is hand-written: the run fails when it does not name
       every guideline file.
    2. Copies 'DiGi.Maintenance/.agents/AGENTS.md' into every 'DiGi.*' repository.
    3. Turns every guideline (except README.md) into '.agents/skills/<skill-name>/SKILL.md' with YAML frontmatter.
       A guideline opening with '## Checklist' becomes a small SKILL.md (introduction + checklist) plus the whole
       text as 'guideline.md' beside it; its 'Evidence/<same name>.md', when present, is copied as 'evidence.md'
       and the links follow.
    4. Copies every workflow skill 'DiGi.Maintenance/files/skills/<name>/SKILL.md' into '.agents/skills/<name>' of
       every repository and into the workspace '.claude/skills/<name>' (Claude Code).
    5. Optionally refreshes an external, machine-global AGENTS.md whose path is configured as
       GLOBAL_AGENTS_FILE in 'user files/Directories.conf'. Everything up to and including the
       '## Summary of Core Coding & Testing Guidelines' heading is preserved; the compiled guidelines follow.
    6. Commits the change in every repository that has a .git directory, unless -NoCommit is specified.

    The run fails before writing anything when the manifest and the guideline files disagree.
    Generated '.agents' files are written as UTF-8 without BOM using CRLF line endings.

.PARAMETER NoCommit
    If specified, files are updated but no git commit is created.

.PARAMETER Message
    Commit message used when committing updated '.agents' folders.

.PARAMETER Repo
    Limit the repository sweep to one 'DiGi.*' folder name (the generated blocks are always refreshed).
    An unknown name exits 2.
#>
param (
    [switch]$NoCommit,

    [string]$Message = "Sync rules and skills (.agents) with latest AI Guidelines",

    [string]$Repo = ""
)

$ErrorActionPreference = "Stop"

# Workspace root, resolved relative to this script
$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path
Write-Host "Base directory resolved to: $baseDir" -ForegroundColor Cyan

$guidelinesDir = Join-Path $baseDir "DiGi.Maintenance\documentation\AI Guidelines"
$evidenceDir = Join-Path $guidelinesDir "Evidence"
$manifestFile = Join-Path $guidelinesDir "Guidelines.json"
$referenceAgentsFile = Join-Path $baseDir "DiGi.Maintenance\.agents\AGENTS.md"
$readmeGuidelinesFile = Join-Path $baseDir "DiGi.Maintenance\files\README - Coding Guidelines.md"
$workflowSkillsDir = Join-Path $baseDir "DiGi.Maintenance\files\skills"

if (-not (Test-Path $guidelinesDir)) {
    Write-Error "AI Guidelines directory not found: $guidelinesDir"
    exit 1
}

if (-not (Test-Path $manifestFile)) {
    Write-Error "Guideline manifest not found at: $manifestFile"
    exit 1
}

if (-not (Test-Path $referenceAgentsFile)) {
    Write-Error "Reference AGENTS.md not found at: $referenceAgentsFile"
    exit 1
}

$targetDirectories = @(Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*")
if ($Repo -ne "") {
    $targetDirectories = @($targetDirectories | Where-Object { $_.Name -eq $Repo })
    if ($targetDirectories.Count -eq 0) {
        Write-Host "Unknown repository '$Repo' under $baseDir." -ForegroundColor Red
        exit 2
    }
} else {
    # The repository template carries the same '.agents' folder
    $templateDir = Join-Path $baseDir "templates\DiGi.Template"
    if (Test-Path $templateDir) {
        $targetDirectories += Get-Item $templateDir
    }
}

# Pre-flight guard: fail when a source file carries a stray '\r\r\n' line ending. Without
# this, the sync below would silently propagate the sequence into every generated file
# (see 'GitHub - Issues.md' section 1 - the \r\r\n trap).
$guardFiles = @(Get-ChildItem -Path $guidelinesDir -Recurse -Filter "*.md" | ForEach-Object { $_.FullName })
$guardFiles += $referenceAgentsFile
$guardFiles += Join-Path $baseDir "DiGi.Maintenance\README.md"
$guardFiles += $readmeGuidelinesFile
if (Test-Path $workflowSkillsDir) {
    $guardFiles += @(Get-ChildItem -Path $workflowSkillsDir -Recurse -Filter "*.md" | ForEach-Object { $_.FullName })
}
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

# Replaces the lines between the generated-block markers of a file, keeping its line ending and BOM.
# Writes only when the content changes, so a re-run leaves the file untouched.
function Set-GeneratedBlock {
    param (
        [string]$Path,
        [string[]]$Lines
    )

    $beginMarker = "<!-- guidelines:begin -->"
    $endMarker = "<!-- guidelines:end -->"

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.IO.File]::ReadAllText($Path)

    $beginIndex = $text.IndexOf($beginMarker)
    $endIndex = $text.IndexOf($endMarker)
    if ($beginIndex -lt 0 -or $endIndex -lt $beginIndex) {
        Write-Host "Generated-block markers '$beginMarker' ... '$endMarker' not found in: $Path" -ForegroundColor Red
        exit 1
    }

    $eol = "`n"
    if ($text.Contains("`r`n")) {
        $eol = "`r`n"
    }

    $newText = $text.Substring(0, $beginIndex + $beginMarker.Length) + $eol + ($Lines -join $eol) + $eol + $text.Substring($endIndex)
    if ($newText -eq $text) {
        return
    }

    [System.IO.File]::WriteAllText($Path, $newText, (New-Object System.Text.UTF8Encoding($hasBom)))
    Write-Host "Updated generated block: $Path" -ForegroundColor Cyan
}

# 'Coding - Deployed WebAPI.md' -> 'coding-deployed-webapi'
function Get-SkillName {
    param (
        [string]$FileName
    )

    return ([System.IO.Path]::GetFileNameWithoutExtension($FileName) -replace '\s+-\s+', '-' -replace '\s+', '-').ToLower()
}

# Guideline files, in a stable order (README.md is an index, not a guideline)
$guidelineFiles = Get-ChildItem -Path $guidelinesDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name

# The manifest: the one list of guidelines every generated target is derived from
$manifest = [System.IO.File]::ReadAllText($manifestFile) | ConvertFrom-Json
$manifestEntries = @($manifest.guidelines)
$categories = @($manifest.categories)

$manifestProblems = @()
$entryByFile = @{}
foreach ($entry in $manifestEntries) {
    if ($entryByFile.ContainsKey($entry.file)) {
        $manifestProblems += "Listed twice: $($entry.file)"
        continue
    }
    $entryByFile[$entry.file] = $entry
    if (-not (Test-Path (Join-Path $guidelinesDir $entry.file))) {
        $manifestProblems += "Listed but missing on disk: $($entry.file)"
    }
    if ($categories -notcontains $entry.category) {
        $manifestProblems += "Unknown category '$($entry.category)': $($entry.file)"
    }
    if (-not $entry.description -or -not $entry.description.StartsWith("Use ")) {
        $manifestProblems += "Description must start with 'Use when ...': $($entry.file)"
    }
    if (-not $entry.route) {
        $manifestProblems += "No route (CLAUDE.md task cell): $($entry.file)"
    }
}
foreach ($guidelineFile in $guidelineFiles) {
    if (-not $entryByFile.ContainsKey($guidelineFile.Name)) {
        $manifestProblems += "On disk but not listed: $($guidelineFile.Name)"
    }
}

# The README block is hand-written (a parallel condensation), so only its coverage is checked
if (Test-Path $readmeGuidelinesFile) {
    $readmeGuidelinesText = [System.IO.File]::ReadAllText($readmeGuidelinesFile)
    foreach ($entry in $manifestEntries) {
        if (-not $readmeGuidelinesText.Contains($entry.file)) {
            $manifestProblems += "Not named in 'files/README - Coding Guidelines.md': $($entry.file)"
        }
    }
}

# Workflow skills (hand-written SKILL.md files that call the maintenance scripts)
$workflowSkills = @()
if (Test-Path $workflowSkillsDir) {
    $workflowSkills = @(Get-ChildItem -Path $workflowSkillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } | Sort-Object Name)
    foreach ($workflowSkill in $workflowSkills) {
        foreach ($entry in $manifestEntries) {
            if ((Get-SkillName $entry.file) -eq $workflowSkill.Name) {
                $manifestProblems += "Workflow skill name collides with a guideline skill: $($workflowSkill.Name)"
            }
        }
    }
}

if ($manifestProblems.Count -gt 0) {
    Write-Host "Guidelines.json and the guideline files disagree:" -ForegroundColor Red
    foreach ($manifestProblem in $manifestProblems) {
        Write-Host "  - $manifestProblem" -ForegroundColor Yellow
    }
    exit 1
}

# Generated blocks: the index, the skill list and the Claude Code routing table
$indexLines = @()
$agentsLines = @()
foreach ($category in $categories) {
    $categoryEntries = @($manifestEntries | Where-Object { $_.category -eq $category })
    if ($categoryEntries.Count -eq 0) {
        continue
    }

    if ($indexLines.Count -gt 0) {
        $indexLines += ""
        $agentsLines += ""
    }

    $indexLines += "## $category"
    $indexLines += "| File | Read when |"
    $indexLines += "|------|-----------|"
    $agentsLines += "### $category"

    foreach ($entry in $categoryEntries) {
        $readWhen = $entry.description -replace '^Use (when )?', ''
        $readWhen = $readWhen.Substring(0, 1).ToUpper() + $readWhen.Substring(1)
        $indexLines += "| [$($entry.file)]($($entry.file -replace ' ', '%20')) | $($readWhen -replace '\|', '\|') |"
        $agentsLines += "- **$(Get-SkillName $entry.file):** $($entry.description)"
    }
}

$routingLines = @("| Task | Read |", "|------|------|")
foreach ($entry in $manifestEntries) {
    $routingLines += "| $($entry.route) | ``$($entry.file)``$($entry.routeNote) |"
}

Set-GeneratedBlock -Path (Join-Path $guidelinesDir "README.md") -Lines $indexLines
Set-GeneratedBlock -Path $referenceAgentsFile -Lines $agentsLines

$claudeFile = Join-Path $baseDir "CLAUDE.md"
if (Test-Path $claudeFile) {
    Set-GeneratedBlock -Path $claudeFile -Lines $routingLines
} else {
    Write-Host "Workspace CLAUDE.md not found - skipping its routing table." -ForegroundColor DarkGray
}

# Workflow skills for Claude Code live in the workspace root (which is no repository)
foreach ($workflowSkill in $workflowSkills) {
    $claudeSkillFolder = Join-Path $baseDir ".claude\skills\$($workflowSkill.Name)"
    New-Item -ItemType Directory -Path $claudeSkillFolder -Force | Out-Null
    Write-TextFile -Path (Join-Path $claudeSkillFolder "SKILL.md") -Text ([System.IO.File]::ReadAllText((Join-Path $workflowSkill.FullName "SKILL.md")))
}

# Search tools built on ripgrep honour a '.ignore' file: without it every phrase of a guideline is found once per
# repository (its generated '.agents' copy). The copies of DiGi.Maintenance stay searchable; the source always is.
$ignoreFile = Join-Path $baseDir ".ignore"
$ignoreLines = @(
    "# Generated copies of the AI Guidelines (source: DiGi.Maintenance/documentation/AI Guidelines) - written by UpdateAgents.ps1",
    "/DiGi.*/.agents/",
    "!/DiGi.Maintenance/.agents/",
    "/templates/*/.agents/"
)
$ignoreText = ""
if (Test-Path $ignoreFile) {
    $ignoreText = [System.IO.File]::ReadAllText($ignoreFile) -replace "`r", ""
}
if (-not $ignoreText.Contains("/DiGi.*/.agents/")) {
    if ($ignoreText -ne "" -and -not $ignoreText.EndsWith("`n")) {
        $ignoreText += "`n"
    }
    [System.IO.File]::WriteAllText($ignoreFile, $ignoreText + ($ignoreLines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Updated search ignore file: $ignoreFile" -ForegroundColor Cyan
}

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
        $skillName = Get-SkillName $guidelineFile.Name
        $description = $entryByFile[$guidelineFile.Name].description

        $skillFolder = Join-Path $skillsDir $skillName
        New-Item -ItemType Directory -Path $skillFolder -Force | Out-Null

        $guidelineText = [System.IO.File]::ReadAllText($guidelineFile.FullName)

        # The evidence file travels with the skill as 'evidence.md'; links to 'Evidence/<name>.md' follow it
        $evidenceFile = Join-Path $evidenceDir $guidelineFile.Name
        if (Test-Path $evidenceFile) {
            Write-TextFile -Path (Join-Path $skillFolder "evidence.md") -Text ([System.IO.File]::ReadAllText($evidenceFile))
            $guidelineText = $guidelineText.Replace("Evidence/" + ($guidelineFile.Name -replace ' ', '%20'), "evidence.md").Replace("Evidence/" + $guidelineFile.Name, "evidence.md")
        }

        # YAML frontmatter: emit the description as a double-quoted scalar with proper escaping,
        # because the plain-scalar form is invalid when the text contains ': ' (e.g. "'ai: *'")
        # or lossy when it contains ' #' (parsed as a comment) or starts with a special character.
        $yamlBackslash = [string][char]92
        $yamlQuote = [string][char]34
        # Escape for a double-quoted YAML scalar: double every backslash, then prefix every quote with one backslash.
        $yamlDescription = $description.Replace($yamlBackslash, $yamlBackslash + $yamlBackslash).Replace($yamlQuote, $yamlBackslash + $yamlQuote)
        $frontmatter = "---`nname: $skillName`ndescription: `"$yamlDescription`"`n---`n`n"

        # A guideline that opens with '## Checklist' ships as a small SKILL.md (introduction + checklist) and the whole
        # guideline beside it as 'guideline.md': a skill body loads whole, so the sections are read on demand.
        $normalizedGuidelineText = $guidelineText -replace "`r", ""
        $checklistIndex = $normalizedGuidelineText.IndexOf("`n## Checklist`n")
        $sectionMatch = $null
        if ($checklistIndex -ge 0) {
            $sectionMatch = [regex]::Match($normalizedGuidelineText.Substring($checklistIndex + 1), '(?m)^## \d')
        }

        if ($null -ne $sectionMatch -and $sectionMatch.Success) {
            $skillBody = $normalizedGuidelineText.Substring(0, $checklistIndex + 1 + $sectionMatch.Index).TrimEnd("`n")
            $skillBody += "`n`n**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.`n"
            Write-TextFile -Path (Join-Path $skillFolder "SKILL.md") -Text ($frontmatter + $skillBody)
            Write-TextFile -Path (Join-Path $skillFolder "guideline.md") -Text $normalizedGuidelineText
        } else {
            Write-TextFile -Path (Join-Path $skillFolder "SKILL.md") -Text ($frontmatter + $guidelineText)
        }
    }

    foreach ($workflowSkill in $workflowSkills) {
        $skillFolder = Join-Path $skillsDir $workflowSkill.Name
        New-Item -ItemType Directory -Path $skillFolder -Force | Out-Null
        Write-TextFile -Path (Join-Path $skillFolder "SKILL.md") -Text ([System.IO.File]::ReadAllText((Join-Path $workflowSkill.FullName "SKILL.md")))
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
