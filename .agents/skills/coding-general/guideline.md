# AI Guidelines: C# General Coding Standards & Architecture

Applies to every C# change. Task-specific detail lives in its own file: serialization (`Coding - Serialization.md`),
NuGet / `HintPath` host dependencies and build errors (`Coding - Host Dependencies.md`), project and `.editorconfig`
setup (`Coding - Project Setup.md`), optimizing and benchmarks (`Coding - Performance.md`). Section and rule numbers are
stable — moved items keep a pointer. Incidents and measurements behind the rules:
[Evidence](evidence.md) (read only when a rule is disputed or being changed).

## Checklist
Read this first; open a section only when its line applies to the change.
- English only; no `var`; target-typed `new()`; collection expressions `[]`; block-scoped namespaces; zero warnings (§1.1–1.5).
- Names start with the type name in camelCase + `_` qualifier; acronym types lowercase the first letter only; collections = pluralized element type (§1.3).
- ≤ 7 parameters on one line however long, ≥ 8 one per line (`DIGI0001`) (§1.6). Async names end with `Async` (§1.7).
- `CancellationToken` last; new optional parameters before it; name every argument after a skipped default (§1.8).
- Simplify member access, then rebuild; namespaces bind innermost-outwards; call a same-named extension fully qualified (§1.9).
- Temporary code: `TODO [MarkerName]:` + removal condition at every site; never on permanent code (§1.12).
- A fix to generated code goes into the generator (§1.13). Scripted edits: `Maintenance - Scripts.md` §6 (§1.14).
- A check that skips absent input fails open — decide what absence means (§1.15). Options defaults are the contract (§1.16).
- Extension receivers box, never convert — one overload per primitive; probe binding claims, don't reason (§1.17).
- Reflection by name is a contract on the hierarchy — document both ends, probe `GetMethod` (§1.18).
- `ToString()` is not a key — identity strings render through `InvariantCulture` (§1.19).
- No caching in an optimization unless allowed (§1.20). Log via `Serilog.Modify.Log` templates (§1.21).
- Rethrow only a requested cancellation, before any general catch (§1.22).
- Architecture: data in `/Classes`, behavior in `Query`/`Modify`/`Create`/`Convert` extensions; no service classes; category folders add no namespace (§2).
- Interface-contract members stay instance methods; constructors only assign and clone, work goes in a nullable `Create` factory (§2).
- One public method per file in `Query`/`Modify`/`Create`; no private methods there; `Convert` first for conversions; `Query` names property-like; `IResult` types end in `Result` (§2).
- Enums start with `Undefined`; constants in `X.Constants` categories; tolerances from `DiGi.Core.Constants.Tolerance` (§2).
- Secrets and generated output in git-ignored `user files/`, committed assets in `files/`; never print a conf; edit a build-copied asset at its source (§3).

## 1. Core Rules

1. **English only** — identifiers, comments, documentation.
2. **No `var`** unless the compiler forces it (anonymous types). Target-typed `new()` (`PointNode pointNode = new();`) and
   collection expressions (`List<int> numbers = [];`, `int[] array = [1, 2, 3];`).
3. **Naming:** camelCase starting with the type name, plus a `_`-suffixed qualifier when needed (`PointNode pointNode_Base`,
   `pointNode_Temp`). An acronym type lowercases only its first letter (`gISPostgreSQLConverterManager`, `yOLO…`, `ePW…`).
   Collections: the pluralized element type, no collection prefix (`filterConditions`, `point3Ds`; not `conditions`,
   `listPoints`). A property whose type name describes it and is unique in the class is named after the type
   (`public AggregateFunction AggregateFunction { get; set; }`). Primitives: plain camelCase (`double tolerance`).
4. **Zero warnings/analyzer messages** — nullability and parameter validation handled cleanly.
5. **Block-scoped namespaces** (`namespace DiGi.Domain { ... }`); file-scoped are prohibited (`Coding - Project Setup.md` §4).
6. **Parameter line breaks (`<= 7` rule, analyzer `DIGI0001`):** a declaration (method, constructor, local function,
   delegate) with ≤ 7 parameters stays on one line however long; ≥ 8 → strictly one parameter per line. Line length is
   never the trigger: a WebAPI action binding six `[FromQuery]` parameters plus a token stays one greppable line that diffs
   as one. Call sites prefer one line; multi-line is allowed for complex expressions, multi-line lambdas and initializers.
7. **Async method names end with `Async`.**
8. **`CancellationToken` is the LAST parameter (CA1068)** of every method and overload; insert new optional parameters
   before it and reorder the `<param>` tags to match.
   - **At call sites, pass by name every argument after a skipped default** (`commandTimeout: 30`,
     `cancellationToken: cancellationToken`), so an inserted parameter fails to compile instead of rebinding (an inserted
     `int maxGroups` once silently took every positional caller's timeout). Named arguments also avoid CS0121 between
     overloads after a reorder.
   - Detect: `grep -rnE "CancellationToken [a-zA-Z_]+( = default)?, " --include=*.cs .` — any hit not last is a violation.
9. **Simplify member access (IDE0002/IDE0001) — then rebuild.** Inside `DiGi`, drop qualifiers the compiler does not need
   (`Serilog.Modify.Log(...)`). C# binds the first segment against each enclosing namespace innermost-outwards with no
   fallback: from `DiGi.GIS.PostgreSQL.UI.Classes`, `WebAPI` is `DiGi.GIS.WebAPI`, so `DiGi.WebAPI.Query.GetAsync` keeps
   its prefix (same for `Core`, `Geometry`, `Analytical`). If both candidates expose the member it compiles and calls the
   wrong one. Leave `<see cref>` targets alone.
   - **Same-named extension methods bind by `using`, and the wrong one compiles.** The more derived parameter wins, but
     only among imported namespaces: `Core.Query.UniqueId(this ISerializableObject?)` is a content hash,
     `Core.IO.Query.UniqueId(this IColumn?)` the stored slug (`floor_area`); `column.UniqueId()` returns the hash wherever
     `DiGi.Core.IO` is not imported. **When several can apply, call the intended one fully qualified**
     (`Core.IO.Query.UniqueId(column)`).
   - Binding errors that refuse to compile:

     | Error | Cause | Fix |
     |---|---|---|
     | `CS0234`/`CS0246` after shortening | namespace shadowing (above) | restore the prefix, comment why |
     | `CS1955` non-invocable member | an extension reuses a property name of its receiver (`typology.References(true)`) | rename (`Typology.GetReferences` became `Query.ReferenceSet`); check before turning `GetX()` into `X()` |
     | `CS0119` | a method shadows a same-named namespace in expression position (`[Fact] void Typology()`, or the factory in `/Create/Typology.cs`) | `DiGi.Typology.Create.Typology(...)`; `Classes.Typology` for types |
     | `CS0103` in a `.cshtml` | views compile into `AspNetCoreGeneratedDocument`, and `@using DiGi.GIS.WebAPI.UI` in `_ViewImports.cshtml` exposes no sub-namespaces (`Constants.Default.UserTokenCookieName` fails) | fully qualify `Constants.*`, `Enums.*`, `Classes.*`; never simplify in views |
     | `CS0012` | a `HintPath` overload candidate | `Coding - Host Dependencies.md` §6 |
10. **Separate projects**, not one monolithic solution — handle namespaces and references accordingly.
11. **Output efficiency:** direct, technical answers without filler.
12. **Temporary code carries `TODO [MarkerName]:`** — PascalCase, naming the **migration**, not the issue
    (`[ReferenceFormat]`, `[ReferencedObjectIndexes]`), reused at every site so `grep -rn "MarkerName"` is the complete
    deletion checklist.
    - State the **removal condition** — the observable fact that makes deletion safe ("once every deployed database has
      run this DDL at least once") — and the tracking issue when there is one.
    - Inline at the site; a file header above the `using` block when the whole file is temporary
      (`DiGi.Core/Query/TryParseLegacy.cs`); `[TEMPORARY]` first in the `<summary>` when removing a public member is an
      API change (`DiGi.GIS.WebAPI.UI/Controllers/SolarController.cs`).
    - A workaround for a defect in **another** DiGi repository is temporary too: name the marker after the workaround and
      make the upstream fix the removal condition: `TODO [TerrainCuttingCap]: remove once DiGi-Organization/DiGi.Geometry#2 ships
      the triangulator fix.`
    - Never tag permanent code shipped in the same change.
13. **Hand-fixes to generated code are lost on regeneration — record them in the generator.** Files a tool writes (ML.NET
    Model Builder `*.consumption.cs`/`*.evaluate.cs`/`*.training.cs`, `mlnet` output, anything with an auto-generated
    header) revert every hand correction silently; a comment inside them is regenerated away. Put each fix in the
    generator or post-processing script, or in a checklist beside the file. Generated defaults embed the generating machine
    (`RetrainFilePath`, `.mbconfig` `DataSource.FilePath`) — make them relative before committing.
14. **Scripted edits and line endings** → `Maintenance - Scripts.md` §6.
15. **A check that skips absent input fails open.** "If a value was given, validate it" passes when nothing was given
    (a probe guarded by `if (!string.IsNullOrWhiteSpace(path_Model))` lets a `null` path through the preflight). Decide
    what absence means (refuse or default), and resolve a path the way the consumer will before calling it absent.
16. **A configuration class's defaults are the contract wherever no file is read.** Once a caller constructs options
    without a file, the initialisers are its entire configuration. Where a UI omits a control, give the default a working
    value and say so in the `<summary>`; re-check the defaults whenever a new caller constructs the class.
17. **An extension-syntax receiver only boxes — it never converts numerically.** With `UniqueId(this int)`,
    `(this short)`, …, `(this object?)` in scope, `((byte)5).UniqueId()` binds to `object` while `Query.UniqueId((byte)5)`
    binds to `short`. Give every primitive the family accepts its own overload (nullable included). **Verify binding and
    compile-error claims with a scratch console app, not by reasoning.**
18. **A member resolved by name through reflection is a contract on the whole hierarchy.** `DiGi.Typology.Query.RuleData`
    calls `type.GetMethod(nameof(RuleData))`, which forbids any derived rule from hiding `RuleData` with `new`. Document
    the constraint at the reflection site and in the base type's `<summary>`; prefer a non-generic interface member
    (`ITypologyFilterRule.RuleData(object?)`) while the design is open; probe `GetMethod` (hide-by-signature is not
    overload resolution).
19. **`ToString()` is not a key.** `Range<T>.ToString()` and `$"[{min}, {max}]"` follow `CurrentCulture`, so a key filed
    as `[0,5, 12,25]` under `pl-PL` is not found elsewhere, and nothing throws. Every identity string (dictionary key,
    discriminator, stored reference, hash input) renders through `CultureInfo.InvariantCulture`: `"R"` for
    `double`/`float` with `-0.0` folded to `0`, `"G29"` for `decimal`, ticks for `DateTime`, the UTC instant for
    `DateTimeOffset`; an `object` value must also be width-agnostic (a boxed `2010` reloads as `2010.0`). Reference:
    `DiGi.Typology.Visual.Query.Key(object)` and its `Query_Key` fact (`Coding - Automatic Tests.md` §4).
20. **No caching in an optimization unless the request explicitly allows it** — no static dictionaries, memoized
    reflection, cached `MethodInfo`/`Type`; propose a cache with its measurement and ask. Detail: `Coding - Performance.md` §1.
21. **Log through `Serilog.Modify.Log` (DiGi.Serilog)**, never `ILogger` (only the MVC app `DiGi.GIS.WebAPI.UI` uses one).
    Structured templates with PascalCase placeholders, never interpolation; the first placeholder names the source:
    `Serilog.Modify.Log(Serilog.Enums.LogEventLevel.Error, "{Type}: county {CountyId} failed", nameof(X), countyId)` (or
    `{Method}`). Information is the overload without a level. `Log(exception, "…", args)` **always logs at Error** — for a
    Warning pass `exception.Message` as an argument with `LogEventLevel.Warning`. Release builds drop Debug. Inside the
    WebAPI host the log file sits beside the calling assembly (`extensions\<name>\logs\`), not in the host's folder.
22. **Rethrow only a requested cancellation.** Put
    `catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }` before any general
    `catch (Exception)` in loops and per-item work; otherwise Stop is swallowed and the run continues, or ends Failed
    instead of Canceled. An `OperationCanceledException` whose token was not cancelled (a timeout) is a failure.

---

## 2. Architecture — `DiGi.Core` Pattern

Data and behavior are separate: anemic models plus static extension methods.
- **`/Classes`** (`[Project].Classes`) — data only; **`/Interfaces`** (`[Project].Interfaces`); **`/Enums`** (`[Project].Enums`).
- Behavior is an extension method in a `public static partial class`: **`Query`** (`/Query`, returns a result, never
  mutates), **`Modify`** (`/Modify`, mutates the target), **`Create`** (`/Create`, builds a new object), **`Convert`**
  (`/Convert/To[TargetArea]/`, see below).
- **No service classes for behavior.** Process-wide registries are `*Manager` classes, exposed as get-only static
  properties on `public static partial class Settings` (`Settings/Settings.cs`, e.g. `DiGi.Core`, `DiGi.Serilog`) or built
  by `Create.XManager()` and registered as DI singletons. Extend an existing manager; never add one to hold behavior that
  belongs in `Query`/`Modify`/`Create`/`Convert`.
- **Category folders add no namespace segment.** Files in `Classes/Options`, `/BackgroundTask`, `/Result`, `/Converter`,
  `/Goo`, `/Component`, `Enums/Parameter` and `Convert/ToX` keep `[Project].Classes` / `.Enums` / the root namespace; only
  domain folders (`Planar`, `Spatial`) add one. A Visual Studio-generated `X.Classes.Options` changes the `_type`
  discriminator (`Namespace.Type,Assembly`) and breaks stored JSON (`IDE0130` is suppressed for this).

### Interface-contract members are instance methods
A method declared on an interface the `/Classes` type implements is an instance method on that class — moving it to an
extension leaves the interface unimplemented (CS0535). Behavior-rich geometry primitives (`Ellipse2D`, `Circle2D`,
`Segment2D`, `Polygon2D`, … implementing `IBoundable2D.GetBoundingBox()`, `ITransformable2D.Transform(...)`,
`IMovable2D.Move(...)`, `IClosedCurve2D.{GetInternalPoint, InRange, Inside, GetArea}`) are deliberately not anemic: never
"migrate" or flag them; check the `I*2D` chain under `Planar/Interfaces` / `Spatial/Interfaces` before moving a method.
Private helpers are allowed on such classes.

### Constructors stay cheap — the work goes in a `Create` factory
A `/Classes` constructor assigns and clones, nothing else — no validation sweep, normalisation, cleanup or even an `O(n)`
scan: it is on the hot path of every clone, copy and deserialization. The work goes in `/Create/[TypeName].cs`, a factory
named after the type it returns, which calls the plain constructor, returns the type **nullable** and returns `null` when
the input cannot make a valid object. **Order: materialise/filter → clean up → then validate** (validating first lets a
three-position ring repeating a corner pass "three or more" and become a two-corner polygon). Document the split on both
sides: the constructor's `<summary>` points at the factory; the factory's says what it removes and why the constructor
does not. Reference: `Planar.Create.Polygon2D(IEnumerable<Point2D?>?, double)` / `Spatial.Create.Polygon3D(...)` versus
`Polygon2D`'s constructors.

```csharp
// /Create/Polygon2D.cs — the work, then the guard
public static Polygon2D? Polygon2D(this IEnumerable<Point2D?>? point2Ds, double tolerance = DiGi.Core.Constants.Tolerance.Distance)
{
    if (point2Ds == null)
    {
        return null;
    }

    List<Point2D> point2Ds_Temp = [];
    foreach (Point2D? point2D in point2Ds)
    {
        if (point2D != null)
        {
            point2Ds_Temp.Add(point2D);
        }
    }

    point2Ds_Temp.RemoveDuplicates(true, tolerance);

    if (point2Ds_Temp.Count < 3)
    {
        return null;
    }

    return new Polygon2D(point2Ds_Temp); // the constructor only assigns
}
```

### One member per file
A file in `/Query`, `/Modify` or `/Create` holds exactly one public method and is named after it (`NearestIndexes.cs`);
related methods are separate files (`TryGetNearestIndexes`, `NearestIndexes`, `NearestNeighbors`). Overloads stay together
(`Triangle3D.cs`); a differently named sibling does not (`Triangle3Ds.cs`). `/Convert` keeps one file per **target** type.
A nested type gets its own file `[Outer].[Inner].cs` beside the outer one, which is declared `partial` (no `<summary>` on
the repeated declaration) — keep it nested (`PointCloud3D.Point.cs`, `PointCloud3D.Enumerator.cs`); promoting it changes
the public API. Exception: a Grasshopper Goo + Param pair (`Coding - Grasshopper.md` §2).
Check: `DiGi.Maintenance/Scripts/CheckGuidelineRules.ps1 -Repo <Repo> -Changed` (also the next rule and the `Query` naming).

### No private methods in `Query`/`Modify`/`Create`/`Convert`
A reusable helper becomes a `public static` method of the right partial class (its own file); a single-use helper becomes
a local function inside the method that needs it.

### `Convert` is the first choice for any conversion
`/Convert/To[TargetArea]/[TargetType].cs`, a `public static` extension on the source type, nullable in → `null` out (never
throw). `To[TargetArea](this Source?)` when the source has one natural target in that area; `To[TargetArea]_[TargetType]`
when it has several (`ToNTS` vs `ToNTS_Polygon` on `IPolygonal2D`; `ToSystem_String`, `ToEPW_DateTime`). Never an
instance method on the model — not even a variant that skips cloning (`ToNTS_Coordinates` moved from `Segmentable2D` to
`/Convert/ToNTS/Coordinates.cs`). When a conversion needs model state without a clone, add a public opt-out overload of
the getter (`Segmentable2D.GetPoints(bool clone)`, whose `<summary>` forbids mutating the result), not an `internal`
accessor.

### `Query` naming is property-like
`BoundingBox()`, not `GetBoundingBox()`; the only verb prefixes are `Is`, `Has`, `Try` (`IsPlanar()`, `TryConvert()`).
Recognised exception: an HTTP helper keeps its verb (`PostJsonAsync`, `DiGi.WebAPI.Query.GetAsync`).

### `IResult` names end in `Result`
Anything deriving from `SerializableResult`/`UniqueResult`: `TerrainPointDensityResult`, not `TerrainPointDensity`; no
second noun for the same idea (`TerrainPointCountyResult`, not `…SummaryResult`); the factory takes the suffix
(`Create.TerrainPointDensityResult` in `/Create/TerrainPointDensityResult.cs`). The name is wire contract (the `_type`
discriminator), so existing violations (`Building2DReferenceUniquenessSummary`, `Building2DReferenceDuplicate`, served by
`Building2DController`) are **not** renamed opportunistically — that needs its own decision, migration and version bump.

### Enums
`Undefined` is the first member — implicit `0`, or `= -1` only when `0` is a real or wire value (`AdministrativeArealType`,
`CountryCode`). `[Description("Text")] Member,` on one line (read by `Core.Query.Description`; `TryGetEnum` also matches
descriptions). Never reorder implicit members of an enum that is stored or sent — the integers change. Enums mirroring an
external schema (BDOT10k) or units may have no `Undefined`.

### Constants
`namespace X.Constants`, one `public static class` per category (`Default`, `FileName`, `FileExtension`, `TableName`,
`DirectoryName`, `Count`, `Name`), always referenced qualified (`Constants.FileName.X`). `FileExtension` values carry **no
leading dot** — `Path.GetExtension(p) == FileExtension.X` never matches. Conf names follow `<Area>_<Role>.conf` and are
resolved from `Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)`: `AppContext.BaseDirectory` inside a WebAPI
extension is the host's folder, where the extension's conf is not.

### Tolerances come from `DiGi.Core.Constants.Tolerance`
Never a magic number: `Distance` (1e-6 — point proximity, intersections, vertex deduplication, bounding-box overlap),
`MicroDistance` (1e-9), `MacroDistance` (1e-3), `Angle` (0.0349066 rad ≈ 2° — parallelism, orthogonality).

---

## 3. Solution Assets — `files/` vs `user files/`

- **`files/` (committed):** non-sensitive deployment assets (`web.config`, `app_offline.htm.bak`, a deny-by-default
  `WebAPI_[Feature].conf`).
- **`user files/` (git-ignored):** secrets, credentials and machine-specific settings (`*.conf` connection strings, API keys,
  local paths), and generated output — reports, dumps and logs go to `user files/reports/` (tests:
  `assembly.ReportsDirectory()`). The solution `.gitignore` contains `[Uu]ser [Ff]iles/`; verify with
  `git check-ignore -v "user files/x.conf"`. PowerShell scripts read machine paths from a `user files/*.conf`, never
  hard-coded and never via a custom `.gitignore` entry.
- Both folders are flattened into the output root; `user files/` wins on a duplicate path because `CopyUserFiles` runs
  `AfterTargets="CopyFiles"` (nothing ever creates `bin/user files/` — do not probe it):
  ```xml
  <Target Name="CopyFiles" AfterTargets="Build">
    <ItemGroup><_Files Include="$(ProjectDir)..\files\**\*.*" /></ItemGroup>
    <Copy SourceFiles="@(_Files)" DestinationFiles="@(_Files->'$(OutputPath)%(RecursiveDir)%(Filename)%(Extension)')" SkipUnchangedFiles="true" />
  </Target>
  <Target Name="CopyUserFiles" AfterTargets="CopyFiles">
    <ItemGroup><_UserFiles Include="$(ProjectDir)..\user files\**\*.*" /></ItemGroup>
    <Copy SourceFiles="@(_UserFiles)" DestinationFiles="@(_UserFiles->'$(OutputPath)%(RecursiveDir)%(Filename)%(Extension)')" SkipUnchangedFiles="true" />
  </Target>
  ```
- **`user files/` ships:** `Deploy.ps1` carries `bin` to the hosts, so it holds only what the deployed tool reads at
  runtime. Training data, alternative weights and experiment inputs live outside the workspace, named by absolute path
  (`Coding - YOLO.md` §3).
- **Never print a `user files/` conf — not even "redacted" — until the redaction is proven.** Learn the shape from the
  key names (`grep -o '^[A-Z_]*='`), assert the secret is absent before showing anything, or report only the
  non-sensitive fact (host, database). A printed secret is reported at once — it must be rotated.
- **A build-copied asset is edited only at its source.** A file a build target copies in (`gltf-viewer-core.js` via
  `CopyGLTFViewerCore`, `gis-theme.css` via `CopyGISTheme`) is overwritten by the next build, which looks like a
  mysterious revert. Edit the owner, build, and commit both copies when the copy is tracked (`Coding - WebAPI GLTF.md` §4).

---

## 4. Host Dependencies → `Coding - Host Dependencies.md`

## 5. Serialization Pattern → `Coding - Serialization.md` (items keep their numbers: §5.7 = Serialization §7)

---

## 6. Reference Snippet (one file per member in real code)

```csharp
namespace DiGi.Core.Classes
{
    public class PointNode
    {
        public string? Name { get; set; }
        public double X { get; set; }
        public double Y { get; set; }
    }
}

namespace DiGi.Core
{
    public static partial class Query
    {
        // Property-like name, no "Get"
        public static double DistanceToOrigin(this Classes.PointNode pointNode)
        {
            return Math.Sqrt((pointNode.X * pointNode.X) + (pointNode.Y * pointNode.Y));
        }
    }

    public static partial class Modify
    {
        public static void Move(this Classes.PointNode pointNode, double deltaX, double deltaY)
        {
            pointNode.X += deltaX;
            pointNode.Y += deltaY;
        }
    }

    public static partial class Create
    {
        // Named after the type it returns; null when the input cannot make a valid object
        public static Classes.PointNode? PointNode(this Classes.PointNode? pointNode, double offset)
        {
            // Single-use helper: a local function, never a private method
            bool IsFinite(double value)
            {
                return !double.IsNaN(value) && !double.IsInfinity(value);
            }

            if (pointNode is null || !IsFinite(offset))
            {
                return null;
            }

            return new() { Name = pointNode.Name + "_Offset", X = pointNode.X + offset, Y = pointNode.Y + offset };
        }
    }

    public static partial class Convert
    {
        // /Convert/ToSystem/String.cs
        public static string? ToSystem_String(this Classes.PointNode? pointNode)
        {
            if (pointNode is null)
            {
                return null;
            }

            return string.Format(CultureInfo.InvariantCulture, "{0}: ({1}, {2})", pointNode.Name, pointNode.X, pointNode.Y);
        }
    }
}
```

## 7. Roslyn Analyzers → `Coding - Project Setup.md` §5
