<#
.SYNOPSIS
    Checks the coding rules no compiler or analyzer enforces, and prints one line per violation.

.DESCRIPTION
    Read-only. Text-based checks over one repository, so an agent does not have to read files to verify them:
      OnePublicMethod   a file in a Query/Modify/Create folder declares public static methods of more than one name
      PrivateMethod     a file in a Query/Modify/Create folder declares a private static method
      QueryGetPrefix    a public method in a Query folder is named Get... (only Is/Has/Try prefixes are allowed)
      XunitUsing        'using Xunit;' or 'using DiGi.Core.xUnit;' in a C# file
      TodoMarker        a TODO comment without a '[MarkerName]'
      MachinePath       a machine-specific path ('C:\Users\name\...') in a markdown file
      UserFilesIgnore   '.gitignore' lacks the '[Uu]ser [Ff]iles/' record
      EditorConfig      an '.editorconfig' setting above the first '[section]' (it applies to nothing)
    Rules the build already fails on (no var, block-scoped namespaces, new(), [], CancellationToken last,
    parameter line breaks) are not repeated here. The checks are regular expressions, not a parser: a reported
    line is a candidate to look at, and the script reports rather than fails unless -FailOnViolation is passed.
    Output: '<Rule> <path>:<line> <detail>'. Exit codes: 0, 1 (violations with -FailOnViolation), 2 (invocation).

.PARAMETER Repo
    'DiGi.*' folder name. Defaults to the repository containing the current directory. Unknown exits 2.

.PARAMETER Changed
    Check only the files changed against HEAD (staged, modified and untracked) - the usual pre-commit check.

.PARAMETER FailOnViolation
    Exit 1 when a violation is found.

.PARAMETER Json
    Emit one compressed JSON array of { Rule, Path, Line, Detail }.

.EXAMPLE
    PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineRules.ps1" -Repo "DiGi.Core" -Changed
#>
param (
    [string]$Repo = "",

    [switch]$Changed,

    [switch]$FailOnViolation,

    [switch]$Json
)

$ErrorActionPreference = "Stop"

$baseDir = (Resolve-Path "$PSScriptRoot\..\..").Path

if ($Repo -eq "") {
    $current = (Get-Location).Path
    if ($current.StartsWith($baseDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $current.Substring($baseDir.Length).TrimStart('\')
        if ($relative -ne "") {
            $Repo = $relative.Split('\')[0]
        }
    }
}

$repoDir = Join-Path $baseDir $Repo
if ($Repo -eq "" -or -not (Test-Path (Join-Path $repoDir ".git"))) {
    Write-Host "Pass -Repo <DiGi.* folder name> (or run from inside a repository). Not a repository: '$Repo'" -ForegroundColor Red
    exit 2
}

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if ($Changed) {
    $files = @(git -C $repoDir -c core.quotepath=false -c core.safecrlf=false diff --name-only HEAD) + @(git -C $repoDir -c core.quotepath=false ls-files --others --exclude-standard)
} else {
    $files = @(git -C $repoDir -c core.quotepath=false ls-files)
}
$files = @($files | Where-Object { $_ -and $_ -notmatch '(^|/)(bin|obj)/' -and $_ -notmatch '^documentation/API/' -and $_ -notmatch '^\.agents/' } | Sort-Object -Unique)

$violations = New-Object System.Collections.Generic.List[object]

function Add-Violation {
    param (
        [string]$Rule,
        [string]$Path,
        [int]$Line,
        [string]$Detail
    )

    $violations.Add([pscustomobject]@{ Rule = $Rule; Path = $Path; Line = $Line; Detail = $Detail })
}

$methodPattern = New-Object System.Text.RegularExpressions.Regex('^\s*(?<access>public|private)\s+static\s+(?:async\s+)?(?:\([^=]*?\)\??|[\w.<>\[\],?\s]+?)\s+(?<name>\w+)\s*(?:<[^()=]*>)?\s*\(')
$todoPattern = New-Object System.Text.RegularExpressions.Regex('//.*\bTODO\b(?!:?\s*\[\w+\])')
$machinePathPattern = New-Object System.Text.RegularExpressions.Regex('[A-Za-z]:\\Users\\(?!\.\.\.|<)|(?<![\w.])/(?:home|Users)/(?!\.\.\.|<)[\w.-]+/')

foreach ($file in $files) {
    $fullPath = Join-Path $repoDir ($file -replace '/', '\')
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        continue
    }

    if ($file -like "*.cs") {
        $lines = [System.IO.File]::ReadAllLines($fullPath)
        $folder = [regex]::Match($file, '(^|/)(?<folder>Query|Modify|Create)/')
        $publicNames = New-Object System.Collections.Generic.List[string]
        $firstPublicLine = 0

        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]

            if ($line -match '^\s*using\s+(Xunit|DiGi\.Core\.xUnit)\s*;') {
                Add-Violation -Rule "XunitUsing" -Path $file -Line ($i + 1) -Detail $line.Trim()
            }

            if ($todoPattern.IsMatch($line)) {
                Add-Violation -Rule "TodoMarker" -Path $file -Line ($i + 1) -Detail "TODO without [MarkerName]"
            }

            if (-not $folder.Success) {
                continue
            }

            $method = $methodPattern.Match($line)
            if (-not $method.Success) {
                continue
            }

            $name = $method.Groups['name'].Value
            if ($method.Groups['access'].Value -eq "private") {
                Add-Violation -Rule "PrivateMethod" -Path $file -Line ($i + 1) -Detail "$name - use a public helper or a local function"
                continue
            }

            if (-not $publicNames.Contains($name)) {
                $publicNames.Add($name)
                if ($firstPublicLine -eq 0) {
                    $firstPublicLine = $i + 1
                }
            }

            if ($folder.Groups['folder'].Value -eq "Query" -and $name -cmatch '^Get[A-Z]') {
                Add-Violation -Rule "QueryGetPrefix" -Path $file -Line ($i + 1) -Detail "$name - Query names are property-like (only Is/Has/Try prefixes)"
            }
        }

        if ($publicNames.Count -gt 1) {
            Add-Violation -Rule "OnePublicMethod" -Path $file -Line $firstPublicLine -Detail ("{0} public methods: {1}" -f $publicNames.Count, ($publicNames -join ", "))
        }

        continue
    }

    if ($file -like "*.md") {
        $lines = [System.IO.File]::ReadAllLines($fullPath)
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $machinePath = $machinePathPattern.Match($lines[$i])
            if ($machinePath.Success) {
                Add-Violation -Rule "MachinePath" -Path $file -Line ($i + 1) -Detail $machinePath.Value
            }
        }

        continue
    }

    if ((Split-Path -Leaf $file) -eq ".editorconfig") {
        $lines = [System.IO.File]::ReadAllLines($fullPath)
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i].Trim()
            if ($line.StartsWith("[")) {
                break
            }
            if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith(";") -or $line -match '^root\s*=') {
                continue
            }
            Add-Violation -Rule "EditorConfig" -Path $file -Line ($i + 1) -Detail "$line - above the first [section], applies to nothing"
        }
    }
}

# Repository-level check (always, also with -Changed: a missing record leaks secrets)
$gitignorePath = Join-Path $repoDir ".gitignore"
if (-not (Test-Path $gitignorePath) -or -not ([System.IO.File]::ReadAllText($gitignorePath).Contains("[Uu]ser [Ff]iles/"))) {
    Add-Violation -Rule "UserFilesIgnore" -Path ".gitignore" -Line 0 -Detail "missing the '[Uu]ser [Ff]iles/' record"
}

if ($Json) {
    Write-Output (ConvertTo-Json -InputObject $violations.ToArray() -Depth 3 -Compress)
} else {
    foreach ($violation in $violations) {
        Write-Host ("{0} {1}:{2} {3}" -f $violation.Rule, $violation.Path, $violation.Line, $violation.Detail)
    }

    $color = "Green"
    if ($violations.Count -gt 0) {
        $color = "Yellow"
    }
    Write-Host ("{0}: {1} file(s) checked, {2} violation(s)." -f $Repo, $files.Count, $violations.Count) -ForegroundColor $color
}

if ($FailOnViolation -and $violations.Count -gt 0) {
    exit 1
}

exit 0
