<#
.SYNOPSIS
    Summarizes AddressPoint import requests from the DiGi WebAPI host logs (DiGi.GIS.PostgreSQL.UI#31).

.DESCRIPTION
    Run on the DATABASE SERVER (the machine that runs api.digiproject.uk), because that is where the
    AddressPointController writes the per-request counters. The tray task's AddressPoints_Import_Report.txt
    does not carry them.

    Logs are Serilog daily files named log-yyyyMMdd[_nnn].txt inside a 'logs' folder next to the logging
    assembly (the host and, with per-assembly routing, each extension such as extensions\gis), so the
    script searches -Root recursively for every such 'logs' folder.

    One row is produced per UpdateItemsByCountyIdsAsync request: timestamps, county ids (widened to every
    county part when the server did so), point count and Inside / Nearest / Unmatched / Outside / Skipped / Written.
    The import is sequential, so request lines do not interleave; a request that overlaps another is dropped
    from the output and counted in the warning at the end.

    The log only has county IDS. To group by voivodeship, pass the tray task's AddressPoints_Import_Report.txt
    file(s) with -ReportPath: its lines 'County <code>: posted N points (county ids a, b)' map ids to the
    4-digit county code, whose first two digits are the voivodeship. The report is on the machine that ran the
    tray task, so copy it next to the logs first.

.PARAMETER Root
    Software directory to search for 'logs' folders (the server's installation root).

.PARAMETER From
    Only requests logged at or after this moment (default: no lower bound).

.PARAMETER Until
    Only requests logged before this moment (default: no upper bound).

.PARAMETER ReportPath
    Optional AddressPoints_Import_Report.txt file(s) used to map county ids to county codes / voivodeships.

.PARAMETER OutputDirectory
    Where the CSV files are written (default: current directory). Both are written, never deployed.

.EXAMPLE
    .\SummarizeAddressPointImportLog.ps1 -Root "<software directory>" -From "2026-10-24" -Until "2026-10-27" -ReportPath ".\AddressPoints_Import_Report.txt"
#>
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Nullable[DateTimeOffset]]$From = $null,
    [Nullable[DateTimeOffset]]$Until = $null,
    [string[]]$ReportPath = @(),
    [string]$OutputDirectory = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Root)) { throw "Root not found: $Root" }

$logFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'log-*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq 'logs' }
# Filter by the date in the file name: the size and write time of a file the running service holds open are stale in a directory listing.
if ($null -ne $From) {
    $logFiles = $logFiles | Where-Object { $_.Name -match '^log-(\d{8})' -and [datetime]::ParseExact($Matches[1], 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture) -ge $From.Date.AddDays(-1) }
}
$logFiles = $logFiles | Sort-Object Name, FullName
if (-not $logFiles) { throw "No log-*.txt files found in 'logs' folders under $Root" }
Write-Host "Log files: $(@($logFiles).Count)"
foreach ($file in $logFiles) {
    # Real size from an open handle; the directory listing's Length is stale for a file the service has open.
    $probe = New-Object System.IO.FileStream($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { Write-Host "  $($file.FullName)  $([math]::Round($probe.Length / 1MB, 2)) MB" } finally { $probe.Dispose() }
}

$timestampPattern = '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} [+-]\d{2}:\d{2}) '
function ConvertTo-Timestamp([string]$Text) {
    [DateTimeOffset]::ParseExact($Text, 'yyyy-MM-dd HH:mm:ss.fff zzz', [Globalization.CultureInfo]::InvariantCulture)
}

$requests = New-Object System.Collections.Generic.List[object]
$dropped = 0
$current = $null

foreach ($file in $logFiles) {
    # The running service holds today's log open for writing, so open it with FileShare.ReadWrite.
    $stream = New-Object System.IO.FileStream($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)
    try {
    while ($null -ne ($line = $reader.ReadLine())) {
        if ($line.IndexOf('AddressPoint', [StringComparison]::Ordinal) -lt 0 -and
            $line.IndexOf('CountyIds', [StringComparison]::Ordinal) -lt 0 -and
            $line.IndexOf('Updating to database', [StringComparison]::Ordinal) -lt 0) { continue }

        if ($line -notmatch $timestampPattern) { continue }
        $stamp = $Matches[1]

        if ($line.Contains('AddressPointController:UpdateItemsByCountyIdsAsync started')) {
            if ($null -ne $current) { $dropped++ }
            $current = [ordered]@{ Started = (ConvertTo-Timestamp $stamp); Ended = $null; CountyIds = ''; Points = $null
                Inside = $null; Nearest = $null; Unmatched = $null; Outside = $null; Skipped = $null; Written = $null }
            continue
        }
        if ($null -eq $current) { continue }

        if ($line -match 'CountyIds provided: ([\d, ]*)') {
            if ([string]::IsNullOrEmpty($current.CountyIds)) { $current.CountyIds = $Matches[1].Trim() }
        }
        elseif ($line -match 'CountyIds widened to every part of their counties: ([\d, ]*)') {
            $current.CountyIds = $Matches[1].Trim()
        }
        elseif ($line -match 'Updating to database starting\. AddressPoints count: (\d+)') {
            $current.Points = [int]$Matches[1]
        }
        elseif ($line -match 'Updating to database ended\. Inside: (\d+), Nearest: (\d+), Unmatched: (\d+), Outside: (\d+), Skipped: (\d+), Written: (\d+)') {
            $current.Ended = ConvertTo-Timestamp $stamp
            $current.Inside = [int]$Matches[1]; $current.Nearest = [int]$Matches[2]; $current.Unmatched = [int]$Matches[3]
            $current.Outside = [int]$Matches[4]; $current.Skipped = [int]$Matches[5]; $current.Written = [long]$Matches[6]
            $requests.Add([pscustomobject]$current)
            $current = $null
        }
    }
    }
    finally { $reader.Dispose() }
}

$rows = $requests.ToArray()
if ($null -ne $From) { $rows = @($rows | Where-Object { $_.Started -ge $From }) }
if ($null -ne $Until) { $rows = @($rows | Where-Object { $_.Started -lt $Until }) }
if ($rows.Count -eq 0) { throw 'No completed AddressPoint update requests found in the selected logs and range.' }

# county id -> county code, from the tray task report(s)
$codeById = @{}
foreach ($path in $ReportPath) {
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^County (\d+): (?:posted \d+ points|FAILED.*) \(county ids ([\d, ]+)\)') {
            foreach ($id in ($Matches[2] -split ',\s*')) { $codeById[$id.Trim()] = $Matches[1] }
        }
    }
}

foreach ($row in $rows) {
    $codes = @(($row.CountyIds -split ',\s*') | Where-Object { $_ } | ForEach-Object { $codeById[$_] } | Where-Object { $_ } | Select-Object -Unique)
    $row | Add-Member -NotePropertyName CountyCode -NotePropertyValue ($codes -join ' ')
    $voivodeship = ''
    if ($codes.Count -gt 0) { $voivodeship = $codes[0].Substring(0, 2) }
    $row | Add-Member -NotePropertyName Voivodeship -NotePropertyValue $voivodeship
    $row | Add-Member -NotePropertyName Seconds -NotePropertyValue ([math]::Round(($row.Ended - $row.Started).TotalSeconds, 1))
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$requestsCsv = Join-Path $OutputDirectory 'AddressPoint_Import_Requests.csv'
$rows | Select-Object Started, Ended, Seconds, Voivodeship, CountyCode, CountyIds, Points, Inside, Nearest, Unmatched, Outside, Skipped, Written |
    Export-Csv -LiteralPath $requestsCsv -NoTypeInformation -Encoding UTF8

$summary = $rows | Group-Object Voivodeship | Sort-Object Name | ForEach-Object {
    $group = $_.Group
    $first = ($group | Sort-Object Started | Select-Object -First 1).Started
    $last = ($group | Sort-Object Ended | Select-Object -Last 1).Ended
    $busy = ($group | Measure-Object Seconds -Sum).Sum
    [pscustomobject]@{
        Voivodeship = if ($_.Name) { $_.Name } else { '(unmapped - pass -ReportPath)' }
        Requests = $group.Count
        Points = [long]($group | Measure-Object Points -Sum).Sum
        Inside = [long]($group | Measure-Object Inside -Sum).Sum
        Nearest = [long]($group | Measure-Object Nearest -Sum).Sum
        Unmatched = [long]($group | Measure-Object Unmatched -Sum).Sum
        Outside = [long]($group | Measure-Object Outside -Sum).Sum
        Skipped = [long]($group | Measure-Object Skipped -Sum).Sum
        Written = [long]($group | Measure-Object Written -Sum).Sum
        BusySeconds = [math]::Round($busy, 0)
        WallClock = ($last - $first).ToString('hh\:mm\:ss')
    }
}
$summaryCsv = Join-Path $OutputDirectory 'AddressPoint_Import_Summary.csv'
$summary | Export-Csv -LiteralPath $summaryCsv -NoTypeInformation -Encoding UTF8

$summary | Format-Table -AutoSize
$total = $summary | Measure-Object Points, Inside, Nearest, Unmatched, Outside, Skipped, Written -Sum
Write-Host ("TOTAL  requests {0}  " -f $rows.Count) -NoNewline
$total | ForEach-Object { Write-Host ("{0} {1}  " -f $_.Property, $_.Sum) -NoNewline }
Write-Host ''
if ($dropped -gt 0) { Write-Warning "$dropped request(s) started but never logged an 'ended' line (failed, timed out, or interleaved); they are not in the totals. Compare with the report's FAILED lines." }
Write-Host "Written: $requestsCsv"
Write-Host "Written: $summaryCsv"
Write-Host 'Outputs describe THIS server only - do not mix them with another machine''s logs.'
