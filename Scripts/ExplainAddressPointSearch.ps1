<#
.SYNOPSIS
    Runs EXPLAIN (ANALYZE, BUFFERS) on the address search statement of the production address_point table (DiGi.GIS.PostgreSQL#104).

.DESCRIPTION
    Run on the DATABASE SERVER, against the Main database the GIS Web API uses: the plan of a table of 8.6 M rows
    on a development database says nothing about production (Coding - PostgreSQL.md section 6).

    The statement is the one in AddressPointPostgreSQLConverter.GetAddressPointMatchesByAddressAsync, with the
    parameters written as literals because EXPLAIN cannot take them in psql. The text is already normalised the way
    Query.SearchText does (lower case, no diacritics, single spaces). Each statement runs twice - the first read may be
    cold, the second warm - and inside a READ ONLY transaction that is rolled back, so nothing is written.

    Every statement runs once per VARIANT, so candidate fixes can be compared on one set of numbers
    (DiGi.GIS.PostgreSQL#112): the shipped threshold 0.4 first (SET LOCAL - scoped to that one transaction, nothing
    persisted), the previous default 0.3, the rejected 0.5, and a larger work_mem. The county-narrowed case gets its
    county_id with \gset (the county part with the most matches for the street). Under each variant the typo and the
    partial-name case also run their plain SELECT and print a RECALL line: whether the top 20 still holds a genuine
    match. A threshold that loses the typo is not acceptable.

    The connection comes from the GIS_PostgreSQL_Main.conf found under -Root (HOST, PORT, USERNAME, PASSWORD, DATABASE).
    The password is passed to psql through the process environment only and is never printed or written to the output.

    PASS: the plan of the search statement contains 'idx_address_point_search_text' and no 'Seq Scan on address_point'.

.PARAMETER Root
    Software directory searched for GIS_PostgreSQL_Main.conf (ignored when -ConfPath is given).

.PARAMETER ConfPath
    Explicit path to the GIS_PostgreSQL_Main.conf to use, when -Root finds more than one.

.PARAMETER OutputDirectory
    Where AddressPoint_Search_Explain.txt is written (default: the current directory).

.PARAMETER PsqlPath
    Path to psql.exe when it is neither on PATH nor under C:\Program Files\PostgreSQL\<version>\bin.

.EXAMPLE
    .\ExplainAddressPointSearch.ps1 -Root "<software directory>" -OutputDirectory "<folder>"
#>
param(
    [string]$Root,
    [string]$ConfPath,
    [string]$OutputDirectory = (Get-Location).Path,
    [string]$PsqlPath
)

$ErrorActionPreference = 'Stop'

if (-not $ConfPath) {
    if (-not $Root) { throw 'Give -Root or -ConfPath.' }
    $confs = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'GIS_PostgreSQL_Main.conf' -ErrorAction SilentlyContinue)
    if ($confs.Count -eq 0) { throw "No GIS_PostgreSQL_Main.conf found under $Root" }
    if ($confs.Count -gt 1) {
        $confs | ForEach-Object { Write-Host "  $($_.FullName)" }
        throw 'More than one GIS_PostgreSQL_Main.conf found; pass the one the Web API reads with -ConfPath.'
    }
    $ConfPath = $confs[0].FullName
}

$settings = @{}
foreach ($line in Get-Content -LiteralPath $ConfPath -Encoding UTF8) {
    if ($line -match '^\s*([A-Za-z_]+)\s*=\s*"?([^"]*)"?\s*$') { $settings[$Matches[1].ToUpperInvariant()] = $Matches[2] }
}
foreach ($key in 'HOST', 'PORT', 'USERNAME', 'PASSWORD', 'DATABASE') {
    if (-not $settings.ContainsKey($key)) { throw "$ConfPath has no $key" }
}

if (-not $PsqlPath) {
    $command = Get-Command psql -ErrorAction SilentlyContinue
    if ($command) { $PsqlPath = $command.Source }
    else {
        $PsqlPath = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $PsqlPath -or -not (Test-Path -LiteralPath $PsqlPath)) { throw 'psql.exe not found; pass -PsqlPath.' }

Write-Host "Conf:     $ConfPath"
Write-Host "Database: $($settings['DATABASE']) on $($settings['HOST']):$($settings['PORT']) as $($settings['USERNAME'])"
Write-Host "psql:     $PsqlPath"

# (label, normalised text, house number or $null, narrow by county_id, expected street for the recall line or $null)
$cases = @(
    @{ Label = 'street name, 13 letters';            Text = 'marszalkowska';  House = $null; County = $false; Expected = $null },
    @{ Label = 'typo';                               Text = 'marszalkowsak';  House = $null; County = $false; Expected = 'marszalkowska' },
    @{ Label = 'partial name';                       Text = 'pawla';          House = $null; County = $false; Expected = 'pawla' },
    @{ Label = 'street name with a house number';    Text = 'marszalkowska';  House = '12';  County = $false; Expected = $null },
    @{ Label = 'street name narrowed by county_id';  Text = 'marszalkowska';  House = $null; County = $true;  Expected = $null }
)

# (label, SET LOCAL statements run inside each READ ONLY transaction, before the statement they tune)
# The first variant is what AddressPointPostgreSQLConverter now ships - SET LOCAL 0.4 inside its own short
# transaction (DiGi.GIS.PostgreSQL#112). The others are the comparison matrix the decision was taken from.
$variants = @(
    @{ Label = 'threshold 0.4 (as shipped)';                  Set = @("SET LOCAL pg_trgm.similarity_threshold = '0.4';") },
    @{ Label = 'threshold 0.3 (previous default)';            Set = @() },
    @{ Label = 'threshold 0.5 (rejected, loses Warszawa typo rows)'; Set = @("SET LOCAL pg_trgm.similarity_threshold = '0.5';") },
    @{ Label = 'work_mem 64MB (measured, no effect)';         Set = @("SET LOCAL work_mem = '64MB';") }
)

function New-AddressSearchStatement($case) {
    $text = $case.Text.Replace("'", "''")
    $house = ''
    $orderHouse = ''
    if ($case.House) {
        $h = $case.House.ToLowerInvariant().Replace("'", "''")
        $house = "AND (lower(house_number) = '$h' OR (left(lower(house_number), length('$h')) = '$h' AND substr(lower(house_number), length('$h') + 1, 1) !~ '[0-9]'))"
        $orderHouse = "(lower(house_number) = '$h') DESC,"
    }
    # :county_narrow is a psql variable filled in below with \gset; it is a bare number, never a quoted literal.
    $county = if ($case.County) { 'AND county_id = :county_narrow' } else { '' }
    return "SELECT object FROM address_point WHERE (search_text % '$text' OR search_text LIKE '%$text%') $house $county ORDER BY similarity(search_text, '$text') DESC, $orderHouse house_number, reference_id LIMIT 20;"
}

$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine('\pset pager off')
[void]$sql.AppendLine('SELECT version();')
[void]$sql.AppendLine("SELECT 'address_point rows (estimate)' AS what, reltuples::bigint AS value FROM pg_class WHERE relname = 'address_point';")
[void]$sql.AppendLine("SELECT 'pg_trgm.similarity_threshold (null = default 0.3)' AS what, current_setting('pg_trgm.similarity_threshold', true) AS value;")
[void]$sql.AppendLine("SELECT 'work_mem (server default unless configured)' AS what, current_setting('work_mem') AS value;")
[void]$sql.AppendLine("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'address_point' ORDER BY indexname;")
# The county part the narrowed case filters on: the one with the most matches for the street. ORDER BY makes the LIMIT deterministic.
[void]$sql.AppendLine("SELECT COALESCE((SELECT county_id FROM address_point WHERE search_text LIKE '%marszalkowska%' GROUP BY county_id ORDER BY count(*) DESC, county_id LIMIT 1), -1) AS county_narrow \gset")
[void]$sql.AppendLine("\echo county_id used by the narrowed case = :county_narrow")

foreach ($variant in $variants) {
    foreach ($case in $cases) {
        $statement = New-AddressSearchStatement $case
        foreach ($run in 'first run', 'second run') {
            [void]$sql.AppendLine("\echo ==== $($variant.Label) / $($case.Label) / $run")
            [void]$sql.AppendLine('BEGIN READ ONLY;')
            foreach ($set in $variant.Set) { [void]$sql.AppendLine($set) }
            [void]$sql.AppendLine("EXPLAIN (ANALYZE, BUFFERS) $statement")
            [void]$sql.AppendLine('ROLLBACK;')
        }
    }

    # Recall under this variant's settings: does the top 20 still hold a row containing the expected street? The typo's
    # own LIKE branch matches no real row, so a genuine match can only come from the % branch - that is what is tested.
    foreach ($case in $cases) {
        if (-not $case.Expected) { continue }
        $text = $case.Text.Replace("'", "''")
        $expected = $case.Expected
        [void]$sql.AppendLine("\echo ==== recall / $($variant.Label) / $($case.Label)")
        [void]$sql.AppendLine('BEGIN READ ONLY;')
        foreach ($set in $variant.Set) { [void]$sql.AppendLine($set) }
        [void]$sql.AppendLine("SELECT count(*) AS recall_rows, bool_or(search_text LIKE '%$expected%') AS recall_expected FROM (SELECT search_text FROM address_point WHERE (search_text % '$text' OR search_text LIKE '%$text%') ORDER BY similarity(search_text, '$text') DESC, house_number, reference_id LIMIT 20) AS top \gset")
        [void]$sql.AppendLine("\echo RECALL $($variant.Label) / $($case.Label) -> rows=:recall_rows expected_found=:recall_expected")
        [void]$sql.AppendLine('ROLLBACK;')
    }
}

$sqlFile = Join-Path ([System.IO.Path]::GetTempPath()) ("explain_address_point_{0}.sql" -f [guid]::NewGuid().ToString('N'))
[System.IO.File]::WriteAllText($sqlFile, $sql.ToString(), (New-Object System.Text.UTF8Encoding($false)))

if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$outFile = Join-Path $OutputDirectory 'AddressPoint_Search_Explain.txt'

$env:PGPASSWORD = $settings['PASSWORD']
$env:PGCLIENTENCODING = 'UTF8'
try {
    & $PsqlPath -h $settings['HOST'] -p $settings['PORT'] -U $settings['USERNAME'] -d $settings['DATABASE'] -v ON_ERROR_STOP=1 -X -f $sqlFile 2>&1 | Out-File -LiteralPath $outFile -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "psql exited with $LASTEXITCODE; see $outFile" }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sqlFile -ErrorAction SilentlyContinue
}

$text = Get-Content -LiteralPath $outFile -Raw
$searchPlans = [regex]::Matches($text, '(?s)==== (?<label>[^\r\n]+)\r?\n.*?(?=\r?\n==== |\z)')
Write-Host ''
foreach ($plan in $searchPlans) {
    $label = $plan.Groups['label'].Value
    if ($label.StartsWith('recall / ')) { continue }  # reported from the RECALL lines below
    $body = $plan.Value
    $usesIndex = $body.Contains('idx_address_point_search_text')
    $seqScan = $body.Contains('Seq Scan on address_point')
    $execution = [regex]::Match($body, 'Execution Time: ([\d.]+) ms').Groups[1].Value
    $verdict = if ($usesIndex -and -not $seqScan) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0,-4} {1,-72} index={2} seqscan={3} execution={4} ms" -f $verdict, $label, $usesIndex, $seqScan, $execution)
}

# Recall of the typo and the partial-name case under each variant: does the top 20 still hold the expected street?
foreach ($line in Get-Content -LiteralPath $outFile) {
    if ($line -match '^RECALL (?<label>.+) -> rows=(?<rows>\d+) expected_found=(?<found>\S+)') {
        $found = if ($Matches['found'] -eq 't') { 'YES' } else { 'NO!!' }
        Write-Host ("{0,-4} {1,-72} top20 rows={2}" -f $found, $Matches['label'], $Matches['rows'])
    }
}
Write-Host ''
Write-Host "Full plans written to: $outFile"
Write-Host 'The output describes THIS server''s database only - do not mix it with a development database''s plan.'
