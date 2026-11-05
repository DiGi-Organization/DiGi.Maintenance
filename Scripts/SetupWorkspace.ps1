<#
.SYNOPSIS
    Creates (or repairs) the local GitHub workspace layout: one folder per GitHub owner.

.DESCRIPTION
    Layout under the GitHub root folder:
        DiGi\              <- every repository of DiGi-Organization (DiGi.* libraries, siblings - HintPaths rely on it)
        DiGi\templates\    <- DiGi.Template, DiGi.WebAPI.GLTF.Template
        DiGi\wiki\         <- <repo>.wiki clones (only with -IncludeWikis)
        DigiProject\       <- every repository of DigiProject-Organization (client projects)
        ZiolkowskiJakub\   <- selected personal repositories ($personalRepositories below)

    Safe to re-run: an existing repository folder is never re-cloned. With -UpdateRemotes the 'origin'
    of an existing clone (and of every existing wiki clone) is pointed at its current owner, which is
    how an existing machine is migrated after repositories were transferred between owners.

    Requires git and an authenticated GitHub CLI ('gh auth login') with access to both organizations.
    See 'documentation/AI Guidelines/GitHub - Workspace Setup.md'.

.PARAMETER Root
    GitHub root folder (the folder that contains DiGi\ and DigiProject\). Defaults to the parent of the
    DiGi workspace when this script runs from DiGi\DiGi.Maintenance\Scripts, otherwise to the current directory.

.PARAMETER Only
    Optional repository names to restrict the run to (e.g. 'DiGi.Core','DiGi.Geometry'). Useful for testing.

.PARAMETER IncludeWikis
    Also clone the wiki of every DiGi-Organization repository that has one into DiGi\wiki\<repo>.wiki.

.PARAMETER UpdateRemotes
    Point 'origin' of existing clones (repositories and DiGi\wiki\*.wiki) at the expected owner.

.EXAMPLE
    .\SetupWorkspace.ps1 -WhatIf
    .\SetupWorkspace.ps1 -Root "$env:USERPROFILE\GitHub"
    .\SetupWorkspace.ps1 -UpdateRemotes
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$Root,
    [string[]]$Only,
    [switch]$IncludeWikis,
    [switch]$UpdateRemotes
)

$ErrorActionPreference = "Stop"

# Owner -> local folder. 'Repositories' = $null means every repository of the owner.
$personalRepositories = @("CustomActions", "Formula", "dg_dfl")
$owners = @(
    @{ Owner = "DiGi-Organization";        Folder = "DiGi";            Repositories = $null },
    @{ Owner = "DigiProject-Organization"; Folder = "DigiProject";     Repositories = $null },
    @{ Owner = "ZiolkowskiJakub";          Folder = "ZiolkowskiJakub"; Repositories = $personalRepositories }
)
$templateRepositories = @("DiGi.Template", "DiGi.WebAPI.GLTF.Template")

if ([string]::IsNullOrWhiteSpace($Root)) {
    $workspaceDir = Resolve-Path "$PSScriptRoot\..\.." -ErrorAction SilentlyContinue
    if ($workspaceDir -and (Split-Path -Leaf $workspaceDir.Path) -eq "DiGi") {
        $Root = Split-Path -Parent $workspaceDir.Path
    }
    else {
        $Root = (Get-Location).Path
    }
}
$Root = [System.IO.Path]::GetFullPath($Root)

foreach ($tool in @("git", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' was not found on PATH."
    }
}
gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run 'gh auth login' first."
}

Write-Host "GitHub root: $Root" -ForegroundColor Cyan

$cloned = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$updated = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

function Confirm-Directory([string]$Path) {
    if (-not (Test-Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

# "owner/name" of a GitHub remote URL in any of its forms (https or ssh, with or without .git), or $null
function Get-RemoteKey([string]$Url) {
    if ($Url -match 'github\.com[:/]+([^/]+)/(.+?)(\.git)?/?$') {
        return "$($Matches[1])/$($Matches[2])".ToLowerInvariant()
    }
    return $null
}

function Sync-Clone([string]$Url, [string]$Target, [string]$Label) {
    if (Test-Path $Target) {
        if (-not (Test-Path (Join-Path $Target ".git"))) {
            Write-Host "  ! $Label - '$Target' exists but is not a git repository, skipped" -ForegroundColor Yellow
            $failed.Add("$Label (not a git repository)")
            return
        }

        $currentUrl = git -C $Target config --get remote.origin.url
        # Compare owner/name rather than the literal URL, so a clone using ssh or a URL without '.git' is
        # not rewritten for nothing - and when it is rewritten, it keeps its protocol.
        if ($UpdateRemotes -and (Get-RemoteKey $currentUrl) -ne (Get-RemoteKey $Url)) {
            $newUrl = $Url
            if ($currentUrl -match '^(ssh://)?git@github\.com[:/]') {
                $newUrl = $Url -replace '^https://github\.com/', 'git@github.com:'
            }
            if ($PSCmdlet.ShouldProcess($Target, "Set origin to $newUrl (was $currentUrl)")) {
                if ([string]::IsNullOrWhiteSpace($currentUrl)) {
                    git -C $Target remote add origin $newUrl
                }
                else {
                    git -C $Target remote set-url origin $newUrl
                }
                if ($LASTEXITCODE -ne 0) {
                    $failed.Add("$Label (could not set origin, git exit code $LASTEXITCODE)")
                    return
                }
            }
            Write-Host "  ~ $Label - origin -> $newUrl" -ForegroundColor Cyan
            $updated.Add($Label)
            return
        }

        Write-Verbose "  = $Label - already present"
        $skipped.Add($Label)
        return
    }

    if ($PSCmdlet.ShouldProcess($Target, "git clone $Url")) {
        Write-Host "  + $Label" -ForegroundColor Green
        git clone --quiet $Url $Target
        if ($LASTEXITCODE -ne 0) {
            $failed.Add("$Label (git clone exit code $LASTEXITCODE)")
            return
        }
    }
    else {
        Write-Host "  + $Label (would clone)" -ForegroundColor Green
    }
    $cloned.Add($Label)
}

foreach ($ownerInfo in $owners) {
    $owner = $ownerInfo.Owner
    $ownerDir = Join-Path $Root $ownerInfo.Folder
    Write-Host "`n[$owner] -> $ownerDir" -ForegroundColor Cyan

    $repositories = gh repo list $owner --limit 1000 --json name,hasWikiEnabled | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        $failed.Add("$owner (gh repo list failed)")
        continue
    }
    if ($ownerInfo.Repositories) {
        $repositories = $repositories | Where-Object { $ownerInfo.Repositories -contains $_.name }
    }
    if ($Only) {
        $repositories = $repositories | Where-Object { $Only -contains $_.name }
    }
    if (-not $repositories) {
        continue
    }
    Confirm-Directory $ownerDir

    foreach ($repository in ($repositories | Sort-Object name)) {
        $name = $repository.name
        $parentDir = $ownerDir
        if ($owner -eq "DiGi-Organization" -and $templateRepositories -contains $name) {
            $parentDir = Join-Path $ownerDir "templates"
            Confirm-Directory $parentDir
        }

        Sync-Clone "https://github.com/$owner/$name.git" (Join-Path $parentDir $name) "$owner/$name"

        if ($IncludeWikis -and $owner -eq "DiGi-Organization" -and $repository.hasWikiEnabled) {
            $wikiUrl = "https://github.com/$owner/$name.wiki.git"
            $wikiTarget = Join-Path $ownerDir "wiki\$name.wiki"
            if (-not (Test-Path $wikiTarget)) {
                # A wiki repository exists only after its first page was created
                git ls-remote $wikiUrl *> $null
                if ($LASTEXITCODE -ne 0) {
                    Write-Verbose "  - $name.wiki - no wiki pages yet"
                    continue
                }
                Confirm-Directory (Join-Path $ownerDir "wiki")
            }
            Sync-Clone $wikiUrl $wikiTarget "$owner/$name.wiki"
        }
    }
}

# Existing wiki clones follow their repository's owner even without -IncludeWikis
if ($UpdateRemotes) {
    $wikiDir = Join-Path $Root "DiGi\wiki"
    if (Test-Path $wikiDir) {
        Write-Host "`n[wiki clones] -> $wikiDir" -ForegroundColor Cyan
        foreach ($dir in Get-ChildItem -Path $wikiDir -Directory -Filter "*.wiki") {
            if ($Only -and ($Only -notcontains ($dir.Name -replace '\.wiki$', ''))) { continue }
            $label = "DiGi-Organization/$($dir.Name)"
            if ($updated.Contains($label) -or $skipped.Contains($label) -or $cloned.Contains($label)) { continue }
            Sync-Clone "https://github.com/DiGi-Organization/$($dir.Name).git" $dir.FullName $label
        }
    }
}

Write-Host "`nSummary: cloned $($cloned.Count), origin updated $($updated.Count), already present $($skipped.Count), failed $($failed.Count)" -ForegroundColor Cyan
foreach ($item in $failed) {
    Write-Host "  failed: $item" -ForegroundColor Red
}
if ($failed.Count -gt 0) {
    exit 1
}
