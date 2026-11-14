<#
.SYNOPSIS
    Reports the size of the AI agent context: what every session loads, and what each guideline costs when read.

.DESCRIPTION
    Read-only. Measures, in bytes and approximate tokens (bytes / 4):
      - ClaudeCode: the workspace 'CLAUDE.md' and the frontmatter of every workspace '.claude/skills/*/SKILL.md'.
      - OpenCode:   every file listed under "instructions" in the workspace 'opencode.jsonc' and the frontmatter
                    of every 'DiGi.Maintenance/.agents/skills/*/SKILL.md' (auto-discovered skill descriptions).
      - Generic:    'DiGi.Maintenance/.agents/AGENTS.md' and the same skill frontmatter.
      - Guideline:  every file in 'DiGi.Maintenance/documentation/AI Guidelines' (paid when a task reads it).
      - Evidence:   every file in its 'Evidence' subfolder (read only when a rule is disputed or changed).

    Use it before and after a guideline change to see what the change costs every session.

.PARAMETER Json
    Emit one compressed JSON array of { Group, Item, Bytes, Tokens } instead of text.

.PARAMETER OutputPath
    Also write the JSON to this file (pass an absolute path), e.g. a baseline under 'user files/reports'.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\MeasureAgentContext.ps1"
#>
param (
    [switch]$Json,

    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path
$maintenanceDir = Join-Path $baseDir "DiGi.Maintenance"
$guidelinesDir = Join-Path $maintenanceDir "documentation\AI Guidelines"
$evidenceDir = Join-Path $guidelinesDir "Evidence"

if (-not (Test-Path $guidelinesDir)) {
    Write-Host "AI Guidelines directory not found: $guidelinesDir" -ForegroundColor Red
    exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$rows = New-Object System.Collections.Generic.List[object]

function Add-Row {
    param (
        [string]$Group,
        [string]$Item,
        [long]$Bytes
    )

    $rows.Add([pscustomobject]@{ Group = $Group; Item = $Item; Bytes = $Bytes; Tokens = [long][math]::Round($Bytes / 4.0) })
}

function Add-File {
    param (
        [string]$Group,
        [string]$Path
    )

    if (Test-Path $Path) {
        Add-Row -Group $Group -Item ($Path.Substring($baseDir.Length).TrimStart('\') -replace '\\', '/') -Bytes (Get-Item $Path).Length
    }
}

# Sum of the YAML frontmatter (name + description) of every SKILL.md below a skills directory
function Add-SkillDescriptions {
    param (
        [string]$Group,
        [string]$SkillsDir
    )

    if (-not (Test-Path $SkillsDir)) {
        return
    }

    [long]$bytes = 0
    $count = 0
    foreach ($skillFile in Get-ChildItem -Path $SkillsDir -Recurse -Filter "SKILL.md") {
        $text = [System.IO.File]::ReadAllText($skillFile.FullName)
        $match = [regex]::Match($text, '\A---\r?\n(.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($match.Success) {
            $bytes += $utf8.GetByteCount($match.Groups[1].Value)
            $count++
        }
    }

    Add-Row -Group $Group -Item ("skill descriptions x" + $count + " (" + ($SkillsDir.Substring($baseDir.Length).TrimStart('\') -replace '\\', '/') + ")") -Bytes $bytes
}

$maintenanceSkillsDir = Join-Path $maintenanceDir ".agents\skills"

# Claude Code
Add-File -Group "ClaudeCode" -Path (Join-Path $baseDir "CLAUDE.md")
Add-SkillDescriptions -Group "ClaudeCode" -SkillsDir (Join-Path $baseDir ".claude\skills")

# OpenCode: the "instructions" array of opencode.jsonc
$openCodePath = Join-Path $baseDir "opencode.jsonc"
if (Test-Path $openCodePath) {
    $openCodeText = [System.IO.File]::ReadAllText($openCodePath)
    $instructions = [regex]::Match($openCodeText, '"instructions"\s*:\s*\[(.*?)\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($instructions.Success) {
        foreach ($entry in [regex]::Matches($instructions.Groups[1].Value, '"([^"]+)"')) {
            Add-File -Group "OpenCode" -Path (Join-Path $baseDir ($entry.Groups[1].Value -replace '/', '\'))
        }
    }
    Add-SkillDescriptions -Group "OpenCode" -SkillsDir $maintenanceSkillsDir
}

# Generic .agents consumers
Add-File -Group "Generic" -Path (Join-Path $maintenanceDir ".agents\AGENTS.md")
Add-SkillDescriptions -Group "Generic" -SkillsDir $maintenanceSkillsDir

# On-demand guideline files
foreach ($guidelineFile in Get-ChildItem -Path $guidelinesDir -Filter "*.md" | Sort-Object Name) {
    Add-Row -Group "Guideline" -Item $guidelineFile.Name -Bytes $guidelineFile.Length
}

if (Test-Path $evidenceDir) {
    foreach ($evidenceFile in Get-ChildItem -Path $evidenceDir -Filter "*.md" | Sort-Object Name) {
        Add-Row -Group "Evidence" -Item $evidenceFile.Name -Bytes $evidenceFile.Length
    }
}

$jsonText = ConvertTo-Json -InputObject $rows.ToArray() -Depth 3 -Compress

if ($OutputPath -ne "") {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -ne "" -and -not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $jsonText + "`n", $utf8)
}

if ($Json) {
    Write-Output $jsonText
    exit 0
}

foreach ($group in "ClaudeCode", "OpenCode", "Generic", "Guideline", "Evidence") {
    $groupRows = @($rows | Where-Object { $_.Group -eq $group })
    if ($groupRows.Count -eq 0) {
        continue
    }

    [long]$total = ($groupRows | Measure-Object -Property Bytes -Sum).Sum
    $label = "always loaded"
    if ($group -eq "Guideline" -or $group -eq "Evidence") {
        $label = "on demand"
    }

    Write-Host ("{0} ({1}): {2} B ~{3} tokens" -f $group, $label, $total, [long][math]::Round($total / 4.0)) -ForegroundColor Cyan
    foreach ($row in $groupRows | Sort-Object Bytes -Descending) {
        Write-Host ("  {0,7} B ~{1,5}  {2}" -f $row.Bytes, $row.Tokens, $row.Item)
    }
}

exit 0
