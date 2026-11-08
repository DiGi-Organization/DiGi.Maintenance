---
name: coding-project-setup
description: "Use when creating a project or repository from templates/ or changing build configuration - the GitHub-created .gitignore that leaks user files, the new-repository checklist (labels, BuildAll order, version branch), Directory.Build.props and the real LangVersion of the repos, .editorconfig from the template (overrides only under [*.cs], never above the first section), Solution Items, Roslyn analyzer project split (DIGI0001)."
---

# AI Guidelines: Project Setup — Templates, New Repositories, `.editorconfig`, Build Props, Analyzers

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
- The **template** sets `LangVersion` 12.0, `Nullable` enable, `TreatWarningsAsErrors`, `AnalysisLevel latest-recommended`
  and XML documentation for non-test projects. **Existing repositories mostly do not** (11 of 72 props carry it): they set
  `<LangVersion>latest</LangVersion>` per `.csproj`. Core libraries (`DiGi.Core`, `DiGi.Geometry`, …) target
  `netstandard2.0`; hosts target `net10.0(-windows)`. Write code that compiles at C# 12 on `netstandard2.0` unless the
  project says otherwise.
- `System.Threading.Lock` (`private readonly Lock lockObject = new();`) only in net9+ projects compiled at C# 13+; elsewhere
  lock an `object`. The template's `csharp_prefer_system_threading_lock` suggestion is inert at LangVersion 12.
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
`IDE0290` (no primary constructors), `IDE1006`, `CA1016`, `CA1711`. Most repositories carry only the first three — when
one fails on `CA1707`/`CA1711`, copy the template's block. The template has the block **once**, under `[*.cs]`;
`[*.{cs,vb}]` holds the naming rules.

## 5. Roslyn analyzers & code fixes
`DIGI0001` lives in `DiGi.Maintenance/DiGi.Maintenance.Analyzers/ParameterListLineBreakAnalyzer.cs` (fact project
`DiGi.Maintenance.Analyzers.xUnit`).
1. **Two projects, both `netstandard2.0`:** `[Namespace].Analyzers` references only `Microsoft.CodeAnalysis.CSharp` +
   `Microsoft.CodeAnalysis.Analyzers` (the `DiagnosticAnalyzer`s); `[Namespace].Analyzers.CodeFixes` references the
   analyzers project + `Microsoft.CodeAnalysis.CSharp.Workspaces` (the `CodeFixProvider`s).
2. **An analyzer project never references `Microsoft.CodeAnalysis.Workspaces`** or IDE packages (`RS1038`): command-line
   compilers do not provide them, and the analyzer can fail to load.
