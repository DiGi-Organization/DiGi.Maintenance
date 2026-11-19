<#
.SYNOPSIS
    Runs the diagnosis of the OrtoDatas queue poison-retirement statement on the production queue table (DiGi.GIS.PostgreSQL#145).

.DESCRIPTION
    Run on the DATABASE SERVER, against the Storage database the GIS Web API uses: the plan of the
    5.6-million-row orto_datas_building_2d_reference_update on a development database says nothing about
    production (Coding - PostgreSQL.md section 6).

    One pass answers everything the issue asks before the fix is deployed and re-runs afterwards as its proof:
      1. the 20 entries of the county part and their attempts (are they exhausted at the ceiling, or not?);
      2. whether attempts is really NOT NULL (attnotnull from pg_attribute - a column that would still accept
         null needs a backfill before the sargable predicate is safe);
      3. the indexes the table carries;
      4. the queue-wide attempts distribution (how many entries are at the ceiling and would be retired);
      5. EXPLAIN (plan only - EXPLAIN never executes DML) of the retirement as it shipped before the fix
         (COALESCE, no index can serve it) and of the fixed statement (attempts >= 5, index on attempts);
      6. EXPLAIN (ANALYZE, BUFFERS) of the fixed statement inside a transaction that is rolled back, so the
         timing is real and nothing stays deleted - neither the 20 entries nor anything else the table held.

    Everything runs read-only or rolled back; the only statement that writes is rolled back. A claim or an
    acknowledgment running at the same moment can meet the briefly locked ceiling rows - the window is the
    duration of one statement, so expect this outside a download burst.

    The connection comes from the GIS_PostgreSQL_Storage.conf found under -Root (HOST, PORT, USERNAME, PASSWORD, DATABASE).
    The password is passed to psql through the process environment only and is never printed or written to the output.

    PASS: the fixed statement plans as an Index Scan on idx_orto_datas_building_2d_reference_update_attempts
    with no Seq Scan, and attempts reads attnotnull = true.

.PARAMETER Root
    Software directory searched for GIS_PostgreSQL_Storage.conf (ignored when -ConfPath is given).

.PARAMETER ConfPath
    Explicit path to the GIS_PostgreSQL_Storage.conf to use, when -Root finds more than one.

.PARAMETER CountyId
    County part whose queue entries are listed (default 17371 - part 17371 of the issue).

.PARAMETER OutputDirectory
    Where OrtoDatas_Retire_Explain.txt is written (default: the current directory).

.PARAMETER PsqlPath
    Path to psql.exe when it is neither on PATH nor under C:\Program Files\PostgreSQL\<version>\bin.

.EXAMPLE
    .\ExplainOrtoDatasRetire.ps1 -Root "<software directory>" -OutputDirectory "<folder>"
#>
param(
    [string]$Root,
    [string]$ConfPath,
    [int]$CountyId = 17371,
    [string]$OutputDirectory = (Get-Location).Path,
    [string]$PsqlPath
)

$ErrorActionPreference = 'Stop'

$queueTable = 'orto_datas_building_2d_reference_update'

if (-not $ConfPath) {
    if (-not $Root) { Write-Host 'Give -Root or -ConfPath.' -ForegroundColor Red; exit 2 }
    $confs = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'GIS_PostgreSQL_Storage.conf' -ErrorAction SilentlyContinue)
    if ($confs.Count -eq 0) { Write-Host "No GIS_PostgreSQL_Storage.conf found under $Root" -ForegroundColor Red; exit 2 }
    if ($confs.Count -gt 1) {
        $confs | ForEach-Object { Write-Host "  $($_.FullName)" }
        Write-Host 'More than one GIS_PostgreSQL_Storage.conf found; pass the one the Web API reads with -ConfPath.' -ForegroundColor Red
        exit 2
    }
    $ConfPath = $confs[0].FullName
}

$settings = @{}
foreach ($line in Get-Content -LiteralPath $ConfPath -Encoding UTF8) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) { continue }
    $key = $trimmed.Substring(0, $separator).Trim().ToUpperInvariant()
    $value = $trimmed.Substring($separator + 1).Trim().Trim('"')
    $settings[$key] = $value
}
foreach ($key in 'HOST', 'PORT', 'USERNAME', 'PASSWORD', 'DATABASE') {
    if (-not $settings.ContainsKey($key)) { Write-Host "$ConfPath has no $key" -ForegroundColor Red; exit 2 }
}

if (-not $PsqlPath) {
    $command = Get-Command psql -ErrorAction SilentlyContinue
    if ($command) { $PsqlPath = $command.Source }
    else {
        $PsqlPath = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $PsqlPath -or -not (Test-Path -LiteralPath $PsqlPath)) { Write-Host 'psql.exe not found; pass -PsqlPath.' -ForegroundColor Red; exit 2 }

Write-Host "Conf:     $ConfPath"
Write-Host "Database: $($settings['DATABASE']) on $($settings['HOST']):$($settings['PORT']) as $($settings['USERNAME'])"
Write-Host "psql:     $PsqlPath"

$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine('\pset pager off')
[void]$sql.AppendLine('SELECT version();')
[void]$sql.AppendLine("SELECT '$queueTable rows (estimate)' AS what, reltuples::bigint AS value FROM pg_class WHERE relname = '$queueTable';")
[void]$sql.AppendLine("SELECT 'ATTEMPTS_NOTNULL=' || attnotnull AS value FROM pg_attribute WHERE attrelid = '$queueTable'::regclass AND attname = 'attempts';")
[void]$sql.AppendLine("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = '$queueTable' ORDER BY indexname;")

# The 20 entries of the issue: their attempts decide whether they are poison (>= 5) or not.
[void]$sql.AppendLine("\echo ==== entries of county part $CountyId")
[void]$sql.AppendLine("SELECT id, county_id, reference, attempts, claimed_at, created_at FROM $queueTable WHERE county_id = $CountyId ORDER BY id;")
[void]$sql.AppendLine("\echo ==== attempts distribution, whole queue")
[void]$sql.AppendLine("SELECT attempts, count(*) FROM $queueTable GROUP BY attempts ORDER BY attempts;")

# Plan only: EXPLAIN without ANALYZE never executes the DELETE, so both predicates are safe to print.
[void]$sql.AppendLine("\echo ==== plan: retire as shipped before DiGi.GIS.PostgreSQL#145 (COALESCE, unsargable)")
[void]$sql.AppendLine("EXPLAIN DELETE FROM $queueTable WHERE COALESCE(attempts, 0) >= 5;")
[void]$sql.AppendLine("\echo ==== plan: retire after DiGi.GIS.PostgreSQL#145 (attempts >= 5, index on attempts)")
[void]$sql.AppendLine("EXPLAIN DELETE FROM $queueTable WHERE attempts >= 5;")

# Real timing of the fixed statement; the transaction is rolled back, so nothing stays deleted.
foreach ($run in 'first run', 'second run') {
    [void]$sql.AppendLine("\echo ==== timing (rolled back): retire after DiGi.GIS.PostgreSQL#145 / $run")
    [void]$sql.AppendLine('BEGIN;')
    [void]$sql.AppendLine("EXPLAIN (ANALYZE, BUFFERS) DELETE FROM $queueTable WHERE attempts >= 5;")
    [void]$sql.AppendLine('ROLLBACK;')
}

$sqlFile = Join-Path ([System.IO.Path]::GetTempPath()) ("explain_ortodatas_retire_{0}.sql" -f [guid]::NewGuid().ToString('N'))
[System.IO.File]::WriteAllText($sqlFile, $sql.ToString(), (New-Object System.Text.UTF8Encoding($false)))

if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$outFile = Join-Path $OutputDirectory 'OrtoDatas_Retire_Explain.txt'

$env:PGPASSWORD = $settings['PASSWORD']
$env:PGCLIENTENCODING = 'UTF8'
try {
    # stderr is NOT redirected: under $ErrorActionPreference = 'Stop' a native stderr line would throw.
    & $PsqlPath -h $settings['HOST'] -p $settings['PORT'] -U $settings['USERNAME'] -d $settings['DATABASE'] -v ON_ERROR_STOP=1 -X -f $sqlFile | Out-File -LiteralPath $outFile -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Write-Host "psql exited with $LASTEXITCODE; see $outFile" -ForegroundColor Red; exit 1 }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sqlFile -ErrorAction SilentlyContinue
}

$text = Get-Content -LiteralPath $outFile -Raw
$sections = [regex]::Matches($text, '(?s)==== (?<label>[^\r\n]+)\r?\n.*?(?=\r?\n==== |\z)')

$nullColumn = $text -match 'ATTEMPTS_NOTNULL=f'
$hasAttemptsIndex = $text -match 'idx_orto_datas_building_2d_reference_update_attempts'

foreach ($section in $sections) {
    $label = $section.Groups['label'].Value
    $body = $section.Value
    if ($label.StartsWith('entries of ')) {
        $rowCount = ([regex]::Matches($body, '(?m)^\s*\d+\s')).Count
        Write-Host ("INFO {0}: {1} row(s) listed" -f $label, $rowCount) -ForegroundColor Cyan
        continue
    }
    if ($label.StartsWith('attempts distribution')) { continue }
    $indexScan = $body -match 'idx_orto_datas_building_2d_reference_update_attempts'
    $seqScan = $body -match 'Seq Scan on ' + $queueTable
    $execution = [regex]::Match($body, 'Execution Time: ([\d.]+) ms').Groups[1].Value
    if ($label.StartsWith('plan:') -or $label.StartsWith('timing')) {
        Write-Host ("INFO {0,-78} index={1} seqscan={2} execution={3} ms" -f $label, $indexScan, $seqScan, $execution) -ForegroundColor Cyan
    }
    else {
        Write-Host ("INFO {0}" -f $label) -ForegroundColor Cyan
    }
}

if ($nullColumn) { Write-Host 'WARN attempts is nullable on this table: run UPDATE ... SET attempts = 0 WHERE attempts IS NULL and ALTER ... SET NOT NULL before deploying the sargable predicate.' -ForegroundColor Yellow }
if ($hasAttemptsIndex) { Write-Host 'PASS the attempts index exists on this table (the fixed statement is served by it).' -ForegroundColor Green }
else { Write-Host 'FAIL the attempts index does not exist here yet - the claim path creates it on the first queue call after the fix is deployed.' -ForegroundColor Yellow }

Write-Host ''
Write-Host "Full output written to: $outFile"
Write-Host "The output describes THIS server's database only - do not mix it with a development database's plan."
exit 0
