<#
.SYNOPSIS
    Prints the signature and summary of the public members matching a pattern, from the generated API docs.

.DESCRIPTION
    Read-only. Every repository holds 'documentation/API/<AssemblyName>/<Namespace>.md', regenerated on build,
    with every public signature and <summary> - but a namespace page runs to hundreds of kilobytes. This script
    reads the pages and prints, per member whose fully qualified name matches -Match:
        <Fully.Qualified.Member(parameter types)>
          <signature on one line>  // <summary>
    so one lookup costs a few lines instead of a whole page. Open the '.cs' file only to edit it or to read
    internal logic. The docs are as fresh as the last build of the assembly.

.PARAMETER Assembly
    Assembly name = folder under 'documentation/API', e.g. "DiGi.Core". Searched in every 'DiGi.*' repository.
    An unknown name exits 2 and lists the assemblies whose name contains the text.

.PARAMETER Match
    Regular expression (case-insensitive) matched against the fully qualified member name,
    e.g. "Query\.Clone", "\.IReference$", "Classes\.SerializableObject\.".

.PARAMETER Max
    Maximum members printed (the rest is counted). Default: 40.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\GetApi.ps1" -Assembly "DiGi.Core" -Match "Query\.Clone"
#>
param (
    [string]$Assembly = "",

    [string]$Match = "",

    [int]$Max = 40
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path

if ($Assembly -eq "" -or $Match -eq "") {
    Write-Host "Pass -Assembly <name> and -Match <regular expression>." -ForegroundColor Red
    exit 2
}

$assemblyDirectories = @(Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*" | ForEach-Object { Join-Path $_.FullName "documentation\API\$Assembly" } | Where-Object { Test-Path $_ })
if ($assemblyDirectories.Count -eq 0) {
    Write-Host "No 'documentation/API/$Assembly' in any repository. Assemblies containing '$Assembly':" -ForegroundColor Red
    Get-ChildItem -Path $baseDir -Directory -Filter "DiGi.*" | ForEach-Object { Join-Path $_.FullName "documentation\API" } | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem -Path $_ -Directory } | Where-Object { $_.Name -like "*$Assembly*" } | ForEach-Object { Write-Host "  $($_.Name)" }
    exit 2
}

$pattern = New-Object System.Text.RegularExpressions.Regex($Match, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$anchor = New-Object System.Text.RegularExpressions.Regex("<a name='([^']+)'></a>")

function Remove-Markdown {
    param (
        [string]$Text
    )

    # '[Type](link 'title')' -> 'Type', then markdown escapes and HTML entities
    $plain = [regex]::Replace($Text, "\[([^\]]+)\]\([^)]*\)", '$1')
    $plain = [regex]::Replace($plain, '\\([.\-<>\[\]()_*#|`])', '$1')
    return $plain.Replace("&lt;", "<").Replace("&gt;", ">").Replace("&amp;", "&")
}

$found = 0
$printed = 0

foreach ($assemblyDirectory in $assemblyDirectories) {
    foreach ($page in Get-ChildItem -Path $assemblyDirectory -Filter "*.md") {
        $text = [System.IO.File]::ReadAllText($page.FullName) -replace "`r", ""
        $anchors = $anchor.Matches($text)

        for ($i = 0; $i -lt $anchors.Count; $i++) {
            $name = $anchors[$i].Groups[1].Value
            # Parameters and type parameters have their own anchors ('Member(...).name'): part of the member, not members
            if ($name -match '\)\.\w+$' -or -not $pattern.IsMatch($name)) {
                continue
            }

            $found++
            if ($printed -ge $Max) {
                continue
            }

            $start = $anchors[$i].Index + $anchors[$i].Length
            $end = $text.Length
            if ($i + 1 -lt $anchors.Count) {
                $end = $anchors[$i + 1].Index
            }
            $block = $text.Substring($start, $end - $start)

            # Summary = the paragraph between the heading and the signature
            $summary = ""
            $signature = ""
            $fence = $block.IndexOf('```csharp')
            $headingEnd = $block.IndexOf("`n", [Math]::Max(0, $block.IndexOf("## ")))
            if ($fence -ge 0) {
                $fenceEnd = $block.IndexOf('```', $fence + 9)
                if ($fenceEnd -gt $fence) {
                    $signature = ([regex]::Replace($block.Substring($fence + 9, $fenceEnd - $fence - 9), '\s+', ' ')).Trim()
                }
                if ($headingEnd -ge 0 -and $fence -gt $headingEnd) {
                    $summary = $block.Substring($headingEnd, $fence - $headingEnd)
                }
            } elseif ($headingEnd -ge 0) {
                $summary = $block.Substring($headingEnd)
            }
            $summary = ([regex]::Replace((Remove-Markdown $summary), '\s+', ' ')).Trim()

            Write-Host $name
            if ($signature -ne "" -and $summary -ne "") {
                Write-Host "  $signature  // $summary"
            } elseif ($signature -ne "") {
                Write-Host "  $signature"
            } elseif ($summary -ne "") {
                Write-Host "  // $summary"
            }
            $printed++
        }
    }
}

if ($found -eq 0) {
    Write-Host "No member of '$Assembly' matches '$Match'." -ForegroundColor Yellow
    exit 1
}

if ($found -gt $printed) {
    Write-Host ("{0} more match(es) not shown - narrow -Match or raise -Max." -f ($found - $printed)) -ForegroundColor Yellow
}

exit 0
