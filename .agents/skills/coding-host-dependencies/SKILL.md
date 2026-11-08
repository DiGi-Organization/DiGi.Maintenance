---
name: coding-host-dependencies
description: "Use when adding a NuGet package, when a deployed host throws FileNotFoundException or delivers a partial result, or on a CS0012/CS0246 build wall - HintPath references drop transitive packages (re-declare them on the host at the same version), checking the already-referenced package and its runtime variant first, extension hosts as one probing set, a stale deps.json after a library reference change, CheckHostDependencies.ps1, rebuilding every consumer after a public-surface change."
---

# AI Guidelines: Host Dependencies — `HintPath` Opacity

DiGi projects reference each other with `<Reference><HintPath>..\..\X\bin\X.dll</HintPath>`, never `<ProjectReference>`.
A raw assembly reference is **opaque to NuGet and to MSBuild's build graph**, and DiGi libraries do not copy their own
packages into `bin`. Everything below follows from that. (Formerly `Coding - General.md` §4.) Build-order consequence for
tests — `dotnet test` never rebuilds the library under test: `Coding - Automatic Tests.md` §4.

## 1. Before adding a package — check what is already referenced
Every new package must be re-declared on every deployed host (§2), so enumerate the existing ones first.
- **Read the package's XML docs** beside the DLL: `%USERPROFILE%\.nuget\packages\<id>/<version>/lib/<tfm>/<Id>.xml`,
  grepped by namespace — faster and more complete than a web search. `Assembly.GetExportedTypes()` gives the bare list.
- **Check the consuming project's TFM folder**: `DiGi.Geometry` is `netstandard2.0`; a type in the `netstandard2.1`
  folder is not automatically in `netstandard2.0`.
- Worked example: [DiGi.Geometry#2](https://github.com/DiGi-Organization/DiGi.Geometry/issues/2) proposed `Clipper2` +
  `Cutear` or ~200 hand-written lines; the already-referenced `NetTopologySuite` 2.6.0 ships
  `PolygonTriangulator`/`PolygonHoleJoiner` in both TFMs (which triangulator to use: `Coding - Geometry.md` §4).
- **Presence of a package is not availability of the capability — check the runtime/native variant at the version in
  use.** `Emgu.CV` 4.12.0.5764 exposes ONNX DNN (`DnnInvoke.ReadNetFromONNX`), but `Emgu.CV.runtime.windows.cuda` stops
  at `4.4.0.4099` on nuget.org, so it is CPU-only (minutes vs days for a 258-GFLOP net); `DiGi.YOLO.ONNX` uses
  `Microsoft.ML.OnnxRuntime.Managed` and keeps Emgu for imaging.

## 2. The rule
- When a `HintPath`-referenced library needs a NuGet package, **re-declare that `PackageReference` on the deployed host**
  (`Exe`/`WinExe`/`Microsoft.NET.Sdk.Web`) at the **exact same version**, with a comment naming the owning library.
- **Unless the target framework provides it** (`System.Drawing.Common` on `net10.0-windows`, the Windows Desktop and
  ASP.NET shared frameworks): re-declaring earns `NU1510`. Build first and let `CheckHostDependencies.ps1` (§8) name what
  is actually absent.
- Audit the whole closure: `DiGi.Geometry` → `DiGi.Math` → `MathNet.Numerics`.
- **Never** `CopyLocalLockFileAssemblies=true` on a netstandard2.0 library (bloats `bin` with `System.*` 4.3.0 shims).
- `<ProjectReference>` consumers (siblings, `.xUnit`, `.Rhino`) are unaffected.
- **A `HintPath` does not carry the assembly reference onward either — that half fails loudly.** A project consuming A by
  `ProjectReference`, where A reaches B by `HintPath`, gets `CS0234`/`CS0246` on B's namespaces and must re-declare B
  (`DiGi.YOLO.ONNX.xUnit` declares `DiGi.YOLO` itself).

## 3. The failure signature — read before suspecting the data
**A missing transitive dependency produces a partial result, not an error**: `FileNotFoundException` is thrown per item
inside a loop and the run reports success. County 5 modelled **65 % of 33 687 buildings** and reported success.
> When a run completes but delivers less than it should, check the host's output for missing assemblies **first**.

A green build and green tests prove nothing: `DiGi.Test/DiGi.GIS.Analytical.xUnit` re-declares `QuikGraph`, so the suite
passed while the shipped host could not split storeys.

## 4. Extension hosts are one probing set
`DiGi.GIS.WebAPI`, `DiGi.GLTF.WebAPI`, `DiGi.Communication.WebAPI`, `DiGi.User.WebAPI` deploy into
`DiGi.WebAPI.WindowsService\bin\extensions\<name>` and load into `AssemblyLoadContext.Default` with cross-directory
`AssemblyDependencyResolver`s. Audit host + `extensions\*` together; declare shared dependencies once on
`DiGi.WebAPI.WindowsService` (as `Microsoft.OpenApi` and `Serilog` are).
`DiGi.GIS.PostgreSQL.UI`'s `bin\extensions\<tool>\` is different: standalone executables started with `Process.Start`,
each its own deployment unit, never loaded — nothing resolves assemblies from it (`Coding - YOLO.md` §5).

## 5. A reference added to a library does not reach the host's `deps.json`
Same `FileNotFoundException`, different cause — the dll **is** in `bin`:
```
Could not load file or assembly 'DiGi.User.PostgreSQL, Version=0.1.0.0, ...'. The system cannot find the file specified.
```
A `SelfContained` host resolves through `*.deps.json`; a file missing from it is not on the TPA list. A new
`<Reference><HintPath>` added to a **library** (`DiGi.GIS.PostgreSQL.UI`) reaches the executable's output
(`DiGi.GIS.PostgreSQL.UI.Application`), but MSBuild judges the executable's `deps.json` up to date because none of **its**
inputs changed. Tell: `deps.json` older than the `.exe` (four days, once). Second instance: `DiGi.PRG`/`DiGi.PRG.Geometry`,
same host.
- **Rebuild the executable with `--no-incremental`** (or clear its `obj`) after changing any consumed library's assembly
  references; re-declaring the references on the host also works.
- Confirm membership, not presence: `grep -oE '"DiGi\.[A-Za-z.]+/[^"]*"' bin/<App>.deps.json`.
- `SyncDirectory.ps1` carries a fresh `.exe` beside a stale manifest — re-sync after the full rebuild and check the
  destination's `deps.json` timestamp.
- Only launching the host proves it (an `.xUnit` project has its own correct manifest; §8 does not check it).

## 6. Build-time symptoms of the same opacity
| Symptom | Cause → fix |
|---|---|
| `CS0012` "type defined in an assembly that is not referenced" on an overloaded call | The compiler loads parameter types of **every** same-named candidate. Fix the `.csproj` (add the named assembly), never the call site. Known: `GIS.Query.Reference()` (`DiGi.BDOT10k`, `DiGi.GML`), `Convert.ToDiGi` (`DiGi.BDOT10k`), `Analytical.Create.BuildingModel` (`DiGi.Geometry`), `Geometry.Planar.Query.Union` (`NetTopologySuite` `PackageReference`). Find the candidate: `grep -rhnE "public static .* <Method>\(this "`. Latent — confirm with `git stash` + rebuild before blaming your change. |
| A wall of `CS0246`/`CS0234` that vanishes under `-m:1` | Parallel-build race: a host reaching a library by both `ProjectReference` and `HintPath` (most `*.UI`/`*.Application`) compiles while the dll is rewritten (47 errors in `DiGi.GIS.UI.Application`). Rebuild `-m:1` or build the dependency first. |
| Dozens of `CS1574` after adding a reference | A `HintPath` also probes its folder; a `bin` built with `CopyLocalLockFileAssemblies=true` holds a stale closure (`DiGi.GIS.IO/bin`: 26 dlls, a 7-hour-old `DiGi.GIS.dll`). Count first: `ls <lib>/bin/*.dll \| wc -l` (1–2 = library, 20 = closure); take what you need inline instead. |
| Solution `--no-incremental` fails compiling against `DiGi.Core` | It cleaned `DiGi.Core\bin` (reached via `DiGi.Core.xUnit`'s `ProjectReference`) before compiling the `HintPath` consumer (`DiGi.Python.slnx`, DiGi.Maintenance#14). Rebuild incrementally or `DiGi.Core` first. |

## 7. Rebuild every consumer after changing a public surface
MSBuild will not tell you a downstream repository broke. After a signature change, a moved/renamed/removed type or member,
or a new dependency, rebuild the repositories that reference the library (`DiGi.Test`, the UIs, `DiGi.GIS.ML`, …;
`BuildAll.ps1`, `Maintenance - Scripts.md` §4) before pushing — ~8 breaks since 2026-08 were found by the next builder
(DiGi.Test `6e5a414`: 34 broken doc cross-references after an added parameter).

## 8. The check
Run after building; it inspects compiled output with `System.Reflection.Metadata.PEReader`:
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CheckHostDependencies.ps1"
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Configuration Release -CheckDependencies
```
It reports every reference resolving neither inside the deployment unit nor in a shared framework. Reviewed exceptions are
declared per unit inside the script, each with its reason — an unexplained entry re-hides the bug class. It does **not**
check `deps.json` membership (§5): it once reported "No missing dependencies" for a host that could not start.
