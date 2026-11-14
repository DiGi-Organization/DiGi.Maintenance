# AI Guidelines: Project Setup — Templates, New Repositories, `.editorconfig`, Build Props, Analyzers

## Checklist
Read this first; open a section only when its line applies to the change.
- Scaffold from `templates/` directly under the workspace root (relative `HintPath`s break one level deeper) (§1).
- New repository: replace `.gitignore` from the template before the first commit and prove `git check-ignore -v "user files/x"`; then the eight setup steps in order (§2).
- Build settings live only in `Directory.Build.props` (`LangVersion latest`, `TreatWarningsAsErrors`, `AnalysisLevel latest-recommended`); core libraries `netstandard2.0`; `System.Threading.Lock` only in net9+ (§3).
- An analyzer finding gets its behavior-preserving fix — never a silent culture switch, never `CA1822` on a public member, never a rename of a public or wire type; suppress at the site with a reason (§3 lists the fix per rule).
- `.editorconfig` is copied from the template; nothing but `root = true` above the first `[section]`; overrides under `[*.cs]`, a repository-only override in its own section below (§4). Check: `DiGi.Maintenance/Scripts/CheckGuidelineRules.ps1 -Repo <Repo>`.
- A Roslyn analyzer is two `netstandard2.0` projects and never references `Microsoft.CodeAnalysis.Workspaces` (§5).

## 1. Templates (`templates/` at the workspace root)
If a template is missing locally, restore it into `templates/` before scaffolding.
- **`DiGi.Template`** — repository boilerplate: `Directory.Build.props`, `Directory.Build.targets` (`DefaultDocumentation`
  generation, `CopyFiles`/`CopyUserFiles` targets), `.editorconfig`, `DefaultDocumentation.json`, `.gitignore`
  (`[Uu]ser [Ff]iles/`).
- **`DiGi.WebAPI.GLTF.Template`** (short name `digiwebapigltftemplate`) — ASP.NET Core Web API on `DiGi.GLTF`
  (`Coding - WebAPI GLTF.md`).
```powershell
dotnet new install "templates/DiGi.WebAPI.GLTF.Template"
dotnet new digiwebapigltftemplate -n MyGLTFHost -o "MyGLTFHost"
dotnet new uninstall "templates/DiGi.WebAPI.GLTF.Template"
```
**Scaffold directly under the workspace root** (`<root>\<Solution>\<Project>\`): the relative `HintPath`s
(`..\..\DiGi.Core\bin\DiGi.Core.dll`) break one level deeper.

## 2. Standing up a new repository
**The leak first: a repository created in the GitHub UI does not ignore `user files/`** — the stock
`VisualStudio.gitignore` has no `[Uu]ser [Ff]iles/` rule, so the first `git add -A` commits connection strings and keys.
Replace `.gitignore` from the template before the first commit and prove it: `git check-ignore -v "user files/x"`.
Then, in order (`DiGi.GIS.YOLO.UI`, `DiGi.YOLO.ONNX` are recent examples):
1. Root files from `templates/DiGi.Template/`: `.editorconfig`, `.gitignore`, `Directory.Build.props`
   (`<Major>`/`<Minor>`/`<Build>` = the version branch, step 7).
2. `Directory.Build.targets`, `DefaultDocumentation.json`, `.github/workflows/sync-wiki.yml` copied from a sibling —
   `ApplyDocumentationSetup.ps1` writes them into **every** repository.
3. `.agents/` (`UpdateAgents.ps1`) and the README guidelines block (`UpdateReadmes.ps1`) — write the README intro first
   (the block is appended below it). Both sweep and commit every repository (`Maintenance - Scripts.md` §3).
4. Labels: `SyncLabelsAllRepos.ps1 -Repo <name>` — without them the first issue cannot carry the mandatory labels.
5. `BuildAll.ps1`: add the `.slnx` to `$solutionOrder` **after everything it references by `HintPath`**.
6. `CheckHostDependencies.ps1`: a `$DeploymentUnits` entry only for an `Exe`/`WinExe`/web host.
7. Version branch: bare SemVer off `main`, `git push -u origin <version>` (`GitHub - Branches and Commits.md` §4).
8. `gh repo edit <owner>/<name> --description "..."` (empty by default).

## 3. `Directory.Build.props`, language version, version stamp
- **Every repository's props carry the template's settings** (DiGi.Maintenance#19): `LangVersion latest`, `Nullable`,
  `ImplicitUsings`, `TreatWarningsAsErrors`, `AnalysisLevel latest-recommended`, `EnforceCodeStyleInBuild`, XML
  documentation for non-test projects. A `.csproj` sets none of them (no per-project `<LangVersion>`). Core libraries
  (`DiGi.Core`, `DiGi.Geometry`, …) target `netstandard2.0`; hosts `net10.0(-windows)` — the language is latest, the
  runtime API is the target's.
- **Zero warnings means the analyzers too.** Recurring findings and the behavior-preserving fix:
  - `CA1305`/`CA1304`/`CA1311`: pass the culture the call already used (`CultureInfo.CurrentCulture`; Roslyn's
    `Diagnostic.GetMessage` defaults to `CurrentUICulture`). `InvariantCulture` only where the value is an identity, a
    key or wire text (`Coding - General.md` §1) — never as a silent switch.
  - `CA1310`: `StringComparison.CurrentCulture`, or `Ordinal` when the comparison is an identity (`CA1309`); a
    user-facing sort keeps its culture order with a `#pragma` and reason.
  - `CA2200` (`throw exception;`): drop the catch or `throw;`. `CA1036`: add `<`/`<=`/`>`/`>=` that follow `CompareTo`,
    null first.
  - `CS0104` after `ImplicitUsings` (`Timer`, …): `using Timer = <the namespace the file meant>.Timer;`. A WPF project
    with `UseWindowsForms` gets `System.Windows.Forms` implicitly (`MessageBox`, `OpenFileDialog`, `Application`,
    `Label` turn ambiguous): `<Using Remove="System.Windows.Forms" />` in its `.csproj`.
  - `CA1805` on a `readonly` field assigned nowhere else: removing `= null` raises `CS0649` — keep the initializer and
    suppress.
  - `CA1200`: `<see cref="Classes.X"/>`, not `T:`; ``X`1`` becomes `X{T}`. The compiler never checked a prefixed cref,
    so dropping `T:` can surface a wrong target as `CS1574` — point it at the real namespace (inside `Create`, a bare
    `X` binds to the `X` factory method).
  - `CA1822`: the code fix (`dotnet format analyzers`) also makes a **public** instance member `static` — every
    `instance.Method(...)` caller breaks, and reflection with `BindingFlags.Instance` misses it silently. Accept it
    only for non-public members; suppress on a public one.
  - `CA2016`: forward the token (`cancellationToken: cancellationToken` after a skipped default) — a deliberate
    behavior change (a requested cancel now stops that step too), so the commit says so. A write that must finish once
    started (a controller's `UpdateAsync` when the client disconnects) passes `CancellationToken.None` explicitly
    instead. `CA1068`: token last.
  - `CA1848`/`CA1873` (`LoggerMessage` delegates): a host logging through `ILogger` with inline structured templates
    turns them off in its own `.editorconfig` (`DiGi.GIS.WebAPI.UI`); `CA2254` is fixed — the template stays constant.
  - A design rule on a public or serialized name (`CA1710`, `CA1010`, `CA1000`, `CA1859` on a serialized field,
    `CA5350`/`CA5351` on a non-security hash, `CA2201`, `CA1069`): `[SuppressMessage(..., Justification = "...")]` or a
    `#pragma` with its reason at the site — renaming a public or wire type is a breaking change, not a fix.
- A non-SDK (.NET Framework, `TargetFrameworkVersion`) project still gets `Nullable` from the props, but the SDK
  analyzers do not run on it (`DiGi.Translate.Framework`).
- `System.Threading.Lock` (`private readonly Lock lockObject = new();`) only in net9+ projects; a `netstandard2.0`
  library locks an `object`.
- Version: `<Major>`/`<Minor>`/`<Build>` match the version branch; `Revision` is a UTC `yyyyMMddHHmmss` stamp; the SDK
  appends `+<HEAD hash>` to `InformationalVersion` — with no dirty marker, so a build from uncommitted changes carries
  HEAD's hash.
- **Solution Items** (`.sln`/`.slnx`): `Directory.Build.props`, `Directory.Build.targets`, `.editorconfig`,
  `DefaultDocumentation.json` (if present) sit in the `Solution Items` virtual folder.

## 4. `.editorconfig`
**The baseline is `templates/DiGi.Template/.editorconfig` — copy it, do not hand-assemble one.**
> [!IMPORTANT]
> **A property above the first `[section]` header applies to no file.** Only `root = true` belongs there; every
> `dotnet_diagnostic.*` override sits under `[*.cs]`. In the preamble it is silently ignored and the analyzer default
> returns — with `AnalysisLevel latest-recommended` + `TreatWarningsAsErrors`, a parameter `fileNames_KeepExisting`
> fails the build with `CA1707`. The template shipped that layout until 2026-10-15 and eight repositories inherited it
> (`DiGi-Organization/DiGi.Python#1`). Audit:
> ```bash
> for f in */.editorconfig; do awk '/^\[/{exit} /^[a-z_]+\.[^=]*=/{print FILENAME": "$0}' "$f"; done
> ```

How the house rules (`Coding - General.md` §1) map to settings:

| Rule | Setting |
|---|---|
| No `var` | `csharp_style_var_for_built_in_types` / `_when_type_is_apparent` / `_elsewhere = false:warning` |
| Block-scoped namespaces | `csharp_style_namespace_declarations = block_scoped:warning` |
| Collection expressions `[]` (IDE0028) | `csharp_style_prefer_collection_expression = true:warning` |
| Target-typed `new()` (IDE0090) | `csharp_style_implicit_object_creation_when_type_is_apparent = true:warning` |
| Block bodies for methods, constructors, operators, local functions; `=>` for properties, indexers, accessors, lambdas | `csharp_style_expression_bodied_* = false/true:silent` |
| Line endings | `[*] end_of_line = crlf`, `charset = utf-8`, `indent_size = 4` |
| Parameter line breaks (≤ 7 one line) | analyzer `DIGI0001` (§5), not an `.editorconfig` setting |

Diagnostic overrides under `[*.cs]` (`= none`), each with its reason: `IDE0130` (logical namespaces; folders do not add
segments, `Coding - General.md` §2), `CA1707` (underscores in `To[Area]_[Type]` and `_`-suffixed names), `CS1591`,
`IDE0290` (no primary constructors), `IDE1006`, `CA1016`, `CA1711`; and the analyzer rules that contradict the
conventions: `CA1720` (variables named after their type, `object @object`), `CA1725` (overrides keep that naming),
`CA1715` (established generic names `UValue`, `K`), `CA1051`/`CA1708` (base classes expose protected fields beside
same-named properties), `CA1716` (`Query`, `Modify`, `Create`, `Convert`, `Inspect`). Add a rule here only when it
contradicts a convention everywhere; otherwise fix the code or suppress at the site (§3). The template has the block
**once**, under `[*.cs]`; `[*.{cs,vb}]` holds the naming rules. A repository-only override goes in a section of its own
appended below the template's text, with its reason (`DiGi.GIS.ML`: generated ML.NET files; `DiGi.GIS.WebAPI.UI`:
`ILogger` rules), so a re-copy of the template shows it in the diff.

## 5. Roslyn analyzers & code fixes
`DIGI0001` lives in `DiGi.Maintenance/DiGi.Maintenance.Analyzers/ParameterListLineBreakAnalyzer.cs` (fact project
`DiGi.Maintenance.Analyzers.xUnit`).
1. **Two projects, both `netstandard2.0`:** `[Namespace].Analyzers` references only `Microsoft.CodeAnalysis.CSharp` +
   `Microsoft.CodeAnalysis.Analyzers` (the `DiagnosticAnalyzer`s); `[Namespace].Analyzers.CodeFixes` references the
   analyzers project + `Microsoft.CodeAnalysis.CSharp.Workspaces` (the `CodeFixProvider`s).
2. **An analyzer project never references `Microsoft.CodeAnalysis.Workspaces`** or IDE packages (`RS1038`): command-line
   compilers do not provide them, and the analyzer can fail to load.
