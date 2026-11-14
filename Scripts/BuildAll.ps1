param(
	[string]$Root = "$PSScriptRoot\..\..",  # Default to one level above script folder
	[string]$Configuration = "Release",
	[string]$VsMsbuildPath = "",
	[switch]$CheckDependencies,             # Run CheckHostDependencies.ps1 after the last solution builds
	[switch]$Summary,                       # Print only failed solutions and de-duplicated diagnostics, not the MSBuild log
	[string]$Solution = ""                  # Build only this solution folder (e.g. "DiGi.Core"); unknown exits 2
)

# Resolve the Root path to full absolute path
$Root = Resolve-Path $Root

Write-Host "Using root path: $Root"

# --- MSBuild detection (same as before) ---
if ([string]::IsNullOrWhiteSpace($VsMsbuildPath)) {
	$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
	if (-Not (Test-Path $vswhere)) {
		Write-Host "vswhere.exe not found at $vswhere. Please provide -VsMsbuildPath manually."
		exit 1
	}

	$vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
	if ([string]::IsNullOrWhiteSpace($vsPath)) {
		Write-Host "Could not find a Visual Studio installation with MSBuild."
		exit 1
	}

	$VsMsbuildPath = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
}

if (-Not (Test-Path $VsMsbuildPath)) {
	Write-Host "MSBuild not found at $VsMsbuildPath"
	exit 1
}

Write-Host "Using MSBuild at: $VsMsbuildPath"

# --- Define solution order ---
$solutionOrder = @(
	"DiGi.Core\DiGi.Core.slnx",
	# DiGi.Python depends on DiGi.Core only; DiGi.Laya reaches it by HintPath, and DiGi.YOLO will
	# (DiGi.YOLO#23), so both stay ahead of DiGi.YOLO.
	"DiGi.Python\DiGi.Python.slnx",
	"DiGi.Laya\DiGi.Laya.slnx",
	"DiGi.Unit\DiGi.Unit.slnx",
	"DiGi.Math\DiGi.Math.slnx",
	"DiGi.User\DiGi.User.slnx",
	"DiGi.BDL\DiGi.BDL.slnx",
	"DiGi.Weather\DiGi.Weather.slnx",
	"DiGi.EPW\DiGi.EPW.slnx",
	"DiGi.GML\DiGi.GML.slnx",
	"DiGi.OSM\DiGi.OSM.slnx",
	"DiGi.YOLO\DiGi.YOLO.slnx",
	"DiGi.YOLO.ONNX\DiGi.YOLO.ONNX.slnx",
	"DiGi.VoTT\DiGi.VoTT.slnx",
	"DiGi.GitHub\DiGi.GitHub.slnx",
	"DiGi.PostgreSQL\DiGi.PostgreSQL.slnx",
	"DiGi.User.PostgreSQL\DiGi.User.PostgreSQL.slnx",
	"DiGi.Geometry\DiGi.Geometry.slnx",
	"DiGi.Geometry.Random\DiGi.Geometry.Random.slnx",
	"DiGi.Geometry.Visual\DiGi.Geometry.Visual.slnx",
	"DiGi.Geometry.PointCloud\DiGi.Geometry.PointCloud.slnx",
	"DiGi.GLTF\DiGi.GLTF.slnx",
	"DiGi.Serilog\DiGi.Serilog.slnx",
	"DiGi.WebAPI\DiGi.WebAPI.slnx",
	"DiGi.GLTF.WebAPI\DiGi.GLTF.WebAPI.slnx",
	"DiGi.User.WebAPI\DiGi.User.WebAPI.slnx",
	"DiGi.Typology\DiGi.Typology.slnx",
	"DiGi.Log\DiGi.Log.slnx",
	"DiGi.SQLite\DiGi.SQLite.slnx",
	"DiGi.Rhino\DiGi.Rhino.slnx",
	"DiGi.Scripting\DiGi.Scripting.slnx",
	"DiGi.Scripting.Rhino\DiGi.Scripting.Rhino.slnx",
	"DiGi.Translate\DiGi.Translate.slnx",
	"DiGi.AssemblyResolver\DiGi.AssemblyResolver.slnx",
	"DiGi.UI.WPF\DiGi.UI.WPF.slnx",
	"DiGi.UI.Windows\DiGi.UI.Windows.slnx",
	"DiGi.Emgu.CV\DiGi.Emgu.CV.slnx",
	"DiGi.ComputeSharp\DiGi.ComputeSharp.slnx",
	"DiGi.ComputeSharp.Rhino\DiGi.ComputeSharp.Rhino.slnx",
	"DiGi.Solar\DiGi.Solar.slnx",
	"DiGi.Solar.Rhino\DiGi.Solar.Rhino.slnx",
	"DiGi.CityGML\DiGi.CityGML.slnx",
	"DiGi.BDOT10k\DiGi.BDOT10k.slnx",
	"DiGi.PRG\DiGi.PRG.slnx",
	"DiGi.Analytical\DiGi.Analytical.slnx",
	"DiGi.Analytical.Rhino\DiGi.Analytical.Rhino.slnx",
	"DiGi.GLTF.Analytical\DiGi.GLTF.Analytical.slnx",
	"DiGi.GIS\DiGi.GIS.slnx",
	"DiGi.GIS.Emgu.CV\DiGi.GIS.Emgu.CV.slnx",
	"DiGi.GIS.IO\DiGi.GIS.IO.slnx",
	"DiGi.GIS.Analytical\DiGi.GIS.Analytical.slnx",
	"DiGi.GIS.PostgreSQL\DiGi.GIS.PostgreSQL.slnx",
	"DiGi.GIS.SQLite\DiGi.GIS.SQLite.slnx",
	"DiGi.GIS.WebAPI\DiGi.GIS.WebAPI.slnx",
	"DiGi.GIS.ML\DiGi.GIS.ML.slnx",
	"DiGi.GIS.YOLO\DiGi.GIS.YOLO.slnx",
	# DiGi.GIS.PostgreSQL.UI reaches DiGi.GIS.YOLO.UI by HintPath - for its Year Built prediction options class,
	# its exit codes and its progress reader - so the extension must be built before the UI hosts that reference
	# it. It cannot be a ProjectReference: DiGi.GIS.PostgreSQL.UI publishes self-contained and single-file and
	# must not pull in the DiGi.GIS.ML closure. See DiGi.GIS.PostgreSQL.UI\DiGi.GIS.PostgreSQL.UI.csproj.
	"DiGi.GIS.YOLO.UI\DiGi.GIS.YOLO.UI.slnx",
	"DiGi.GIS.Rhino\DiGi.GIS.Rhino.slnx",
	"DiGi.Communication\DiGi.Communication.slnx",
	"DiGi.Communication.Rhino\DiGi.Communication.Rhino.slnx",
	"DiGi.Communication.WebAPI\DiGi.Communication.WebAPI.slnx",
	"DiGi.SAM\DiGi.SAM.slnx",
	"DiGi.Tas\DiGi.Tas.slnx",
	"DiGi.GIS.UI\DiGi.GIS.UI.slnx",
	"DiGi.GIS.PostgreSQL.UI\DiGi.GIS.PostgreSQL.UI.slnx",
	"DiGi.GIS.WebAPI.UI\DiGi.GIS.WebAPI.UI.slnx",
	"DiGi.Maintenance\DiGi.Maintenance.slnx",
	"DiGi.WebAPI.WindowsService\DiGi.WebAPI.WindowsService.slnx",
	"DiGi.WebTracker\DiGi.WebTracker.sln"
	# add more in the order you need
)

$platform_x64 = @(
	"DiGi.Tas\DiGi.Tas.slnx"
)

if ($Solution -ne "")
{
	$solutionOrder = @($solutionOrder | Where-Object { $_.Split('\')[0] -eq $Solution })

	if ($solutionOrder.Count -eq 0)
	{
		Write-Host "Unknown solution '$Solution' - it is not in the build order of this script." -ForegroundColor Red
		exit 2
	}
}

# 'file(line,col): error CS0000: message [project]' -> 'error CS0000 file:line message', de-duplicated
function Get-Diagnostics
{
	param(
		[object[]]$Lines
	)

	$seen = @{}
	$result = @()
	foreach ($line in $Lines)
	{
		$text = [string]$line
		$diagnostic = ""
		$located = [regex]::Match($text, '^\s*(?:\d+>)?(?<file>[^(]+?)\((?<line>\d+)(?:,\d+)*\)\s*:\s*(?<severity>error|warning)\s+(?<code>\w+)\s*:\s*(?<message>.*?)(?:\s*\[[^\]]+\])?\s*$')
		if ($located.Success)
		{
			$file = $located.Groups['file'].Value.Trim()
			if ($file.StartsWith([string]$Root, [System.StringComparison]::OrdinalIgnoreCase))
			{
				$file = $file.Substring(([string]$Root).Length).TrimStart('\')
			}
			$diagnostic = "{0} {1} {2}:{3} {4}" -f $located.Groups['severity'].Value, $located.Groups['code'].Value, $file, $located.Groups['line'].Value, $located.Groups['message'].Value
		}
		else
		{
			$general = [regex]::Match($text, '^\s*(?:\d+>)?[^:]*?\s*:\s*(?<severity>error|warning)\s+(?<code>\w+)\s*:\s*(?<message>.*?)(?:\s*\[[^\]]+\])?\s*$')
			if (-not $general.Success)
			{
				continue
			}
			$diagnostic = "{0} {1} {2}" -f $general.Groups['severity'].Value, $general.Groups['code'].Value, $general.Groups['message'].Value
		}

		if (-not $seen.ContainsKey($diagnostic))
		{
			$seen[$diagnostic] = $true
			$result += $diagnostic
		}
	}

	return $result
}

$count = 0

$length = $solutionOrder.Count

foreach ($relativePath in $solutionOrder) 
{
	$sln = Join-Path $Root $relativePath

	if (-Not (Test-Path $sln)) 
	{
		Write-Host "Solution not found (skipping): $sln" -ForegroundColor Yellow
		continue
	}

	if (-Not $Summary)
	{
		Write-Host "Building solution: $sln"
	}

	# Determine platform parameter
	if ($platform_x64 -contains $relativePath) 
	{
		$platformParam = "/p:Platform=x64"
	} 
	else 
	{
		$platformParam = ""
	}

	# Build the solution
	#& $VsMsbuildPath $sln /p:Configuration=$Configuration $platformParam /m:1 /p:VisualStudioVersion=17.0 /verbosity:minimal
	
	# Build the solution with an explicit restore step
	if ($Summary)
	{
		# Capture the log; print only what needs attention
		$buildOutput = & $VsMsbuildPath $sln -restore /p:Configuration=$Configuration $platformParam /m:1 /p:VisualStudioVersion=17.0 /verbosity:minimal
		$buildExitCode = $LASTEXITCODE
		$diagnostics = @(Get-Diagnostics -Lines $buildOutput)

		if ($buildExitCode -ne 0)
		{
			Write-Host "FAIL $relativePath" -ForegroundColor Red
			$diagnostics | Where-Object { $_.StartsWith("error") } | ForEach-Object { Write-Host "  $_" }
			exit $buildExitCode
		}

		if ($diagnostics.Count -gt 0)
		{
			Write-Host "WARN $relativePath" -ForegroundColor Yellow
			$diagnostics | ForEach-Object { Write-Host "  $_" }
		}

		$count = $count + 1
		continue
	}

	& $VsMsbuildPath $sln -restore /p:Configuration=$Configuration $platformParam /m:1 /p:VisualStudioVersion=17.0 /verbosity:minimal

	if ($LASTEXITCODE -ne 0) 
	{
		Write-Host "Build failed for $sln" -ForegroundColor Red
		exit $LASTEXITCODE
	}
	
	$count = $count + 1
	
	Write-Host "Building succeeded ($count/$length)`n"-ForegroundColor Green
}

if ($count -eq $length)
{
	Write-Host "$count solutions from $length built successfully.`n" -ForegroundColor Green
}
else
{
	Write-Host "$count solutions from $length built successfully.`n" -ForegroundColor Yellow
}

if ($CheckDependencies)
{
	# HintPath references drop a library's transitive NuGet dependencies, so a host can build clean
	# and still be missing an assembly at runtime. Verify the output before it is deployed.
	$checkScript = Join-Path -Path $PSScriptRoot -ChildPath "CheckHostDependencies.ps1"

	if (-Not (Test-Path $checkScript))
	{
		Write-Host "'$checkScript' not found. Dependency check skipped." -ForegroundColor Yellow
	}
	else
	{
		& $checkScript -Root $Root -FailOnMissing

		if ($LASTEXITCODE -ne 0)
		{
			exit $LASTEXITCODE
		}
	}
}
