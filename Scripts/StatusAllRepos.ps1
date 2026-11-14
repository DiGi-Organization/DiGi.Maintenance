<#
.SYNOPSIS
    One line per DiGi repository that needs attention: branch, uncommitted files, commits ahead/behind.

.DESCRIPTION
    Read-only (no fetch, no checkout). Walks every 'DiGi.*' repository under the workspace root and reports:
      - the current branch, and the expected one when it differs (the numerically highest bare SemVer local
        branch - the active version branch of 'GitHub - Branches and Commits.md'),
      - the number of uncommitted files (staged, modified and untracked),
      - commits ahead of / behind the upstream as last fetched ('gone' = the upstream branch was deleted,
        'none' = no upstream configured).
    A repository that is clean, in sync and on its expected branch is omitted unless -All is passed.
    Replaces running 'git status' repository by repository before a commit, a pull or a sweep.

.PARAMETER All
    Also list the repositories that need no attention.

.PARAMETER Repo
    Limit the report to one 'DiGi.*' folder name. An unknown name exits 2.

.PARAMETER Json
    Emit one compressed JSON array of { Repo, Branch, Expected, Dirty, Ahead, Behind, Upstream }.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\StatusAllRepos.ps1"
#>
param (
    [switch]$All,

    [string]$Repo = "",

    [switch]$Json
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path

$repositories = @(Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*" | Where-Object { Test-Path (Join-Path $_.FullName ".git") })
if ($Repo -ne "") {
    $repositories = @($repositories | Where-Object { $_.Name -eq $Repo })
    if ($repositories.Count -eq 0) {
        Write-Host "Unknown repository '$Repo' under $baseDir." -ForegroundColor Red
        exit 2
    }
}

$rows = New-Object System.Collections.Generic.List[object]

foreach ($repository in $repositories) {
    $path = $repository.FullName

    $branch = [string](git -C $path branch --show-current)
    if ($branch -eq "") {
        $branch = "(detached)"
    }

    $dirty = @(git -C $path status --porcelain).Count

    # Highest bare SemVer local branch = the active version branch
    $expected = ""
    $highest = $null
    foreach ($localBranch in @(git -C $path branch --format="%(refname:short)")) {
        if ($localBranch -notmatch '^\d+\.\d+\.\d+$') {
            continue
        }
        $version = [version]$localBranch
        if ($null -eq $highest -or $version -gt $highest) {
            $highest = $version
            $expected = $localBranch
        }
    }
    if ($expected -eq $branch) {
        $expected = ""
    }

    $ahead = 0
    $behind = 0
    $upstream = "none"
    if ($branch -ne "(detached)") {
        $tracking = [string](git -C $path for-each-ref --format="%(upstream:short)|%(upstream:track)" "refs/heads/$branch")
        $parts = $tracking.Split('|')
        if ($parts.Length -eq 2 -and $parts[0] -ne "") {
            $upstream = $parts[0]
            if ($parts[1] -match 'gone') {
                $upstream = "gone"
            }
            if ($parts[1] -match 'ahead (\d+)') {
                $ahead = [int]$Matches[1]
            }
            if ($parts[1] -match 'behind (\d+)') {
                $behind = [int]$Matches[1]
            }
        }
    }

    $rows.Add([pscustomobject]@{ Repo = $repository.Name; Branch = $branch; Expected = $expected; Dirty = $dirty; Ahead = $ahead; Behind = $behind; Upstream = $upstream })
}

$listed = @($rows | Where-Object { $All -or $_.Dirty -gt 0 -or $_.Ahead -gt 0 -or $_.Behind -gt 0 -or $_.Expected -ne "" -or $_.Upstream -eq "gone" -or $_.Branch -eq "(detached)" })

if ($Json) {
    Write-Output (ConvertTo-Json -InputObject $listed -Depth 3 -Compress)
    exit 0
}

foreach ($row in $listed) {
    $line = "{0}  {1}" -f $row.Repo, $row.Branch
    if ($row.Expected -ne "") {
        $line += " (expected $($row.Expected))"
    }
    if ($row.Dirty -gt 0) {
        $line += "  dirty=$($row.Dirty)"
    }
    if ($row.Ahead -gt 0) {
        $line += "  ahead=$($row.Ahead)"
    }
    if ($row.Behind -gt 0) {
        $line += "  behind=$($row.Behind)"
    }
    if ($row.Upstream -eq "gone" -or $row.Upstream -eq "none") {
        $line += "  upstream=$($row.Upstream)"
    }
    Write-Host $line
}

Write-Host ("{0} repositories, {1} need attention." -f $rows.Count, @($rows | Where-Object { $_.Dirty -gt 0 -or $_.Ahead -gt 0 -or $_.Behind -gt 0 -or $_.Expected -ne "" }).Count) -ForegroundColor Cyan
exit 0
