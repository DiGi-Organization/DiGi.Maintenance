<#
.SYNOPSIS
Checks the GitHub wikis of all DiGi.* repositories for broken or foreign wiki links.

.DESCRIPTION
Two classes of findings are flagged:
  1. WRONG-OWNER - a github.com link whose owner differs from the owner of the
     repository whose wiki is being checked (e.g. a stale "ZiolkowskiJakub" link
     after a transfer to "DiGi-Organization").
  2. DEAD-LINK   - a link to a DiGi repository whose code or wiki repository
     does not exist under the linked owner (e.g. a link to a repository that
     was never created or was deleted).

Wiki markdown is read from the local "DiGi/wiki/<repo>.wiki" clone when present;
otherwise a shallow clone is created in TEMP and removed afterwards.

Exit code is 0 when no findings exist and 1 when at least one finding is
reported, so the script can gate a CI workflow.

.EXAMPLE
PowerShell -ExecutionPolicy Bypass -File ".\CheckWikiLinks.ps1"
#>

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path

# Probe cache: "owner/repo" -> $true / $false
$existsCache = @{}

function Test-RemoteExists {
    param(
        [Parameter(Mandatory = $true)] [string]$Url
    )
    if ($existsCache.ContainsKey($Url)) { return $existsCache[$Url] }
    $null = git ls-remote --exit-code $Url HEAD 2>$null
    $result = ($LASTEXITCODE -eq 0)
    $existsCache[$Url] = $result
    return $result
}

# The link pattern matches both "https://github.com/<owner>/<repo>[/path...]"
# and "git@github.com:<owner>/<repo>" forms. Group 1 = owner, group 2 = repo,
# group 3 = optional path (present for /wiki, /blob, ... links).
$linkPattern = '(?:https?://)?github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)((?:/[^\s\)\]\|>]*)?)'

$targetDirectories = Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*"
$findings = [System.Collections.Generic.List[string]]::new()
$checkedCount = 0
$skippedCount = 0

foreach ($dir in $targetDirectories) {
    $dirName = $dir.Name

    Push-Location $dir.FullName
    $remoteUrl = git config --get remote.origin.url
    Pop-Location

    if (-not $remoteUrl -or $remoteUrl -notmatch 'github\.com[:/]([^/]+)/') {
        continue
    }
    $owner = $Matches[1]

    # Read the wiki pages from the local clone when available.
    $isTempClone = $false
    $localClone = Join-Path (Join-Path $baseDir "wiki") "$dirName.wiki"
    if (Test-Path $localClone) {
        $pagesDir = $localClone
    } else {
        $tempDir = Join-Path $env:TEMP "DiGi.WikiLinkCheck_$dirName"
        if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
        $null = git clone --quiet --depth 1 "https://github.com/$owner/$dirName.wiki.git" $tempDir 2>$null
        if ($LASTEXITCODE -ne 0) {
            # No wiki at all - nothing to check here.
            $skippedCount++
            continue
        }
        $pagesDir = $tempDir
        $isTempClone = $true
    }

    $mdFiles = Get-ChildItem -Path $pagesDir -Filter "*.md" -File
    foreach ($md in $mdFiles) {
        $content = Get-Content -Raw $md.FullName
        $linkMatches = [regex]::Matches($content, $linkPattern)
        $seen = @{}
        foreach ($m in $linkMatches) {
            $linkOwner = $m.Groups[1].Value
            $linkRepo = $m.Groups[2].Value
            $linkPath = $m.Groups[3].Value

            # Only DiGi.* repositories are part of this ecosystem check.
            if ($linkRepo -notlike "DiGi.*") { continue }

            $key = "$linkOwner/$linkRepo"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $location = "$dirName/$($md.Name)"

            if ($linkOwner -ne $owner) {
                $findings.Add("[WRONG-OWNER] $location -> github.com/$linkOwner/$linkRepo (expected owner: $owner)")
                continue
            }

            # Links under /wiki probe the wiki repository; everything else
            # probes the code repository.
            if ($linkPath -like "wiki*" -or $linkPath -like "/wiki*" -or $linkPath -eq "") {
                $probeUrl = "https://github.com/$linkOwner/$linkRepo.wiki.git"
            } else {
                $probeUrl = "https://github.com/$linkOwner/$linkRepo.git"
            }
            if (-not (Test-RemoteExists $probeUrl)) {
                $findings.Add("[DEAD-LINK] $location -> github.com/$linkOwner/$linkRepo (repository does not exist)")
            }
        }
    }

    if ($isTempClone) {
        Remove-Item -Recurse -Force $pagesDir
    }
    $checkedCount++
}

Write-Host "Checked $checkedCount wiki repositories (skipped $skippedCount without a wiki) under owner-independent checks." -ForegroundColor Cyan

if ($findings.Count -gt 0) {
    Write-Host ""
    Write-Host "=== $($findings.Count) FINDING(S) ===" -ForegroundColor Red
    foreach ($finding in $findings) {
        Write-Host "  $finding" -ForegroundColor Yellow
    }
    exit 1
} else {
    Write-Host "OK: no wrong-owner or dead wiki links found." -ForegroundColor Green
    exit 0
}
