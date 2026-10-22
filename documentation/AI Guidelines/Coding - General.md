# AI Guidelines: C# General Coding Standards & Architecture

**Environment:** Visual Studio 2026 / Windows 11 / .NET 9.0+ / C# 10+.  
**Domain:** C# plugins & engineering software (Revit API, RhinoCommon, Grasshopper, Dynamo).

---

## 1. Core Coding Rules

1. **Language:** **English only** for identifiers, comments, and documentation.
2. **Explicit Typing (No `var`):** Mandatory explicit variable typing unless compiler-forced (e.g. anonymous types).
   - Use target-typed `new()`: `PointNode pointNode = new();`
   - Use collection expressions `[]`: `List<int> numbers = [];`, `int[] array = [1, 2, 3];`
3. **Variable Naming:**
   - **Standard:** `camelCase` starting with type name (`PointNode pointNode`). Add `_`-suffixed qualifier when needed (`PointNode pointNode_Base`, `pointNode_Temp`).
   - **Collections:** Use pluralized element type name — do not prefix with collection type (`filterConditions`, `point3Ds`; not `conditions`, `listPoints`).
   - **Descriptive Value Types:** Name property after type if unique (`public AggregateFunction AggregateFunction { get; set; }`).
   - **Primitives:** Plain `camelCase` (`double tolerance`, `string name`, `int count`).
4. **Compiler Warnings:** **Zero warnings/analyzer messages allowed.** Handle nullability and validation cleanly.
5. **Block-Scoped Namespaces:** Enforce block-scoped `namespace DiGi.Domain { ... }`. Prohibit file-scoped namespaces (`csharp_style_namespace_declarations = block_scoped`).
6. **Parameter Line Breaks (`<= 7` Rule):**
   - **<= 7 parameters:** Must remain on a **single line**, however long that line becomes.
   - **>= 8 parameters:** Split parameters onto multiple lines, **strictly one parameter per line** (multiple parameters on the same line violate `DIGI0001`).
   - **Scope:** Applies strictly to **parameter declarations** on methods, constructors, local functions, and delegates (enforced via analyzer `DIGI0001`).
   - **Call Sites (`ArgumentList`):** Single-line formatting is standard and preferred for simple argument lists. Multi-line formatting (one argument per line or aligned) is permitted when arguments are complex expressions, multi-line lambdas (`x => { ... }`), object/collection initializers, or when line breaking improves readability.
   - A long signature is not a reason to wrap. Line length is not the trigger — the parameter count
     is, because a signature that reads as one line stays greppable and diffs as one line. A WebAPI
     action binding six query parameters plus a `CancellationToken` is exactly the shape this rule
     protects: wrapping it turns a one-line diff into seven.
7. **Async Naming:** All asynchronous method names must end with `Async` (e.g., `GetDetailsAsync`).
8. **`CancellationToken` Rules (CA1068):**
   - **Position:** `CancellationToken` must ALWAYS be the **LAST parameter** in every method signature and overload.
   - **Optional Parameters:** Insert new parameters *before* the token, never after.
   - **XML Documentation:** Order `<param>` tags to mirror signature order exactly.
   - **Call Sites:** Pass by name: `cancellationToken: cancellationToken`.
   - **Overload Ambiguity:** Prevent CS0121 when reordering by using named arguments for differing parameters.
   - **Detection:** `grep -rnE "CancellationToken [a-zA-Z_]+( = default)?, " --include=*.cs .` (hits prior to last parameter are violations).
9. **Simplify Member Access & Shadowing (IDE0002/IDE0001):**
   - Omit redundant `DiGi.` namespace prefixes when types resolve unambiguously.
   - **Innermost-Namespace Shadowing Exception:** Keep full prefix when a parent namespace shares a segment name with an inner namespace (e.g., `DiGi.WebAPI.Query` vs `DiGi.GIS.WebAPI`). Always rebuild after removing a prefix; keep qualifier if CS0234/CS0246 occurs or if both namespaces contain matching types.
   - **Same-Named Extension Methods Bind By `using`, And The Wrong One Compiles.** The rule above is about
     types and fails loudly as CS0234/CS0246. Its sibling fails silently: when two extension methods share a
     name and both apply to the argument, C# picks the one with the more derived parameter type — but only
     from namespaces that are actually imported. Which one binds is therefore decided by a `using` directive,
     not by anything a reader of the call site can see, and the loser compiles just as happily.
     - **Worked example.** `Core.Query.UniqueId(this ISerializableObject?)` returns a content hash of the
       serialized object. `Core.IO.Query.UniqueId(this IColumn?)` returns the stored column slug
       (`floor_area`) that PostgreSQL and the WebAPI address a column by. `IColumn` derives from
       `ISerializableObject`, so the slug version wins **where `DiGi.Core.IO` is imported** and the hash
       version wins where it is not. `column.UniqueId()` reads identically in both files.
     - **The failure is not an exception.** A projection built from hashes matched no column server side; the
       endpoint returned only the identity columns it always includes and the caller defaulted the rest,
       producing a full-looking 174-column, 1 823-row table in which every feature was `0`. It parsed, it had
       the right shape, and a regressor fitted it without complaint.
     - **Rule:** when more than one same-named extension method can apply, **call the intended one fully
       qualified** (`Core.IO.Query.UniqueId(column)`). An import is not a decision anyone reviews, and
       tidying a `using` block must not be able to change which method runs. Prefer this over relying on
       overload resolution even when the current imports happen to be right.
   - **An Extension Cannot Reuse The Name Of A Property On Its Receiver (CS1955).** Member lookup finds the
     property first, sees a non-invocable member, and stops — extension methods are never consulted, so
     `typology.References(true)` fails with *"Non-invocable member cannot be used like a method"* while a
     `References` list property exists. When migrating `GetX()` to the property-like `X()` (§2 *`Query`
     Naming*), check the receiver has no `X` property first; `Typology.GetReferences(bool)` had to become
     `Query.ReferenceSet` for this reason. Unlike the `using` trap above, this one refuses to compile.
   - **A Method Shadows A Namespace Of The Same Name In Expression Position (CS0119).** Inside a `Facts`
     class that declares `[Fact] public void Typology()`, `Typology.Create.Typology(...)` binds `Typology` to
     the method — write `DiGi.Typology.Create.Typology(...)`. Inside `/Create/Typology.cs` the factory itself
     shadows the namespace the same way, so qualify types as `Classes.Typology`. Type positions are unaffected.
   - **Razor Views Have No Enclosing `DiGi.*` Namespace — Do Not Simplify There.** A `.cshtml` compiles into
     the generated `AspNetCoreGeneratedDocument` namespace, so the innermost-outward lookup this rule relies on
     has no `DiGi.*` chain to walk. `@using DiGi.GIS.WebAPI.UI` in `_ViewImports.cshtml` makes that
     namespace's types visible but not its sub-namespaces: `Constants.Default.UserTokenCookieName` is
     `CS0103`. Fully qualify sub-namespace members (`Constants.*`, `Enums.*`, `Classes.*`) in views.
10. **Project Structure:** Treat codebase as multiple SEPARATE projects, not a monolithic solution.
11. **Output Efficiency:** Direct, technical responses. Omit conversational filler.
12. **Temporary Code Markers (`TODO [MarkerName]`):** Code that exists only until a migration completes must say so at every site, in a form one `grep` can collect.
   - **Tag:** `TODO [MarkerName]:` where `MarkerName` is PascalCase and names the **migration**, not the issue (`[ReferenceFormat]`, `[ReferencedObjectIndexes]`). Reuse the one tag at every site belonging to that migration, so `grep -rn "MarkerName"` returns the complete deletion checklist rather than a sample of it.
   - **State the removal condition** — the observable fact that makes deletion safe ("once every storage archive has been rewritten", "once every deployed database has run this DDL at least once"), not merely that the code is temporary. A marker without one cannot be acted on and never gets removed. Name the tracking issue when there is one.
   - **Placement:** an inline comment at the site; a file header above the `using` block when the whole file is temporary (`DiGi.Core/Query/TryParseLegacy.cs`); `[TEMPORARY]` as the first token of the XML `<summary>` when a whole public member is provisional and removing it is a public-API change (`DiGi.GIS.WebAPI.UI/Controllers/SolarController.cs`).
   - **A workaround for a defect in another DiGi repository is temporary code too.** Name the marker after the workaround, and make the removal condition the upstream fix, naming its issue. `DiGi.GIS.WebAPI.UI`'s `TerrainCuttingMaxBuildingCount = 250` silently skipped terrain footprint cutting above 250 buildings to dodge a `DiGi.Geometry` crash. It said *"Temporary limitation ... until spatial batching optimization is implemented"* in prose but carried no grep-able tag, so no sweep could collect it; it outlived its cause and was found only by reading the call site while investigating something else. Correct form: `TODO [TerrainCuttingCap]: remove once DiGi-Organization/DiGi.Geometry#2 ships the triangulator fix.`
   - **Mark only what is actually temporary.** Permanent code shipped in the same change must not carry the tag, or the sweep stops being a checklist.
13. **Hand-Fixes To Generated Code Are Lost On Regeneration — Put Them In The Generator.** Files produced by
   a tool (ML.NET Model Builder's `*.consumption.cs` / `*.evaluate.cs` / `*.training.cs`, the `mlnet` CLI's
   output, anything carrying an auto-generated header) get corrected by hand and the correction survives
   exactly until the next regeneration, which reverts it in silence. The build then fails, or worse does not.
   - **Record every fix where regeneration cannot reach it:** in the generator or post-processing script that
     produces the file, or failing that in a checklist beside it naming each correction and why. A comment
     inside the generated file is not a record — it is regenerated away with everything else.
   - **Worked example.** One regeneration of `DiGi.GIS.ML/OrtoBuildingDetectionModel.*.cs` reverted five
     previously-applied corrections at once: `Plotly.NET`'s `LinearAxis.init` needs its eight type arguments
     stated because they cannot be inferred; a `<param>` written inside a `<summary>` reads as a duplicate
     param tag (`<paramref>` is what refers to a parameter from prose); non-nullable `string` and `float[]`
     members need initialisers or the build warns; a deployment-aware model path resolver replaced the
     generated `Path.GetFullPath`; and an unqualified `Query.UniqueId` bound to the wrong overload per §1.9.
   - **Generated defaults often embed the machine that ran the tool.** Check for absolute paths before
     committing — `RetrainFilePath` and a Model Builder `.mbconfig` `DataSource.FilePath` both arrive
     hard-coded to the generating workstation. Make them relative to the file that carries them.
14. **Scripted Edits Rewrite Line Endings — Edit Bytes, Not Lines.** The working tree is CRLF by
   `.editorconfig` (`end_of_line = crlf`), and the obvious tools do not preserve it. The damage compiles, so
   nothing fails; what it costs is the review.
   - **`sed -i` on Git Bash converts the whole file to LF.** It reads in text mode and writes `\n`, so a
     one-line namespace substitution silently rewrites every line in the file. Python does the same through
     universal newlines — `io.open(p, encoding="utf-8-sig").read()` strips both the CRLFs and the BOM, and
     writing back with `encoding="utf-8-sig"` *adds* a BOM to a file that never had one.
   - **The symptom is a diff, not a failure.** The build stays green and the tests pass, while every line of
     the file shows as changed and the actual edit is invisible inside it.
   - **`grep -c $'\r'` does not detect it** — it reports every line as matching either way. Count bytes:
     `tr -cd '\r' < file | wc -c` against `tr -cd '\n' < file | wc -c`. Equal means CRLF survived, zero CR
     means it did not.
   - **Edit in binary and assert the match count**, so a pattern that matched nothing — or matched twice —
     fails loudly instead of writing a file that merely looks edited:
     ```python
     data = path.read_bytes()
     assert data.count(old) == expected
     path.write_bytes(data.replace(old, new))
     ```
     A search string spanning more than one line has to carry `\r\n`. Detect the convention per file rather
     than assuming it — `.slnx` and some `.csproj` in these repos genuinely are LF:
     `eol = b"\r\n" if b"\r\n" in data else b"\n"`.
   - **Check before believing a diff stat.** `git diff --stat --ignore-cr-at-eol` shows the real size of the
     change; a whole-file stat that collapses to a few lines under that flag is a line-ending rewrite rather
     than an edit. Note the converse also exists — some committed blobs already hold CRLF, so touching them
     renders every line as changed through no fault of the edit.
   - **The working tree and the committed blob can disagree, and the `git add` flag decides which bytes land in the blob.** With `core.autocrlf=true` and no `.gitattributes`, checkout materialises an LF blob as a CRLF working tree — so the working tree alone does not reveal what the repository stores; read the stored convention from the **blob** (`git cat-file -p HEAD:<path>`, byte-level). And the same CRLF working tree commits an **LF** blob under the default `autocrlf=true` (normalised on the way in) but a **CRLF** blob under `-c core.autocrlf=false` (verbatim). The flag is therefore a choice about the *stored* convention: to keep a stored-LF file LF, commit with the **default**, not `-c core.autocrlf=false`.
   - **The convention can split within one repository.** In these repos `README.md` is stored LF while `.agents/AGENTS.md` and `SKILL.md` are stored CRLF, so a sync script regenerating one set must not assume the other set's ending. A guard that skips (with a warning) when a generated file's line ending would differ from the blob it replaces is the tripwire that catches such a regression before it produces dozens of whole-file rewrites.
   - **Worked example.** `UpdateReadmes.ps1` forced every `README.md` to CRLF *and* committed with `-c core.autocrlf=false`, so CRLF bytes landed verbatim in a blob every repo stored as LF — a full-file rewrite across all 66 repos on a run whose real change was five lines ([DiGi.Maintenance#11](https://github.com/DiGi-Organization/DiGi.Maintenance/issues/11)). The fix detects the stored ending from the blob, emits in that convention, and guards against a mismatch.
   - This is the source-file half of the `\r\r\n` trap in [GitHub - Issues.md](GitHub%20-%20Issues.md) §1,
     which governs the markdown bodies sent to GitHub rather than the files in the tree.
   - **A diff that is only `\ No newline at end of file` is editor noise — revert it.** An IDE that trims
     the trailing newline marks a file modified with nothing else changed; sixteen such files sat in a
     `DiGi.Typology` working tree beside a real redesign. Check each modified file with
     `git diff --ignore-cr-at-eol -- <file>`: an empty result means only the line-ending bytes moved, so
     `git checkout -- <file>` before review rather than carrying it into the commit.

15. **A Check That Skips Absent Input Fails Open.** A guard written as "if a value was given, validate it"
    *passes* when nothing was given — usually the case it most needed to refuse. `DiGi.YOLO`'s
    `YOLOEnvironmentResult` probes the detector weights only `if (!string.IsNullOrWhiteSpace(path_Model))`,
    so the preflight `DiGi.GIS.YOLO.UI#6` added to refuse a bad environment "in seconds instead of after
    exporting a county" did not fire for a `ModelPath` of `null`: the run passed the preflight, exported
    55 366 images over four and a half minutes, and then failed on the first step that actually opened the
    file. **Decide explicitly what an absent value means** — refuse it, or default it — rather than letting
    it fall through the validation as "nothing to check". Where the value is a path, **resolve it the way
    the consumer will resolve it before deciding it is absent**: a preflight probing a different path from
    the one the real call receives is not a preflight.

16. **A Configuration Class's Defaults Are The Contract Wherever No File Is Read.** An options class is
    normally thought of as "what the JSON sets", which makes its property initialisers read as fallbacks.
    The moment one caller constructs it *without* a file, they stop being fallbacks and become that
    caller's entire configuration. `YearBuiltPredictionPipelineOptions.ModelPath` defaulted to `null` while
    its own `<summary>` promised a fallback search that no longer existed — harmless for the console app,
    which always loads JSON, and fatal to every run started from the tray application, whose dialog
    deliberately offers no weights control (`DiGi.GIS.PostgreSQL.UI#9`). **Where a UI or a host
    deliberately omits a control, the default behind it is that surface's answer**, so give it a working
    value and say so in the `<summary>`. Re-check the defaults whenever a new caller *constructs* the class
    rather than deserializing one.

17. **An Extension-Syntax Receiver Only Boxes — It Never Converts Numerically.** `x.Method()` admits only
    identity, implicit reference and boxing conversions on `x`; an implicit *numeric* conversion is not
    considered. With `UniqueId(this int)`, `UniqueId(this short)`, ..., `UniqueId(this object?)` in scope,
    `((byte)5).UniqueId()` binds to the **`object`** overload, while the static form `Query.UniqueId((byte)5)`
    binds to `short` (signed beats unsigned). The same value therefore takes two different code paths
    depending on call syntax, and a numeric type without its own overload silently falls to `object` in
    every extension-syntax call — which is how `dynamic` dispatch and `ToString()` fallbacks get reached.
    Give every primitive the family accepts its own overload (nullable form included).
    **Verify overload-binding and compile-error claims with a probe project, not by reasoning.** In
    `DiGi.Core#5` the issue said these calls "fall to `object`", the implementation summary said they were
    "CS0121-ambiguous", and the review's first draft said "only the nullable forms are CS0121"; a 40-line
    scratch console app printing which overload each call hits settled it in a minute — the issue was
    right, the other two were wrong, and nothing was ambiguous.

18. **A Member Resolved By Name Through Reflection Is A Contract On The Whole Hierarchy.**
    `DiGi.Typology.Query.RuleData(ITypologyFilterRule, object)` reaches the generic `RuleData` through
    `type.GetMethod(nameof(RuleData))` because the non-generic interface does not expose it. That one
    line silently forbids every derived rule from hiding `RuleData` with a `new` overload — the lookup
    would become ambiguous or bind to whichever method reflection prefers — so `DiGi.Typology.Visual`'s
    range and unique-value rules had to be re-parented onto `TypologyFilterRule` instead of deriving from
    the rules they mirror, at the cost of duplicating the base implementation.
    - **Document the constraint at both ends:** at the reflection site (why by name, what it assumes)
      and on the base type's `<summary>` (do not hide this member), because the person deriving a class
      never reads the `Query` that will later dispatch on it.
    - **Prefer a non-generic interface member over `GetMethod`** when the design is still open — an
      `ITypologyFilterRule.RuleData(object?)` returning the base rule data would have made the by-name
      lookup unnecessary.
    - **Probe, do not reason,** before relying on `GetMethod(string)` picking a most-derived overload
      (§1.17): reflection's hide-by-signature rules are not overload resolution.

19. **`ToString()` Is Not A Key.** `Range<T>.ToString()` and an interpolated `$"[{min}, {max}]"` follow
    `CultureInfo.CurrentCulture`, so a dictionary keyed on them files `[0,5, 12,25]` under `pl-PL` and
    `[0.5, 12.25]` elsewhere — a key written on one machine is not found on another, and nothing throws.
    Any string used as an identity — a dictionary key, a `_type`-like discriminator, a stored
    reference, a hash input — renders through `CultureInfo.InvariantCulture`: `"R"` for `double`/`float`
    (with `-0.0` folded to `0`), `"G29"` for `decimal` (scale stripped, since `1.10m == 1.1m`), ticks for
    `DateTime`, the UTC instant for `DateTimeOffset`. `DiGi.Typology.Visual.Query.Key(object)` is the
    reference renderer and its `Query_Key` fact the reference test (`Coding - Automatic Tests.md` §4).
    An `object`-typed value adds a second reason: after a JSON round trip a boxed `2010` comes back as
    `2010.0`, so `Equals` no longer groups it with the value it was — the key must be width-agnostic.

20. **No Caching In An Optimization Unless It Was Explicitly Allowed.** When asked to make code faster, do
    not introduce a caching scheme — a static `Dictionary`/`ConcurrentDictionary`, memoized reflection
    results, cached `MethodInfo`/`ConstructorInfo`/`Type` lookups — unless the request says caching is
    allowed for that change. It applies to every repository in the workspace.
    - **Why:** an optimization pass over `DiGi.Core` added caches to `Description`, `Serialize`, `Value` and
      `Clone`, and all of it was rolled back. A cache brings static mutable state, thread-safety obligations
      and unbounded memory growth into a library that every host loads, and none of that is visible at the
      call site.
    - **Reach for these first:** drop throwaway allocations (`ToList().ConvertAll(...)`), avoid repeated
      enumeration, replace an `O(n²)` scan with a `HashSet`/`Dictionary` built for **one** pass and discarded
      afterwards, copy hot data out of object graphs into flat arrays (`Coding - Geometry.md`).
    - **When a cache really is the best fix** — typically a hot reflection path — propose it with the
      measurement and ask before implementing it.

---

## 2. Architecture — `DiGi.Core` Pattern

Strictly separate data models from business logic using anemic models + static extension methods.

### Structure Breakdown
- **Models (`/Classes`):** Namespace `[Project].Classes`. Lightweight data containers (properties + basic constructors only). **No business logic.**
- **Interfaces (`/Interfaces`):** Namespace `[Project].Interfaces`.
- **Enums (`/Enums`):** Namespace `[Project].Enums`.
- **Business Logic:** Static partial classes providing extension methods. Never create service/manager classes.
  - `Query` (`/Query`): Returns query results. **Does NOT modify source.**
  - `Modify` (`/Modify`): Modifies state/properties of target object in-place.
  - `Create` (`/Create`): Instantiates and returns new objects.
  - `Convert` (`/Convert/To[TargetArea]`): Transforms objects/primitives into target representations (`ToSystem_String`, `ToEPW_DateTime`).

### Interface Contract Exception (Geometry Primitives)
- Methods required by an interface implemented by a `/Classes` type MUST be implemented as **instance methods on the class** (e.g., `Ellipse2D`, `Circle2D`, `Polygon2D` implementing `IBoundable2D`, `ITransformable2D`, `IMovable2D`, `IClosedCurve2D`).
- **Do NOT migrate interface contract methods to `Query`/`Modify` extensions.**
- Check interface hierarchy before proposing method relocations.
- Private helper methods are permitted on interface-implementing geometry model classes.

### Constructors Stay Cheap — Put Calculation in `Create`

- **Constructors on `/Classes` types assign and clone. Nothing else.** No validation sweep, no
  normalisation, no cleanup pass, no geometric or numeric computation — not even an `O(n)` scan over
  a collection the caller just handed over. A constructor is on the hot path of every clone, every
  copy constructor and every deserialization, and a caller who already holds clean data must not pay
  for a check they do not need.
- **Any such work belongs in a `Create` factory** named after the type it returns, at
  `/Create/[TypeName].cs`. The factory does the work, then calls the plain constructor. It returns
  the type as **nullable** and returns `null` when the input cannot make a valid object, so the
  guard is a return value rather than an exception.
- **Order inside the factory:** materialise and filter the input, run the cleanup, *then* check the
  result is still valid. Validating before the cleanup measures the wrong thing — a ring of three
  positions that repeats a corner passes a "three or more" check and then becomes a two corner
  polygon.
- **Document the split on both sides.** The constructor's `<summary>` points at the factory for
  callers whose data is not already clean; the factory's `<summary>` says what it removes and why
  the constructor does not.

**Reference:** `DiGi.Geometry.Spatial.Create.Polygon3D(IEnumerable<Point3D?>?, double)` and
`DiGi.Geometry.Planar.Create.Polygon2D(IEnumerable<Point2D?>?, double)` — both drop points repeating
their predecessor via `Modify.RemoveDuplicates(..., closed, tolerance)` before checking the corner
count, while `Polygon2D`'s constructors store whatever they are given.

```csharp
// /Classes — plain assignment, no work
public Polygon2D(IEnumerable<Point2D>? point2Ds)
    : base(point2Ds)
{
}

// /Create — the work lives here, and the guard runs after it
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

    return new Polygon2D(point2Ds_Temp);
}
```

### File Organisation — One Member Per File

- **`Query`/`Modify`/`Create` — one method per file, named after the method.** A file in `/Query`,
  `/Modify` or `/Create` holds exactly one public method, and the file name is that method's name
  (`/Spatial/Query/NearestIndexes.cs` holds `NearestIndexes`). Do **not** group related methods into
  one file: `TryGetNearestIndexes`, `NearestIndexes` and `NearestNeighbors` are three files, not one.
  - **Overloads are the same method and stay together.** Every `Triangle3D(...)` overload lives in
    `Triangle3D.cs`; the plural `Triangle3Ds(...)` is a different method name and gets
    `Triangle3Ds.cs`.
  - Helpers promoted to `public static` under the encapsulation rule below get their own file too,
    named after the helper.
  - `Convert` keeps its own layout, `/Convert/To[TargetArea]/[TargetType].cs` — file per TARGET
    type, not per method, so all conversions to one target share a file.
- **Nested types get their own file, `[Outer].[Inner].cs`.** A `class`, `struct`, `record` or `enum`
  declared inside another type is moved to its own file next to the outer type's file, declaring the
  outer type `partial` and carrying only the nested type — `/Spatial/Classes/PointCloud3D.Point.cs`
  and `/Spatial/Classes/PointCloud3D.Enumerator.cs` sit beside `/Spatial/Classes/PointCloud3D.cs`.
  Keep the type nested; do not promote it to a top-level type, because that changes the public API
  and usually the name stops making sense on its own (`Point`, `Enumerator`).
  - The outer `partial` declaration is repeated in each file with no XML `<summary>` on it, per the
    "do not document `partial` class declarations" rule.

### Method Encapsulation in Utility Classes (`Query`/`Modify`/`Create`/`Convert`)
- **Prohibit `private static` methods** inside partial utility classes.
- **Reusable helpers:** Implement as `public static` methods within the appropriate partial class.
- **Single-use helpers:** Implement as **local functions (inline methods)** inside the consuming method body.

### `Convert` Class Rules
- File layout: `/Convert/To[TargetArea]/[TargetType].cs`.
- Method shape: `public static` extension method on source type. Return `null` for null/invalid input (do not throw).
- Method naming: `To[TargetArea](this SourceType?)` for single target; `To[TargetArea]_[TargetType](this SourceType?)` when multiple targets exist for a single source.
- **`Convert` is the first choice — never an instance method on the model**, including a performance variant
  that skips defensive cloning (`ToNTS_Coordinates` was moved out of `Segmentable2D` into
  `/Convert/ToNTS/Coordinates.cs`).
- **When a conversion needs the model's state without a clone, add a public opt-out overload of the existing
  getter — not an `internal` accessor.** `Segmentable2D.GetPoints(bool clone)` returns the internal list
  when `clone` is `false`, and its `<summary>` states the caller must not mutate it; `Convert.ToNTS_Coordinates`
  consumes that. A narrow `internal` property for same-assembly speed was rejected and is not a pattern here.

### `Query` Naming Conventions
- Use property-like names without verb prefixes (e.g., `BoundingBox()`, NOT `GetBoundingBox()`).
- **Allowed verb prefixes:** Only `Is`, `Has`, and `Try` (e.g., `IsPlanar()`, `HasMaterial()`, `TryConvert()`).

### Result Type Naming — `IResult` Implementations End in `Result`
- **Any class implementing `IResult` / `ISerializableResult` (in practice, anything deriving from `SerializableResult` or `UniqueResult`) MUST have a name ending in `Result`.** `TerrainPointDensityResult`, not `TerrainPointDensity`; `TerrainPointCoverageResult`, not `TerrainPointCoverage`.
- **Do not stack a second noun for the same idea.** The suffix already says the type reports an outcome, so drop `Summary`, `Report`, `Info`, `Data` and the like rather than keeping both: `TerrainPointCountyResult`, NOT `TerrainPointCountySummaryResult` and NOT `TerrainPointCountySummary`.
- **The `Create` factory is named after the type it returns**, so it takes the suffix too — `Create.TerrainPointDensityResult(...)` in `/Create/TerrainPointDensityResult.cs`, per [File Organisation](#file-organisation--one-member-per-file).
- **Why it matters beyond consistency:** the JSON `_type` discriminator carries the class name, so the name is part of the wire contract. Getting it right at creation is free; changing it afterwards breaks every stored document and every deployed client.
- **Existing violations are NOT to be renamed opportunistically.** `Building2DReferenceUniquenessSummary` and `Building2DReferenceDuplicate` (both `: SerializableResult`, both served by deployed `Building2DController` endpoints) predate this rule. Renaming them is a breaking wire change and needs its own decision, migration and version bump — not a drive-by fix. The rule governs new types.

### Standard Tolerance Constants (`DiGi.Core.Constants.Tolerance.*`)
Never introduce arbitrary magic numbers (e.g. `0.001`, `1e-5`, `0.00001`) when invoking or implementing geometric, spatial, or mathematical calculation routines requiring a tolerance parameter. Always reference canonical constants defined in `DiGi.Core.Constants.Tolerance`:
- `Tolerance.Distance` (`1e-6`): Primary spatial/distance tolerance for point proximity, segment/polygon intersection, vertex deduplication, and bounding box overlap checks.
- `Tolerance.Angle`: Angular tolerance for vector parallelism, orthogonality, and angle comparisons.
- `Tolerance.General` / `Tolerance.Macro`: Macro-level numeric comparison tolerances.

---

## 3. Solution Assets — `files/` vs `user files/`

- **`files/` (Committed):** Non-sensitive, shared deployment assets (`web.config`, `app_offline.htm.bak`). Copied to build output via `CopyFiles` MSBuild target (`AfterTargets="Build"`).
- **`user files/` (Git-Ignored):** Sensitive, user-specific, local machine data (DB credentials `*.conf`, API keys, local paths), and test report outputs (`user files/reports/`). Copied via `CopyUserFiles` target.
  - **Precedence / Overriding Rule:** In case of duplicate relative file paths between `files/` and `user files/`, assets from `user files/` MUST ALWAYS take precedence and override assets from `files/`. To guarantee execution ordering, `CopyUserFiles` MUST specify `AfterTargets="CopyFiles"`.
  - Solution `.gitignore` MUST contain `[Uu]ser [Ff]iles/`. Verify with `git check-ignore -v "user files/file.conf"`.
  - PowerShell scripts requiring environment paths MUST read `.conf` files from `user files/`.
  - Automated test reports, diagnostic dumps, and text logs produced during test execution MUST be saved to `user files/reports/` (resolved via `assembly.ReportsDirectory()`).
  - **`user files/` ships.** `CopyUserFiles` flattens it into `bin`, and `Deploy.ps1` carries `bin` to the
    hosts, so it holds only what the deployed tool reads at runtime. Training data, alternative model weights
    and experiment inputs live outside the workspace and are named by absolute path — for the YOLO detector
    see [Coding - YOLO.md](Coding%20-%20YOLO.md) §3, where 1.17 GB of model variants once rode along on
    every deploy.
  - **Do not print a `user files/` conf to inspect it — not even "redacted" — until the redaction is proven.**
    A pattern that does not match fails silently and prints the secret in clear text. A
    `sed -E 's/(Password|pwd)=[^;]*/…/'` written for a `Key=value;` connection string matched nothing in a
    conf whose shape was `PASSWORD="value"` on its own line, and the password reached the transcript. Learn
    the shape from the key names alone (`grep -o '^[A-Z_]*='`), build the pattern for that shape, and assert
    the secret substring is absent before showing anything. Usually the safer answer is to report only the
    non-sensitive fact you needed (host, database name). If a secret is printed anyway, say so immediately
    — it has to be rotated.
- **Solution Items (`.sln` / `.slnx`):** In Visual Studio 2026 solutions, root-level configuration and build assets must be organized under the `Solution Items` virtual folder:
  - `Directory.Build.props`
  - `Directory.Build.targets`
  - `.editorconfig`
  - `DefaultDocumentation.json` (if present)

---

## 4. Host Dependencies — `HintPath` Drops Transitive NuGet Packages

DiGi projects reference each other with `<Reference><HintPath>..\..\X\bin\X.dll</HintPath>`, never
`<ProjectReference>`. A raw assembly reference is **opaque to NuGet**, and the DiGi class libraries do
not copy their own NuGet dependencies into their `bin`. A library's third-party dependencies therefore
never reach a host that consumes it by `HintPath`.

The same opacity has a build-order consequence inside the workspace, before anything is deployed: MSBuild
cannot see a `HintPath` reference as a project to build either, so building or testing a consumer **never
rebuilds the library it consumes**. `dotnet test` in `DiGi.Test` runs against whatever was last built into
each repository's `bin`, which makes an un-rebuilt edit look like a change that had no effect — see
[Coding - Automatic Tests.md](Coding%20-%20Automatic%20Tests.md) §4.

### Before Adding One — Check What You Already Reference
The cheapest package is the one you do not add. Because of the rule below, every new dependency has to be
re-declared on every deployed host at the same version, so spending a few minutes enumerating the packages
already in the tree is always the better trade. A package is usually far larger than the slice of it
currently in use.

- **Read the package's own XML docs.** Every NuGet package ships them beside the DLL, in the NuGet global
  package folder (`%USERPROFILE%\.nuget\packages\`) under `<id>/<version>/lib/<tfm>/<Id>.xml`. Grep it by
  namespace — it lists every public type with its `<summary>`, which is faster and more complete than a web
  search. Reflect over the assembly (`Assembly.GetExportedTypes()`) for the bare type list, or byte-scan the
  DLL for a type name when reflection-only loading is unavailable on the platform.
- **Check the target framework the consuming project actually builds for.** `DiGi.Geometry` is
  `netstandard2.0`; a type found in a package's `netstandard2.1` folder is not automatically present in the
  `netstandard2.0` one. Verify against the right `lib/<tfm>/` folder before designing around it.
- **Worked example.** [DiGi.Geometry#2](https://github.com/DiGi-Organization/DiGi.Geometry/issues/2) carried
  two proposals: add `Clipper2` + `Cutear`, or hand-write ~200 lines of ear clipping with hole bridging.
  Both were for a triangulator that keeps the polygon's own vertices and supports holes.
  `NetTopologySuite` 2.6.0 — already referenced — ships exactly that as
  `NetTopologySuite.Triangulate.Polygon.PolygonTriangulator` and `PolygonHoleJoiner`, in both TFM folders.
  Zero packages added, and this section never had to be applied.
- **An already-referenced package can still be the wrong answer — check the *variant* you need is
  published.** The rule above says prefer what you already have; this is its counterweight. `Emgu.CV`
  **4.12.0.5764** is referenced across the workspace and exposes an ONNX-capable DNN module
  (`DnnInvoke.ReadNetFromONNX`, `BlobFromImage`, `NMSBoxes`), so scoring a network through it looked
  free. It is not: **`Emgu.CV.runtime.windows.cuda` is published on nuget.org only up to
  `4.4.0.4099`**, so at 4.12 there is no GPU runtime to install and OpenCV DNN through Emgu is CPU-only
  — for a 258-GFLOP network that is the difference between minutes and days. `DiGi.YOLO.ONNX` therefore
  takes `Microsoft.ML.OnnxRuntime.Managed` for inference and keeps Emgu for imaging only. **Presence of
  the package is not availability of the capability:** check the runtime, native or platform-specific
  companion package exists at the version actually in use, not just that the main package does.
- **NetTopologySuite corollary, because it has cost time twice.**
  `NetTopologySuite.Triangulate.ConformingDelaunayTriangulationBuilder` is **not** the general polygon
  triangulator. It inserts Steiner points of its own and throws `ConstraintEnforcementException` when
  constraint splitting fails to converge, which narrow slivers reliably cause. Use
  `NetTopologySuite.Triangulate.Polygon.PolygonTriangulator` (ear clipping, holes joined onto the shell) or
  `ConstrainedDelaunayTriangulator` when triangle quality matters.

### The Rule
- When a `HintPath`-referenced DiGi library needs a NuGet package, re-declare that `PackageReference`
  on the **deployed host** (the `Exe`/`WinExe`/`Microsoft.NET.Sdk.Web` project), at the **exact same
  version**. Add a comment naming the library that owns the dependency.
- **Unless the target framework already provides it.** `System.Drawing.Common` on `net10.0-windows`, and
  anything else in the Windows Desktop or ASP.NET shared frameworks, is already in the deployment unit —
  re-declaring it earns `NU1510` ("will not be pruned … does not need to be referenced explicitly")
  against a house standard of zero warnings. `CheckHostDependencies.ps1` indexes the shared frameworks and
  will not report such an assembly missing, so **build first and let the script name what is actually
  absent**, rather than pre-emptively declaring every package a library mentions.
- The chain runs deeper than the direct reference: `DiGi.Geometry` → `DiGi.Math` → `MathNet.Numerics`.
  Audit the whole closure, not just the assemblies listed in the `.csproj`.
- Do **NOT** fix this with `CopyLocalLockFileAssemblies=true` on the netstandard2.0 library — it bloats
  its `bin` with `System.*` 4.3.0 shims.
- `<ProjectReference>` consumers (siblings, `.xUnit`, `.Rhino`) are unaffected; NuGet flows normally there.
- **A `HintPath` also does not carry the *assembly* reference onward, and that half fails loudly.** A
  project consuming library A by `ProjectReference`, where A reaches library B by `HintPath`, cannot
  see B's types at compile time — `CS0234`/`CS0246` on B's namespaces. Re-declare B with its own
  `HintPath` in the consumer. This is why every `.xUnit` project lists the DiGi assemblies its subject
  depends on rather than just the subject: `DiGi.YOLO.ONNX.xUnit` project-references
  `DiGi.YOLO.ONNX` and still needs `DiGi.YOLO` declared, because `DiGi.YOLO.ONNX` reaches it by
  `HintPath`. Unlike the NuGet half above this cannot ship silently — it will not compile — so it costs
  diagnosis time rather than a corrupted run.

### The Failure Signature — Read This Before Suspecting the Data
**A missing transitive dependency produces a partial result, not an error.** `FileNotFoundException` is
thrown per item deep inside a loop, so a batch run completes and reports success while silently
delivering less than it should. County 5 modelled **65 % of 33 687 buildings and reported success**; the
shortfall was found by sampling the database, not by any log entry.

> When a run completes but delivers less than it should, check the host's output directory for missing
> assemblies **before** investigating the data.

**A green build and a green test suite prove nothing.** `DiGi.Test/DiGi.GIS.Analytical.xUnit` re-declares
`QuikGraph` for exactly this reason, so the suite exercised the storey split successfully while the
shipped application could not.

### Extension Hosts Are One Probing Set
`DiGi.GIS.WebAPI`, `DiGi.GLTF.WebAPI`, `DiGi.Communication.WebAPI` and `DiGi.User.WebAPI` deploy into
`DiGi.WebAPI.WindowsService\bin\extensions\<name>` and are loaded into `AssemblyLoadContext.Default`
with cross-directory `AssemblyDependencyResolver`s. Audit the host output **together with** its
`extensions\*` folders, and declare shared dependencies once on `DiGi.WebAPI.WindowsService` — that is
already how `Microsoft.OpenApi` and `Serilog` reach the extensions.

### The Other `extensions\` Folder Is Not A Probing Set
The section above is about assemblies loaded **into** a host process. `DiGi.GIS.PostgreSQL.UI` uses the
same folder name for something structurally different, and the two must not be reasoned about together:
`bin\extensions\<tool>\` there holds a **standalone executable started with `Process.Start`**, never
loaded into the tray application. `DiGi.GIS.YOLO.UI.ConsoleApp` is the first of them.

- **It is its own deployment unit.** It carries its own dependency closure and its own `*.conf`, and
  `CheckHostDependencies.ps1` audits it as a unit of its own rather than with `Recurse`. How the Year Built
  runner is assembled and deployed — the opt-in flag, the local sync into the host's `bin`, the allowlist —
  is in [Coding - YOLO.md](Coding%20-%20YOLO.md) §5.
- **Do not drop a plugin assembly in it expecting it to be loaded.** Nothing resolves assemblies from these
  folders.

### A Reference Added To A Library Does Not Reach The Host's `deps.json`
The two traps above are about an assembly being **absent**. This one is about an assembly being **present
and still unloadable**. It surfaces as the same `FileNotFoundException` and is diagnosed completely
differently, so read the message carefully before assuming a missing file.

A `SelfContained` host resolves assemblies through its `*.deps.json`. A file sitting in the output folder
but missing from that manifest is not on the TPA list and does not load:

```
Could not load file or assembly 'DiGi.User.PostgreSQL, Version=0.1.0.0, Culture=neutral,
PublicKeyToken=null'. The system cannot find the file specified.
```

**…while the dll is right there in `bin`.** The manifest was never regenerated. The new
`<Reference><HintPath>` went into a **library** (`DiGi.GIS.PostgreSQL.UI`), while the executable
(`DiGi.GIS.PostgreSQL.UI.Application`) only `ProjectReference`s that library and declares no assembly
references of its own. The library's copy-local items still reach the executable's output directory, so the
file appears — but MSBuild judged the executable's dependency file up to date, because none of **its** own
inputs (its `.csproj`, its `project.assets.json`) had changed. The tell is an `.exe` whose `deps.json` is
older than the `.exe` itself; the one that shipped this was four days stale.

- **Rebuild the executable with `--no-incremental`** (or clear its `obj`) after changing the assembly
  references of any library it consumes. A normal incremental build is not enough, and nothing warns.
- **Confirm membership, not presence:** `grep -oE '"DiGi\.[A-Za-z.]+/[^"]*"' bin/<App>.deps.json`.
- **The deployed copy is a second instance of the same staleness.** `SyncDirectory.ps1` carries the fresh
  `.exe` and dlls across next to the stale manifest, so `SOFTWARE_DIRECTORY\<product>` keeps crashing after
  the workspace has been fixed. Re-sync **after** the full rebuild, and check the destination's `deps.json`
  timestamp rather than its `.exe`.
- **Only launching the host proves it.** Unit tests cannot: an `.xUnit` project re-declares its own
  references and therefore gets its own, correct manifest. Neither can the script below.

**Second confirmed instance (DiGi.PRG).** `DiGi.PRG` and `DiGi.PRG.Geometry` were added as
`<Reference><HintPath>` to the library `DiGi.GIS.PostgreSQL.UI`, consumed by the host
`DiGi.GIS.PostgreSQL.UI.Application`. Identical symptom: `FileNotFoundException` for
`DiGi.PRG.Geometry` at runtime, dll present in the deployment folder, absent from `deps.json`.
Confirmed fix: `dotnet build --no-incremental` on the host regenerated its `deps.json` and the
assembly resolved. The host `.csproj` was also updated to re-declare the two references explicitly;
this is redundant but harmless and self-documenting — either approach alone is sufficient.

### Build-Time Symptoms Of The Same Opacity
The sections above are about what a deployed host fails to load. The same `HintPath` opacity produces four
compile-time failures in the workspace, each of which looks like a defect in the change you just made.

- **`CS0012` from overload resolution — fix the `.csproj`, never the call site.** To resolve an overloaded
  call the compiler loads the parameter types of **every** same-named candidate, including overloads your
  arguments could never bind to. If one candidate's type lives in an assembly the caller does not reference
  directly, the error is *"type '…' is defined in an assembly that is not referenced"*, not "no matching
  overload". Known offenders: `GIS.Query.Reference()` (candidates typed from `DiGi.BDOT10k` and `DiGi.GML`),
  `Convert.ToDiGi` (`DiGi.BDOT10k`), `Analytical.Create.BuildingModel` (`DiGi.Geometry`), and
  `Geometry.Planar.Query.Union` (`NetTopologySuite` — a NuGet package, fixed with a `PackageReference` at the
  version `DiGi.Geometry` uses). The error names the assembly; grep the overload set
  (`grep -rhnE "public static .* <Method>\(this "`) to find the candidate, then add the direct reference. It
  is **latent**: it can appear only after an unrelated library is rebuilt, so confirm with `git stash` and a
  rebuild before treating it as your own breakage.
- **A wall of `CS0246`/`CS0234` that vanishes under `-m:1` is a parallel-build race.** A host that reaches the
  same library both by `ProjectReference` and (through another project) by `HintPath` — most
  `*.UI`/`*.Application` projects — compiles the reader while the library's dll is being rewritten.
  `DiGi.GIS.UI.Application` produced 47 such errors, none related to the edit. Rebuild with `-m:1`, or build
  the dependency first; do not chase the messages.
- **A `HintPath` also probes the folder it points into.** MSBuild resolves unlisted dependencies from that
  directory, and the `bin` of a library built with `CopyLocalLockFileAssemblies=true` holds a whole,
  possibly stale, closure. Adding `DiGi.GIS.IO` to `DiGi.GIS.PostgreSQL.xUnit` took it from 0 to 66 `CS1574`,
  because `DiGi.GIS.IO/bin` carried 26 dlls including a `DiGi.GIS.dll` seven hours older than the canonical
  one. **Count first:** `ls <lib>/bin/*.dll | wc -l` — one or two is a plain library, twenty is a deployment
  closure, and taking what you need inline (a column needs only its name) beats taking the reference. This
  one is stable across rebuilds, unlike the race above.
- **`--no-incremental` on a solution can delete the `HintPath` target it then compiles against.** A
  solution whose xUnit project reaches `DiGi.Core` through `DiGi.Core.xUnit`'s `ProjectReference`, while its
  library reaches `DiGi.Core` by `HintPath`, cleans `DiGi.Core\bin` (DiGi.Core, .Parameter, .Relation,
  .Drawing) as part of the rebuild and then fails to compile the library before those are rebuilt —
  `dotnet build DiGi.Python.slnx --no-incremental`, 2026-10-15 (DiGi.Maintenance#14). Rebuild such a
  solution incrementally, or rebuild `DiGi.Core` first. The `deps.json` advice above is per executable
  `.csproj`, not per solution.

### The Check
Run after building; it inspects compiled output, not project files.
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\CheckHostDependencies.ps1"
PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\BuildAll.ps1" -Configuration Release -CheckDependencies
```
It reads each output assembly's reference table with `System.Reflection.Metadata.PEReader` and reports
every reference that resolves neither inside the deployment unit nor in a shared framework. Reviewed
exceptions are declared per unit inside the script, each with a stated reason — an unexplained entry
there re-hides the exact class of bug the script exists to find.

**What it does not check: `deps.json` membership.** It asks whether a referenced assembly resolves as a
**file** inside the deployment unit, which is not the same question as whether the host will load it — see
the section above. It reported *"No missing dependencies"* for a deployment unit whose application could not
start. Launching the host is the only check that covers both halves.

---

## 5. Serialization Pattern (`SerializableObject` / `ISerializableObject`)

Classes requiring JSON persistence, cloning, or polymorphic deserialization MUST inherit `DiGi.Core.Classes.SerializableObject`.

### Class Requirements
1. **Marker Interfaces (`/Interfaces`):**
   - `public interface I<Project>Object : DiGi.Core.Interfaces.IObject`
   - `public interface I<Project>SerializableObject : I<Project>Object, DiGi.Core.Interfaces.ISerializableObject`
2. **Backing Fields:** `private readonly`, decorated with `[JsonInclude, JsonPropertyName(nameof(PublicPropertyName))]`.
3. **Three Constructors (Mandatory Order):**
   - **Primary:** `(param1, param2)` — sets backing fields.
   - **Copy:** `ClassName(ClassName? source) : base(source)` — clones all fields:
     - Primitives/strings: copy by value.
     - Primitive lists: `source.list == null ? null : new List<T>(source.list)`.
     - `SerializableObject` lists: iterate source and clone: `if (Core.Query.Clone(item) is ItemType item_Temp) list.Add(item_Temp);`. Do NOT cast `IEnumerable.Clone()` directly to `IList`.
     - Single nested `SerializableObject`: `field = Core.Query.Clone(source.field);`.
   - **JSON:** `ClassName(JsonObject? jsonObject) : base(jsonObject)` — empty body delegation.
4. **Properties:** `[JsonIgnore]` get-only returning field.
5. **Timestamp & Date Fields (`DateTimeOffset` Standard):**
   - Always use `DateTimeOffset` (or `DateTimeOffset?`) for timestamps and date-time properties and backing fields instead of `DateTime`.
   - `DateTime` values with `DateTimeKind.Unspecified` cause timezone offset ambiguity, local time drift, and round-trip equality assertion failures in `SerializationCheck` / JSON deserialization across environments with different UTC offsets. `DateTimeOffset` guarantees standard `ISO 8601` serialization with explicit UTC offset persistence.
6. **A `JsonValue` Has Two Implementations — Hash and Compare by JSON Kind, Not CLR Type.**
   `Create.JsonNode` builds values through `JsonValue.Create(object)` (a CLR-backed `JsonValueCustomized<object>`),
   while `JsonNode.Parse` yields element-backed values. They answer differently:
   - `TryGetValue<T>` on a CLR-backed value is `Value is T` — a boxed `short`, `float`, `decimal`, `char`,
     `DateTimeOffset` or `Guid` fails `TryGetValue<int/long/double/string>`; the parsed form of the same
     value succeeds as `int`/`double`/`string`.
   - `GetValue<object>()` on a parsed value returns the **`JsonElement`**, not a CLR primitive; an
     `object`-typed dispatch then falls through to `JsonElement.ToString()` (raw text) with no error.
   - A whole-number `double` serializes as `5` and parses back as `int`.
   Any identity, hash or equality derived from a `JsonNode` must therefore switch on
   `jsonValue.GetValueKind()` and read the JSON-level value (`ToJsonString()` for numbers, the decoded
   string for strings) so that a node built from an object and the same node read back from a file agree.
   Reference: `DiGi.Core.Query.UniqueHash(JsonNode)`; the round-trip fact is `UniqueId_JsonObjectRoundTrip`.
   Numbers hash over their JSON text, which is shortest-round-trip on .NET Core 3.0+ and `G15` on .NET
   Framework — the one cross-runtime split that cannot be closed from user code.
   - **Member-level consequence — an `object` member holding a number.** The text round trip
     (`Convert.ToSystem_String` → `Convert.ToDiGi<T>`) hands a boxed `int` back as `double`, so
     `UniqueValueRuleData(2010)` is no longer `Equals`-equal to itself after a reload; and `Clone()`
     (`ToJsonObject` → `new T(JsonObject)`, no text parse) throws
     `InvalidOperationException: A value of type 'System.Object' cannot be converted to a 'System.Double'`
     because `Query.Value` asks the CLR-backed node for a `double` it does not hold
     ([DiGi.Core#6](https://github.com/DiGi-Organization/DiGi.Core/issues/6)). Until #6 ships: never key or
     compare an `object` member with `Equals` (render it through an invariant, width-agnostic key — §1.19),
     and `SerializationCheck` such a type with a string value, marking the deferred numeric check
     `TODO [ObjectMemberClone]` so the sweep finds it when #6 closes.
7. **How The DiGi Serializer Collects And Applies Members — Traps That Raise No Error.**
   `Query.SerializableMemberInfos` walks `BaseType` and reflects every level with
   `NonPublic | Public | Instance`; `SerializationMethodCollection` keys the result by member name. Each trap
   below leaves an object that deserializes "successfully" with a member missing or changed:
   - **Setters run in JSON document order, not declaration order.** `Update` iterates the `JsonObject`, so a
     re-ordered or hand-edited document applies members in whatever order it lists them. Never let one
     member's setter depend on another having run; make a payload self-describing instead (the point-cloud
     reference blob repeats the count the coordinate blob already carries).
   - **Members de-duplicate by name across the hierarchy, and the derived one wins.** A derived member that
     reuses a base member's name silently replaces it, and a `[JsonIgnore]` at any level removes same-named
     base members too. Choose names on a derived serializable type that collide with nothing above it.
   - **A `[JsonInclude]` property with a `private set` on a base class never deserializes on a derived type.**
     Reflected through the derived type, the base's private accessor is invisible, that entry wins the
     name-keyed dictionary, its `SetMethod` is `null`, and the member is skipped. `Typology.SubTypologies` came
     back empty from every `Clone` once `Typology` became generic. Use `protected set`, or a `[JsonInclude]`
     private **field** (fields are collected only from their declaring type); `private set` is safe only on a
     sealed class.
   - **A property with no setter is written but skipped on read.** Array-backed payloads therefore travel
     through a settable single-string property, not a get-only one.
   - **A dictionary is rebuilt with `Activator.CreateInstance(type, dictionary)`.** Keys go on the wire as
     JSON object names, so a `Dictionary<object, T>` filed under `int 2010` comes back under `"2010"`; and the
     rebuilt instance uses the type's **default** comparer, so a `SortedDictionary<string, T>` constructed with
     an ordinal comparer is culture-sensitive after every read or `Clone`. Key serialized maps by string and
     prefer `Dictionary<string, T>` (ordinal, insertion-ordered on both legs).
   - **`byte[]` is a JSON number array, never base64.** `Create.JsonNode` treats it as an `IEnumerable`
     (`"Bytes":[255,216,…]`). A SQL projection of such a member (`v->'Bytes'`) decodes with
     `DiGi.GIS.PostgreSQL.Convert.ToSystem_Bytes(JsonNode)`; `Convert.FromBase64String` throws on every row.
     Seed fixtures from a real `ToJsonObject()`, not from a hand-written guess of the shape.
   - **`Clone()` is a JSON round trip through the `JsonObject` constructor**, never the copy constructor —
     see `Coding - Automatic Tests.md` §4 for what that means for `SerializationCheck`.

---

## 6. Code Reference Snippets

### Core Architecture (`Query`, `Modify`, `Create`, `Convert`, Local Function)

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
        // Property-like naming (no 'Get')
        public static double DistanceToOrigin(this Classes.PointNode pointNode)
        {
            return Math.Sqrt((pointNode.X * pointNode.X) + (pointNode.Y * pointNode.Y));
        }

        public static bool IsValid(this Classes.PointNode pointNode)
        {
            return !string.IsNullOrWhiteSpace(pointNode.Name);
        }
    }

    public static partial class Modify
    {
        public static void MoveNode(this Classes.PointNode pointNode, double deltaX, double deltaY)
        {
            pointNode.X += deltaX;
            pointNode.Y += deltaY;
        }
    }

    public static partial class Create
    {
        public static Classes.PointNode PointNode_ByOffset(this Classes.PointNode pointNode, double offset)
        {
            // Inline helper (local function) for single-use logic
            bool IsValidOffset(double val) => !double.IsNaN(val) && !double.IsInfinity(val);

            if (!IsValidOffset(offset))
            {
                return new();
            }

            PointNode pointNode_Result = new();
            pointNode_Result.Name = pointNode.Name + "_Offset";
            pointNode_Result.X = pointNode.X + offset;
            pointNode_Result.Y = pointNode.Y + offset;
            return pointNode_Result;
        }
    }

    public static partial class Convert
    {
        public static string? ToSystem_String(this Classes.PointNode? pointNode)
        {
            if (pointNode is null)
            {
                return null;
            }
            return $"{pointNode.Name}: ({pointNode.X}, {pointNode.Y})";
        }
    }
}
```

### `SerializableObject` Pattern

```csharp
using DiGi.Core.Classes;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace DiGi.EPW.Classes
{
    public class Holiday : SerializableObject, IEPWSerializableObject
    {
        [JsonInclude, JsonPropertyName(nameof(Name))]
        private readonly string? name;

        [JsonInclude, JsonPropertyName(nameof(Date))]
        private readonly string? date;

        public Holiday(string? name, string? date)
        {
            this.name = name;
            this.date = date;
        }

        public Holiday(Holiday? holiday) : base(holiday)
        {
            if (holiday != null)
            {
                name = holiday.name;
                date = holiday.date;
            }
        }

        public Holiday(JsonObject? jsonObject) : base(jsonObject) { }

        [JsonIgnore]
        public string? Name => name;

        [JsonIgnore]
        public string? Date => date;
    }
}
```

---

## 7. Roslyn Analyzers & CodeFix Architecture

When implementing custom Roslyn analyzers and code fix providers (e.g. in `DiGi.Maintenance`):

1. **Project Decoupling (Rule RS1038):**
   - A Roslyn `DiagnosticAnalyzer` project must **never** reference `Microsoft.CodeAnalysis.Workspaces` or IDE packages.
   - Command-line compilers (`dotnet build`, `csc.exe`, CI pipelines) intentionally do not provide workspace assemblies, and referencing them emits compiler warning `RS1038` and risks runtime resolution crashes.
2. **Two-Project Layout:**
   - **`[Namespace].Analyzers`** (`netstandard2.0`): References only `Microsoft.CodeAnalysis.CSharp` and `Microsoft.CodeAnalysis.Analyzers`. Contains `DiagnosticAnalyzer` types that run during compilation and in IDEs.
   - **`[Namespace].Analyzers.CodeFixes`** (`netstandard2.0`): References `[Namespace].Analyzers` and `Microsoft.CodeAnalysis.CSharp.Workspaces`. Contains `CodeFixProvider` types loaded on-demand by IDEs and formatting tools (`dotnet format`).
3. **Target Framework:** `netstandard2.0` ensures broad compatibility across .NET SDKs and Visual Studio versions.

