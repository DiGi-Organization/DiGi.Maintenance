<#
.SYNOPSIS
    Builds the library under test, runs one xUnit project and prints only the counts and the failed facts.

.DESCRIPTION
    DiGi test projects reference the library under test by HintPath, so 'dotnet test' never rebuilds it
    ('Coding - Automatic Tests.md'): pass every changed library with -Library and it is built first, one node
    ('-m:1'). The test run writes a TRX file to a temporary folder; the script prints
        TESTS <project>: <passed> passed, <failed> failed, <skipped> skipped (<seconds> s)
    followed, per failed fact, by its name, the first lines of its message and the first stack frame with a
    source line. A build failure prints the de-duplicated compiler diagnostics instead of the raw log.
    Exit codes: 0 all passed, 1 a build or a fact failed, 2 invalid invocation.

.PARAMETER Project
    The xUnit project (.csproj) or its folder.

.PARAMETER Library
    Library projects (.csproj) to build before the test run, in dependency order.

.PARAMETER Filter
    A 'dotnet test --filter' expression, e.g. "FullyQualifiedName~SerializationCheck".

.PARAMETER Configuration
    Build configuration. Default: Debug.

.PARAMETER MessageLines
    Lines of each failure message to print. Default: 4.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\TestSummary.ps1" -Library "..\..\DiGi.Core\DiGi.Core\DiGi.Core.csproj" -Project "..\..\DiGi.Core\DiGi.Core.xUnit"
#>
param (
    [string]$Project = "",

    [string[]]$Library = @(),

    [string]$Filter = "",

    [string]$Configuration = "Debug",

    [int]$MessageLines = 4
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path

if ($Project -eq "" -or -not (Test-Path $Project)) {
    Write-Host "Pass -Project <xUnit .csproj or its folder>. Not found: '$Project'" -ForegroundColor Red
    exit 2
}

foreach ($libraryPath in $Library) {
    if (-not (Test-Path $libraryPath)) {
        Write-Host "Library project not found: '$libraryPath'" -ForegroundColor Red
        exit 2
    }
}

$Project = (Resolve-Path $Project).Path

# 'file(line,col): error CS0000: message [project]' -> 'error CS0000 file:line message', de-duplicated
function Get-Diagnostics {
    param (
        [object[]]$Lines
    )

    $seen = @{}
    $result = @()
    foreach ($line in $Lines) {
        $text = [string]$line
        $diagnostic = ""
        $located = [regex]::Match($text, '^\s*(?:\d+>)?(?<file>[^(]+?)\((?<line>\d+)(?:,\d+)*\)\s*:\s*(?<severity>error|warning)\s+(?<code>\w+)\s*:\s*(?<message>.*?)(?:\s*\[[^\]]+\])?\s*$')
        if ($located.Success) {
            $file = $located.Groups['file'].Value.Trim()
            if ($file.StartsWith($baseDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $file = $file.Substring($baseDir.Length).TrimStart('\')
            }
            $diagnostic = "{0} {1} {2}:{3} {4}" -f $located.Groups['severity'].Value, $located.Groups['code'].Value, $file, $located.Groups['line'].Value, $located.Groups['message'].Value
        } else {
            $general = [regex]::Match($text, '^\s*(?:\d+>)?[^:]*?\s*:\s*(?<severity>error|warning)\s+(?<code>\w+)\s*:\s*(?<message>.*?)(?:\s*\[[^\]]+\])?\s*$')
            if (-not $general.Success) {
                continue
            }
            $diagnostic = "{0} {1} {2}" -f $general.Groups['severity'].Value, $general.Groups['code'].Value, $general.Groups['message'].Value
        }

        if (-not $seen.ContainsKey($diagnostic)) {
            $seen[$diagnostic] = $true
            $result += $diagnostic
        }
    }

    return $result
}

foreach ($libraryPath in $Library) {
    $libraryPath = (Resolve-Path $libraryPath).Path
    $buildOutput = & dotnet build $libraryPath -c $Configuration -m:1 --nologo -v q
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("BUILD FAIL {0}" -f (Split-Path -Leaf $libraryPath)) -ForegroundColor Red
        @(Get-Diagnostics -Lines $buildOutput) | Where-Object { $_.StartsWith("error") } | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
}

$resultsDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("DiGi.TestSummary." + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null

try {
    $testArguments = @("test", $Project, "-c", $Configuration, "--nologo", "-v", "q", "--logger", "trx;LogFileName=result.trx", "--results-directory", $resultsDirectory)
    if ($Filter -ne "") {
        $testArguments += @("--filter", $Filter)
    }

    $testOutput = & dotnet @testArguments
    $testExitCode = $LASTEXITCODE

    $projectName = (Split-Path -Leaf $Project) -replace '\.csproj$', ''
    $trxFiles = @(Get-ChildItem -Path $resultsDirectory -Filter "*.trx" -Recurse)

    if ($trxFiles.Count -eq 0) {
        # No result file: the test project did not build, or no fact matched the filter
        $diagnostics = @(@(Get-Diagnostics -Lines $testOutput) | Where-Object { $_.StartsWith("error") })
        if ($diagnostics.Count -gt 0 -or $testExitCode -ne 0) {
            Write-Host "BUILD FAIL $projectName" -ForegroundColor Red
            $diagnostics | ForEach-Object { Write-Host "  $_" }
            exit 1
        }

        Write-Host "TESTS ${projectName}: no fact ran (filter matched nothing?)" -ForegroundColor Yellow
        exit 1
    }

    $passed = 0
    $failed = 0
    $skipped = 0
    $seconds = 0.0
    $failures = @()

    foreach ($trxFile in $trxFiles) {
        [xml]$trx = [System.IO.File]::ReadAllText($trxFile.FullName)
        $counters = $trx.TestRun.ResultSummary.Counters
        $passed += [int]$counters.passed
        $failed += [int]$counters.failed
        $skipped += [int]$counters.total - [int]$counters.executed

        $times = $trx.TestRun.Times
        if ($times -and $times.start -and $times.finish) {
            $seconds += ([datetimeoffset]$times.finish - [datetimeoffset]$times.start).TotalSeconds
        }

        foreach ($unitTestResult in @($trx.TestRun.Results.UnitTestResult)) {
            if ($null -eq $unitTestResult -or $unitTestResult.outcome -ne "Failed") {
                continue
            }
            $failures += $unitTestResult
        }
    }

    if ($passed + $failed + $skipped -eq 0) {
        Write-Host "TESTS ${projectName}: no fact ran (filter matched nothing?)" -ForegroundColor Yellow
        exit 1
    }

    $color = "Green"
    if ($failed -gt 0) {
        $color = "Red"
    }
    Write-Host ("TESTS {0}: {1} passed, {2} failed, {3} skipped ({4:0.0} s)" -f $projectName, $passed, $failed, $skipped, $seconds) -ForegroundColor $color

    foreach ($failure in $failures) {
        Write-Host ("  FAIL {0}" -f $failure.testName)

        $errorInfo = $failure.Output.ErrorInfo
        $message = [string]$errorInfo.Message
        $shown = 0
        foreach ($messageLine in ($message -replace "`r", "") -split "`n") {
            if ($messageLine.Trim() -eq "") {
                continue
            }
            if ($shown -ge $MessageLines) {
                break
            }
            Write-Host ("    " + $messageLine.TrimEnd())
            $shown++
        }

        foreach ($frame in (([string]$errorInfo.StackTrace) -replace "`r", "") -split "`n") {
            $source = [regex]::Match($frame, ' in (?<file>.+):line (?<line>\d+)')
            if (-not $source.Success) {
                continue
            }
            $file = $source.Groups['file'].Value
            if ($file.StartsWith($baseDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $file = $file.Substring($baseDir.Length).TrimStart('\')
            }
            Write-Host ("    at {0}:{1}" -f $file, $source.Groups['line'].Value)
            break
        }
    }

    if ($failed -gt 0 -or $testExitCode -ne 0) {
        exit 1
    }

    exit 0
} finally {
    Remove-Item $resultsDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
