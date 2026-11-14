<#
.SYNOPSIS
    Searches, filters, and inspects GitHub issues across DiGi repositories by labels, repository, state, and keywords.

.DESCRIPTION
    Provides a token-optimized interface to query GitHub issues across a single repository or the entire DiGi
    ecosystem. Automatically normalizes shorthand label names to the standard 21-label taxonomy, formats results
    compactly to save tokens, and supports JSON output and detailed inspection when needed.

.PARAMETER Repo
    Optional target repository name (e.g. 'DiGi.Core', 'DiGi.GIS.PostgreSQL', or 'DiGi-Organization/DiGi.Core').
    If omitted or set to 'all', searches across all repositories belonging to the owner.

.PARAMETER Labels
    One or more labels or shorthands to filter by (e.g. 'ai: standard', 'priority: high', 'standard, high', 'bug').
    Can be passed as array, comma-separated string, or space-separated arguments. Shorthands like 'high', 'standard',
    'bug', 'in-progress' are automatically mapped to canonical taxonomy names.

.PARAMETER State
    Filter by issue state: 'open' (default), 'closed', or 'all'.

.PARAMETER Search
    Optional free-text search term to match against issue titles and descriptions.

.PARAMETER Issue
    Optional specific issue number to retrieve (e.g. -Issue 42 -Repo "DiGi.GIS.PostgreSQL").

.PARAMETER Limit
    Maximum number of issues to return (default: 30).

.PARAMETER Sort
    Sort field: 'updated' (default), 'created', or 'comments'.

.PARAMETER Order
    Sort order: 'desc' (default) or 'asc'.

.PARAMETER Detail
    If specified, includes a short snippet of the issue description body.

.PARAMETER Full
    If specified with -Detail or -Issue, outputs the full issue body.

.PARAMETER Json
    If specified, outputs minimal, structured JSON instead of formatted text.

.PARAMETER ExtraArgs
    Captures any remaining unbound arguments (e.g. when multiple labels are passed with spaces after commas).

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.Core" -Labels "ai: standard", "priority: high"

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Labels "standard, high"

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Search "subdivision"

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Repo "DiGi.GIS.PostgreSQL" -Issue 42 -Detail

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File ".\FilterIssues.ps1" -Labels "critical" -Json
#>
[CmdletBinding(PositionalBinding = $false)]
param (
    [string]$Repo,

    [Alias("Label")]
    [string[]]$Labels,

    [ValidateSet("open", "closed", "all")]
    [string]$State = "open",

    [Alias("Query")]
    [string]$Search,

    [int]$Issue,

    [int]$Limit = 30,

    [ValidateSet("updated", "created", "comments")]
    [string]$Sort = "updated",

    [ValidateSet("asc", "desc")]
    [string]$Order = "desc",

    [switch]$Detail,

    [switch]$Full,

    [switch]$Json,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"

# Determine GitHub owner from origin URL or fallback
$owner = "DiGi-Organization"
$currentRepoRemote = git config --get remote.origin.url 2>$null
if ($currentRepoRemote -match 'github\.com[:/]([^/]+)/') {
    $owner = $Matches[1]
}

# Standard DiGi 21-label taxonomy mapping for shorthands
$taxonomyMap = @{
    # AI Complexity
    "light"           = "ai: light"
    "standard"        = "ai: standard"
    "heavy"           = "ai: heavy"
    "ultra"           = "ai: ultra"

    # Priority
    "critical"        = "priority: critical"
    "high"            = "priority: high"
    "medium"          = "priority: medium"
    "low"             = "priority: low"

    # Type
    "bug"             = "type: bug"
    "feature"         = "type: feature"
    "enhancement"     = "type: enhancement"
    "performance"     = "type: performance"
    "refactor"        = "type: refactor"
    "breaking-change" = "type: breaking-change"
    "breaking"        = "type: breaking-change"
    "documentation"   = "type: documentation"
    "docs"            = "type: documentation"
    "doc"             = "type: documentation"
    "test"            = "type: test"
    "tests"           = "type: test"
    "maintenance"     = "type: maintenance"

    # Status
    "in-progress"     = "status: in-progress"
    "blocked"         = "status: blocked"
    "needs-review"    = "status: needs-review"
    "parked"          = "status: parked"
}

# Collect all label inputs from $Labels and $ExtraArgs
$allLabelInputs = @()
if ($Labels) { $allLabelInputs += $Labels }
if ($ExtraArgs) { $allLabelInputs += $ExtraArgs }

# Normalize labels (supporting comma-separated items and trailing punctuation)
$normalizedLabels = @()
if ($allLabelInputs.Count -gt 0) {
    $rawList = @()
    foreach ($item in $allLabelInputs) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($item.Contains(',')) {
            $rawList += $item.Split(',')
        } else {
            $rawList += $item
        }
    }

    foreach ($lbl in $rawList) {
        $trimmed = $lbl.Trim().Trim(',').Trim('"').Trim("'").Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $lower = $trimmed.ToLower()
        if ($taxonomyMap.ContainsKey($lower)) {
            $normalizedLabels += $taxonomyMap[$lower]
        } else {
            $normalizedLabels += $trimmed
        }
    }
}

# Normalize repository identifier
$repoIdentifier = $null
if ($Repo -and $Repo -ne "all") {
    if ($Repo.Contains("/")) {
        $repoIdentifier = $Repo
    } else {
        $repoIdentifier = "$owner/$Repo"
    }
}

# Check gh CLI availability
$ghVersion = gh --version 2>$null
if ($LASTEXITCODE -ne 0 -or -not $ghVersion) {
    Write-Error "GitHub CLI ('gh') is not installed or not available in PATH. Please install GitHub CLI."
    exit 1
}

# Mode 1: Fetch single specific issue
if ($Issue -gt 0) {
    if (-not $repoIdentifier) {
        Write-Error "-Issue parameter requires a specific target repository via -Repo (e.g. -Repo 'DiGi.Core' -Issue $Issue)."
        exit 1
    }

    $jsonFields = "number,title,state,labels,url,body,createdAt,updatedAt"
    $issueJsonRaw = (& gh issue view $Issue --repo $repoIdentifier --json $jsonFields 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($issueJsonRaw)) {
        Write-Error "Failed to retrieve issue #$Issue from repository '$repoIdentifier'."
        exit 1
    }

    $singleIssue = $issueJsonRaw | ConvertFrom-Json
    $labelNames = if ($singleIssue.labels) { @($singleIssue.labels | ForEach-Object { $_.name }) } else { @() }
    $shortRepo = if ($repoIdentifier.Contains("/")) { $repoIdentifier.Split("/")[1] } else { $repoIdentifier }

    if ($Json) {
        $outputObj = [ordered]@{
            Number    = $singleIssue.number
            Repo      = $shortRepo
            Title     = $singleIssue.title
            State     = $singleIssue.state
            Labels    = $labelNames
            Url       = $singleIssue.url
            CreatedAt = $singleIssue.createdAt
            UpdatedAt = $singleIssue.updatedAt
            Body      = $singleIssue.body
        }
        $outputObj | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }

    $stateColor = if ($singleIssue.state -eq "OPEN") { "Green" } else { "DarkYellow" }
    Write-Host "`n#$($singleIssue.number) [$shortRepo] $($singleIssue.title)" -ForegroundColor Cyan
    Write-Host "  State:   " -NoNewline -ForegroundColor Gray
    Write-Host "$($singleIssue.state)" -ForegroundColor $stateColor
    Write-Host "  Labels:  $($labelNames -join ', ')" -ForegroundColor Yellow
    Write-Host "  URL:     $($singleIssue.url)" -ForegroundColor DarkGray
    Write-Host "  Updated: $($singleIssue.updatedAt)" -ForegroundColor DarkGray

    if ($Detail -or $Full) {
        Write-Host "`n--- Description ---" -ForegroundColor DarkCyan
        if (-not [string]::IsNullOrWhiteSpace($singleIssue.body)) {
            if ($Full) {
                Write-Host $singleIssue.body
            } else {
                $lines = $singleIssue.body -split "`r?`n"
                $preview = ($lines | Select-Object -First 10) -join "`n"
                Write-Host $preview
                if ($lines.Count -gt 10) {
                    Write-Host "`n[... $(($lines.Count - 10)) more lines truncated. Use -Full to view complete body ...]" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Host "(No description provided)" -ForegroundColor DarkGray
        }
    }
    exit 0
}

# Mode 2: Search / list issues
$ghArgs = @("search", "issues")

if ($repoIdentifier) {
    $ghArgs += @("--repo", $repoIdentifier)
} else {
    $ghArgs += @("--owner", $owner)
}

if ($State -ne "all") {
    $ghArgs += @("--state", $State)
}

if ($Search) {
    $ghArgs += $Search
}

foreach ($lbl in $normalizedLabels) {
    $ghArgs += @("--label", $lbl)
}

$ghArgs += @("--limit", $Limit.ToString())
$ghArgs += @("--sort", $Sort)
$ghArgs += @("--order", $Order)
$ghArgs += @("--json", "number,title,state,labels,url,body,createdAt,updatedAt,repository")

# Execute query
$rawOutput = (& gh @ghArgs 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI query failed. Command args: gh $($ghArgs -join ' ')"
    exit 1
}

$issues = @()
if (-not [string]::IsNullOrWhiteSpace($rawOutput)) {
    $parsed = $rawOutput | ConvertFrom-Json
    if ($parsed -is [System.Array]) {
        $issues = @($parsed)
    } elseif ($parsed) {
        $issues = @($parsed)
    }
}

# Output Mode: JSON
if ($Json) {
    $jsonList = @()
    foreach ($item in $issues) {
        $repoName = if ($item.repository -and $item.repository.name) {
            $item.repository.name
        } elseif ($repoIdentifier -and $repoIdentifier.Contains("/")) {
            $repoIdentifier.Split("/")[1]
        } else {
            $owner
        }

        $labelNames = if ($item.labels) { @($item.labels | ForEach-Object { $_.name }) } else { @() }
        $obj = [ordered]@{
            Number    = $item.number
            Repo      = $repoName
            Title     = $item.title
            State     = $item.state
            Labels    = $labelNames
            Url       = $item.url
            CreatedAt = $item.createdAt
            UpdatedAt = $item.updatedAt
        }
        if ($Detail -or $Full) {
            $obj["Body"] = $item.body
        }
        $jsonList += [PSCustomObject]$obj
    }

    if ($jsonList.Count -eq 0) {
        Write-Output "[]"
    } else {
        $jsonList | ConvertTo-Json -Depth 5 -Compress
    }
    exit 0
}

# Output Mode: Formatted text (Ultra Token-Efficient)
$scopeDesc = if ($repoIdentifier) { $repoIdentifier } else { "all repositories ($owner/*)" }
$labelDesc = if ($normalizedLabels.Count -gt 0) { " [Labels: $($normalizedLabels -join ', ')]" } else { "" }
$searchDesc = if ($Search) { " [Search: '$Search']" } else { "" }

Write-Host "Found $($issues.Count) issue(s) in $scopeDesc (State: $State)$labelDesc$searchDesc`n" -ForegroundColor Cyan

if ($issues.Count -eq 0) {
    Write-Host "No issues matched the specified criteria." -ForegroundColor DarkGray
    exit 0
}

foreach ($item in $issues) {
    $repoName = if ($item.repository -and $item.repository.name) {
        $item.repository.name
    } elseif ($repoIdentifier -and $repoIdentifier.Contains("/")) {
        $repoIdentifier.Split("/")[1]
    } else {
        "Unknown"
    }

    $labelNames = if ($item.labels) { @($item.labels | ForEach-Object { $_.name }) } else { @() }
    $labelStr = if ($labelNames.Count -gt 0) { " ($($labelNames -join ', '))" } else { "" }
    $stateMarker = if ($State -eq "all" -and $item.state -ne "OPEN") { " [CLOSED]" } else { "" }

    Write-Host "#$($item.number)" -NoNewline -ForegroundColor Yellow
    Write-Host " [$repoName]$stateMarker " -NoNewline -ForegroundColor DarkCyan
    Write-Host "$($item.title)" -ForegroundColor White
    Write-Host "  $($item.url)$labelStr" -ForegroundColor DarkGray

    if ($Detail -or $Full) {
        if (-not [string]::IsNullOrWhiteSpace($item.body)) {
            if ($Full) {
                Write-Host "  Description: $($item.body)" -ForegroundColor Gray
            } else {
                $lines = ($item.body -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $preview = if ($lines.Count -gt 0) { $lines[0] } else { "" }
                if ($preview.Length -gt 160) {
                    $preview = $preview.Substring(0, 157) + "..."
                }
                Write-Host "  Preview: $preview" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
}
