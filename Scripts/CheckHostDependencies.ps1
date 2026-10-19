# Audits the build output of every deployed DiGi host for assembly references that cannot be
# resolved at runtime.
#
# DiGi repositories reference each other with <Reference><HintPath>..\..\X\bin\X.dll</HintPath>
# instead of <ProjectReference>. A raw assembly reference is opaque to NuGet, so a library's
# transitive NuGet dependencies never reach a host that consumes it by HintPath, and the DiGi class
# libraries do not copy their own NuGet dependencies into their bin either. The host builds clean,
# the test suite passes, and the assembly is simply absent at runtime.
#
# The failure is not a crash. FileNotFoundException is thrown per item deep inside a loop, so a run
# completes and reports success while silently producing less than it should. This script is the
# check that catches it before a deployment does.
#
# Requires a prior build - it inspects compiled output, not project files. Run BuildAll.ps1 first
# (or BuildAll.ps1 -CheckDependencies, which calls this script for you).

param(
	[string]$Root = "$PSScriptRoot\..\..",  # DiGi workspace root
	[string]$Unit = "",                     # Optional single deployment unit name filter
	[switch]$FailOnMissing                  # Exit 1 when a genuine gap is found
)

$Root = (Resolve-Path $Root).Path

# Deployment units, as synchronized by Deploy.ps1.
#
# Recurse:
#   DiGi.WebAPI.WindowsService hosts DiGi.GIS.WebAPI, DiGi.GLTF.WebAPI, DiGi.Communication.WebAPI and
#   DiGi.User.WebAPI under bin\extensions\<name>. They are loaded into AssemblyLoadContext.Default
#   with cross-directory AssemblyDependencyResolvers, so the host output and every extension folder
#   form ONE probing set. Audited separately each reports gaps the deployed service does not have.
#
# Ignore:
#   Reviewed exceptions. Every entry needs a reason - an unexplained name here re-hides the exact
#   class of bug this script exists to find.
$DeploymentUnits = @(
	@{
		Name    = "DiGi.WebAPI.WindowsService"
		Path    = "DiGi.WebAPI.WindowsService\bin"
		Recurse = $true
		# DiGi.GIS.IO.Modify.Update takes IEnumerable<OrtoDatasComparison>, so DiGi.GIS.IO.dll hard
		# references DiGi.GIS.Emgu.CV.dll, which references Emgu.CV. The referenced types are plain
		# data classes with no Emgu types in their surface, so the CLR only needs Emgu.CV.dll if an
		# image-processing member is invoked, which no WebAPI host does. Shipping it would drag
		# native binaries into every host. If a host ever calls an orthophoto path, add
		# Emgu.CV + Emgu.CV.runtime.windows there and drop this entry.
		Ignore  = @("Emgu.CV")
	},
	@{
		Name    = "DiGi.GIS.UI"
		Path    = "DiGi.GIS.UI\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		Name    = "DiGi.GIS.WebAPI.UI"
		Path    = "DiGi.GIS.WebAPI.UI\bin"
		Recurse = $false
		Ignore  = @("Emgu.CV")  # As DiGi.WebAPI.WindowsService above.
	},
	@{
		Name    = "DiGi.GIS.PostgreSQL.UI"
		Path    = "DiGi.GIS.PostgreSQL.UI\bin"
		Recurse = $false
		Ignore  = @("Emgu.CV")  # As DiGi.WebAPI.WindowsService above.
	},
	@{
		Name    = "DiGi.GIS.YOLO.UI"
		Path    = "DiGi.GIS.YOLO.UI\bin"
		Recurse = $false
		Ignore  = @("Emgu.CV")
	},
	@{
		# Three console applications deploy here - the model consumer, the training-table assembler and
		# the accuracy evaluator - so the folder is a deployment unit even though the repository is
		# mostly a class library.
		Name    = "DiGi.GIS.ML"
		Path    = "DiGi.GIS.ML\bin"
		Recurse = $false
		Ignore  = @("Emgu.CV")
	},
	@{
		Name    = "DiGi.Maintenance"
		Path    = "DiGi.Maintenance\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		Name    = "DiGi.Translate"
		Path    = "DiGi.Translate\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		Name    = "DiGi.GML"
		Path    = "DiGi.GML\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		# The standalone nutrition and recipe importer of bodyplan - a framework-dependent console application
		# in the pattern of DiGi.GIS.YOLO.UI.ConsoleApp: its own dependency closure, its own *.conf beside the
		# executable, deployed to the database server through the Software folder by bodyplan\Scripts\Deploy.ps1
		# rather than DiGi.Maintenance's own Deploy.ps1 (which does not carry bodyplan). Every tool of bodyplan's Tools group
		# builds into its own bin, so this folder is the importer's alone.
		# bodyplan is a DigiProject-Organization repository, so it lives in the DigiProject folder beside the DiGi
		# workspace rather than inside it (DiGi.Maintenance/documentation/GitHub - Workspace Setup.md).
		Name    = "bodyplan.Importer"
		Path    = "..\DigiProject\bodyplan\Tools\bodyplan.Importer\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		# The internal bodyplan test page (bodyplan.digiproject.uk) - an IIS-hosted ASP.NET Core application in the
		# pattern of DiGi.GIS.WebAPI.UI, deployed to the web server through the Software folder by
		# bodyplan\Scripts\Deploy.ps1. It builds into its own UI\bin, apart from the extension's Extensions\bin.
		Name    = "bodyplan.WebAPI.UI"
		Path    = "..\DigiProject\bodyplan\UI\bin"
		Recurse = $false
		Ignore  = @()
	},
	@{
		# DiGi.WebTracker tray host (WinExe). All three projects output to the repo-root bin\ folder.
		Name    = "DiGi.WebTracker.UI.Application"
		Path    = "DiGi.WebTracker\bin"
		Recurse = $false
		Ignore  = @()
	}
)

# A -Unit naming no deployment unit used to match nothing, audit nothing and report "No missing dependencies"
# with exit code 0 - so a caller naming a unit before its entry existed here got a green check of nothing.
if (-not [string]::IsNullOrWhiteSpace($Unit) -and -not ($DeploymentUnits | Where-Object { $_.Name -eq $Unit }))
{
	Write-Error "Unknown deployment unit '$Unit'. Known units: $(($DeploymentUnits | ForEach-Object { $_.Name }) -join ', ')."
	exit 2
}

# Indexes every assembly of every installed shared framework (Microsoft.NETCore.App,
# Microsoft.AspNetCore.App, Microsoft.WindowsDesktop.App). Those resolve at runtime without being
# copied to the output, so a reference to one of them is never a gap.
function Get-FrameworkAssemblyNames
{
	$names = @{}

	$lines = $null
	try
	{
		$lines = & dotnet --list-runtimes 2>$null
	}
	catch
	{
		$lines = $null
	}

	if ($null -eq $lines -or $lines.Count -eq 0)
	{
		Write-Warning "'dotnet --list-runtimes' produced no output. Framework assemblies cannot be indexed and every framework reference would be reported as missing."
		Write-Warning "Install the .NET SDK or put 'dotnet' on PATH, then run this script again."
		exit 2
	}

	$directories = @()
	foreach ($line in $lines)
	{
		# Format: "<FrameworkName> <Version> [<InstallDirectory>]"
		if ($line -match '^\S+\s+(\S+)\s+\[(.+)\]$')
		{
			$directories += (Join-Path $Matches[2] $Matches[1])
		}
	}

	foreach ($directory in ($directories | Select-Object -Unique))
	{
		if (-not (Test-Path $directory))
		{
			continue
		}

		foreach ($file in (Get-ChildItem -Path $directory -Filter *.dll -File))
		{
			$names[$file.BaseName] = $true
		}
	}

	return $names
}

# Reads the assembly reference table of a managed assembly without loading it. Returns an empty
# array for native images, resource-only files and anything else without metadata.
function Get-AssemblyReferenceNames
{
	param([string]$Path)

	$names = @()

	try
	{
		$fileStream = [System.IO.File]::OpenRead($Path)
		try
		{
			$peReader = [System.Reflection.PortableExecutable.PEReader]::new($fileStream)
			try
			{
				if (-not $peReader.HasMetadata)
				{
					return @()
				}

				$metadataReader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
				foreach ($handle in $metadataReader.AssemblyReferences)
				{
					$assemblyReference = $metadataReader.GetAssemblyReference($handle)
					$names += $metadataReader.GetString($assemblyReference.Name)
				}
			}
			finally
			{
				$peReader.Dispose()
			}
		}
		finally
		{
			$fileStream.Dispose()
		}
	}
	catch
	{
		return @()
	}

	return $names
}

Write-Host "Checking host dependencies under: $Root" -ForegroundColor Cyan
Write-Host "==========================================="

$frameworkAssemblyNames = Get-FrameworkAssemblyNames
Write-Host "Indexed $($frameworkAssemblyNames.Count) shared framework assemblies."

$count_Missing = 0
$count_Ignored = 0

foreach ($deploymentUnit in $DeploymentUnits)
{
	if (-not [string]::IsNullOrWhiteSpace($Unit) -and $deploymentUnit.Name -ne $Unit)
	{
		continue
	}

	$directory = Join-Path $Root $deploymentUnit.Path

	Write-Host ""
	Write-Host "### $($deploymentUnit.Name)" -ForegroundColor White

	if (-not (Test-Path $directory))
	{
		Write-Warning "Output directory not found: '$directory'. Build the solution first."
		continue
	}

	$files = if ($deploymentUnit.Recurse) { Get-ChildItem -Path $directory -Filter *.dll -File -Recurse } else { Get-ChildItem -Path $directory -Filter *.dll -File }

	$presentAssemblyNames = @{}
	foreach ($file in $files)
	{
		$presentAssemblyNames[$file.BaseName] = $true
	}

	# Referencing assembly names per unresolved reference, so the owner of the gap is obvious.
	$referencedByNames = @{}

	foreach ($file in $files)
	{
		# References made BY a framework assembly are noise - System.Data forwards to
		# System.Data.Odbc/OleDb/SqlClient, System forwards to System.IO.Ports, and so on. Those
		# out-of-band packages are legitimately absent unless something actually uses them.
		if ($frameworkAssemblyNames.ContainsKey($file.BaseName))
		{
			continue
		}

		foreach ($name in (Get-AssemblyReferenceNames $file.FullName))
		{
			if ($presentAssemblyNames.ContainsKey($name) -or $frameworkAssemblyNames.ContainsKey($name))
			{
				continue
			}

			if (-not $referencedByNames.ContainsKey($name))
			{
				$referencedByNames[$name] = @()
			}

			$referencedByNames[$name] += $file.BaseName
		}
	}

	Write-Host "Scanned $($files.Count) assemblies in '$directory'."

	if ($referencedByNames.Count -eq 0)
	{
		Write-Host "All assembly references resolve." -ForegroundColor Green
		continue
	}

	$found = $false
	foreach ($name in ($referencedByNames.Keys | Sort-Object))
	{
		$referencedBy = ($referencedByNames[$name] | Select-Object -Unique | Sort-Object) -join ", "

		if ($deploymentUnit.Ignore -contains $name)
		{
			$count_Ignored = $count_Ignored + 1
			Write-Host "  IGNORED $name (referenced by $referencedBy)" -ForegroundColor DarkGray
			continue
		}

		$found = $true
		$count_Missing = $count_Missing + 1
		Write-Host "  MISSING $name (referenced by $referencedBy)" -ForegroundColor Red
	}

	if (-not $found)
	{
		Write-Host "All assembly references resolve or are reviewed exceptions." -ForegroundColor Green
	}
}

Write-Host ""
Write-Host "==========================================="

if ($count_Missing -eq 0)
{
	Write-Host "No missing dependencies ($count_Ignored reviewed exception(s))." -ForegroundColor Green
	exit 0
}

Write-Host "$count_Missing missing dependency reference(s) found ($count_Ignored reviewed exception(s))." -ForegroundColor Red
Write-Host "Add the owning NuGet package as a <PackageReference> on the host project, matching the version"
Write-Host "declared by the DiGi library that needs it. Do not set CopyLocalLockFileAssemblies on the library."

if ($FailOnMissing)
{
	exit 1
}

exit 0
