<#
.SYNOPSIS
    Proves that a restructured AI Guideline lost no fact compared with an earlier commit.

.DESCRIPTION
    Read-only. For every guideline in 'DiGi.Maintenance/documentation/AI Guidelines' that exists at -BaseRef, extracts
    the facts of the base version:
      - every line of a fenced code block,
      - every backticked span (identifiers, paths, commands, commit hashes),
      - every issue reference ('#12', 'DiGi.Core#6'),
      - every ISO date and every number of two or more digits (list markers, heading numbers and section
        references excluded),
    and looks each one up in the current guideline plus its 'Evidence/<same name>.md'.
      - found there                       -> kept
      - found only in another guideline   -> moved (allowed: one canonical home per rule; listed with -Detail)
      - found nowhere                     -> LOST (the script exits 1)
    A numbered section heading ('## 3.') of the base version that no longer exists is also LOST, because code
    comments across the workspace cite guidelines as 'File.md <section>'.

.PARAMETER BaseRef
    Commit, tag or branch of DiGi.Maintenance to compare with. Defaults to HEAD (the uncommitted edit).

.PARAMETER Name
    Limit the check to one guideline file name, e.g. "Coding - General.md". An unknown name exits 2.

.PARAMETER Detail
    Also list the moved facts.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineLossless.ps1" -BaseRef c9482d6
#>
param (
    [string]$BaseRef = "HEAD",

    [string]$Name = "",

    [switch]$Detail
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path
$maintenanceDir = Join-Path $baseDir "DiGi.Maintenance"
$relativeGuidelinesDir = "documentation/AI Guidelines"
$guidelinesDir = Join-Path $maintenanceDir "documentation\AI Guidelines"
$evidenceDir = Join-Path $guidelinesDir "Evidence"

# git prints UTF-8; without this Windows PowerShell decodes it with the console code page
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$sectionSign = [string][char]0x00A7

$baseNames = @(git -C $maintenanceDir ls-tree --name-only "$BaseRef" -- "$relativeGuidelinesDir/" | ForEach-Object { Split-Path -Leaf $_ } | Where-Object { $_ -like "*.md" })
if ($LASTEXITCODE -ne 0 -or $baseNames.Count -eq 0) {
    Write-Host "No guideline found at '$BaseRef'." -ForegroundColor Red
    exit 2
}

if ($Name -ne "") {
    if ($baseNames -notcontains $Name) {
        Write-Host "Unknown guideline '$Name' at '$BaseRef'. Known:" -ForegroundColor Red
        $baseNames | ForEach-Object { Write-Host "  $_" }
        exit 2
    }
    $baseNames = @($Name)
}

function Get-Facts {
    param (
        [string]$Text
    )

    $facts = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $prose = New-Object System.Text.StringBuilder
    $inFence = $false

    foreach ($line in ($Text -replace "`r", "") -split "`n") {
        if ($line.TrimStart().StartsWith('```')) {
            $inFence = -not $inFence
            continue
        }

        if ($inFence) {
            $codeLine = $line.Trim()
            if ($codeLine -ne "" -and $seen.Add("code:" + $codeLine)) {
                $facts.Add([pscustomobject]@{ Kind = "code"; Value = $codeLine })
            }
            continue
        }

        [void]$prose.AppendLine($line)
    }

    $proseText = $prose.ToString()

    foreach ($match in [regex]::Matches($proseText, '`([^`\n]+)`')) {
        $value = $match.Groups[1].Value
        if ($seen.Add("tick:" + $value)) {
            $facts.Add([pscustomobject]@{ Kind = "tick"; Value = $value })
        }
    }

    # Numbers are searched outside backticks, list markers, heading numbers and section references
    $numberText = [regex]::Replace($proseText, '`[^`\n]+`', ' ')
    $numberText = [regex]::Replace($numberText, '(?m)^\s*\d+\.\s', ' ')
    $numberText = [regex]::Replace($numberText, '(?m)^#+\s*\d+(\.\d+)*\.?', ' ')
    $numberText = [regex]::Replace($numberText, [regex]::Escape($sectionSign) + '\s?\d+(\.\d+)*', ' ')

    foreach ($match in [regex]::Matches($numberText, '(?<![\w/])(?:[A-Za-z][\w.]*)?#\d+')) {
        if ($seen.Add("ref:" + $match.Value)) {
            $facts.Add([pscustomobject]@{ Kind = "ref"; Value = $match.Value })
        }
    }

    foreach ($match in [regex]::Matches($numberText, '\b\d{4}-\d{2}-\d{2}\b')) {
        if ($seen.Add("date:" + $match.Value)) {
            $facts.Add([pscustomobject]@{ Kind = "date"; Value = $match.Value })
        }
    }

    foreach ($match in [regex]::Matches($numberText, '(?<![\w.#-])\d[\d,]*\d(?:\.\d+)?(?![\w-])')) {
        if ($seen.Add("num:" + $match.Value)) {
            $facts.Add([pscustomobject]@{ Kind = "num"; Value = $match.Value })
        }
    }

    return $facts
}

function Test-Fact {
    param (
        [object]$Fact,
        [string]$Text
    )

    if ($Fact.Kind -eq "num" -or $Fact.Kind -eq "ref") {
        return [regex]::IsMatch($Text, '(?<![\d#])' + [regex]::Escape($Fact.Value) + '(?!\d)')
    }

    return $Text.Contains($Fact.Value)
}

function Read-Normalized {
    param (
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return ""
    }

    return ([System.IO.File]::ReadAllText($Path) -replace "`r", "")
}

# Every current guideline and evidence file: the pool a fact may have moved to
$poolBuilder = New-Object System.Text.StringBuilder
foreach ($file in Get-ChildItem -Path $guidelinesDir -Recurse -Filter "*.md") {
    [void]$poolBuilder.AppendLine((Read-Normalized $file.FullName))
}
$poolText = $poolBuilder.ToString()

$lostTotal = 0
$movedTotal = 0

foreach ($baseName in $baseNames | Sort-Object) {
    $baseText = (git -C $maintenanceDir show "${BaseRef}:$relativeGuidelinesDir/$baseName") -join "`n"
    $currentText = (Read-Normalized (Join-Path $guidelinesDir $baseName)) + "`n" + (Read-Normalized (Join-Path $evidenceDir $baseName))

    $lost = New-Object System.Collections.Generic.List[string]
    $moved = New-Object System.Collections.Generic.List[string]

    if ($currentText.Trim() -eq "") {
        $lost.Add("file  (guideline removed)")
    }

    foreach ($fact in Get-Facts -Text $baseText) {
        if (Test-Fact -Fact $fact -Text $currentText) {
            continue
        }

        if (Test-Fact -Fact $fact -Text $poolText) {
            $moved.Add($fact.Kind + "  " + $fact.Value)
        } else {
            $lost.Add($fact.Kind + "  " + $fact.Value)
        }
    }

    $mainText = Read-Normalized (Join-Path $guidelinesDir $baseName)
    foreach ($match in [regex]::Matches($baseText, '(?m)^## (\d+)\.')) {
        if (-not [regex]::IsMatch($mainText, '(?m)^## ' + $match.Groups[1].Value + '\.')) {
            $lost.Add("section  ## " + $match.Groups[1].Value + ".")
        }
    }

    $lostTotal += $lost.Count
    $movedTotal += $moved.Count

    if ($lost.Count -gt 0) {
        Write-Host ("LOST  {0}: {1} lost, {2} moved" -f $baseName, $lost.Count, $moved.Count) -ForegroundColor Red
        $lost | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    } elseif ($moved.Count -gt 0) {
        Write-Host ("OK    {0}: {1} moved" -f $baseName, $moved.Count)
    } else {
        Write-Host ("OK    {0}" -f $baseName)
    }

    if ($Detail) {
        $moved | ForEach-Object { Write-Host "    moved  $_" -ForegroundColor DarkGray }
    }
}

if ($lostTotal -gt 0) {
    Write-Host ("{0} fact(s) lost, {1} moved to another guideline." -f $lostTotal, $movedTotal) -ForegroundColor Red
    exit 1
}

Write-Host ("No fact lost ({0} moved to another guideline)." -f $movedTotal) -ForegroundColor Green
exit 0
