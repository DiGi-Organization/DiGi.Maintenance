---
name: coding-automatic-tests
description: "Use when writing or adding xUnit facts - Facts partial class layout, shared fixtures in DiGi.Test/files/, reports in DiGi.Test/user files/reports/, building the changed library before dotnet test (HintPath means it never rebuilds), Short/Medium/Long duration attributes and DIGI_TEST_MAX_DURATION, culture-scoped key facts, reproducing a defect before fixing it, proving a guard can fail, database facts on their own *_Test.conf that restore what they write, phantom Test Explorer entries."
---

# AI Guidelines: Automatic Tests (xUnit)

## 1. Coding rules
Production rules apply unchanged (`Coding - General.md` §1): English, no `var`, type-prefixed names, zero warnings.

## 2. Project structure
- One test project per project: `[ProjectName].xUnit` under `DiGi.Test/`.
- All facts in `public partial class Facts`, files under `/Facts/`, namespace = the test project (`DiGi.Core.xUnit`).
- `Xunit` is a global using — never add `using Xunit;`.
- `[Fact]` per test, named after the class/property/method under test (`Color()`, `PlanarIntersectionResult_Performance()`).
- Every fact has an XML `<summary>`; no blank lines in the block — `<para>` for breaks.

## 3. Fixtures and reports
- **Input fixtures:** one shared folder `DiGi.Test/files/` for every test project (no per-project data folder), read in
  place (no `<CopyToOutputDirectory>`), resolved with `Core.xUnit.Query.FilePath(Assembly.GetExecutingAssembly(), "x.gmf")`
  (asserts the folder exists; needs `using System.Reflection;`) or `assembly.FilesDirectory()`. Large binaries are
  git-tracked — keep samples minimal.
- **Everything a fact writes** (reports, dumps, benchmark logs) goes to the git-ignored `DiGi.Test/user files/reports/`
  via `assembly.ReportsDirectory()` / `Core.xUnit.Query.ReportsDirectory(...)` (both create it); `UserFilesDirectory()` is
  its parent. Never `files/`, never a machine path. Examples: `DiGi.CityGML.xUnit/Facts/InspectDuplicates.cs`,
  `DiGi.GIS.Analytical.xUnit/Facts/BuildingModel_Enclosed.cs`.

## 4. Testing patterns
- **Build what you changed before you test it — `dotnet test` will not.** The xUnit projects reach the code under test by
  `HintPath` (only `DiGi.Core.xUnit` is a `ProjectReference`), so a run uses whatever was last built into each `bin`. The
  symptom is a result identical to the previous run in either direction — a fix that "does not work", a regression that
  "does not exist". Build the changed library first (and the ConsoleApp for a fact calling `Program.Main`):
  ```powershell
  dotnet build "..\DiGi.X\DiGi.X\DiGi.X.csproj" -c Debug -m:1
  dotnet test "DiGi.X.xUnit\DiGi.X.xUnit.csproj" -c Debug -m:1
  ```
  When a run contradicts the change you just made, `Get-FileHash` the consumed `bin` assembly against the build output
  before believing it (a corrected exit code "kept failing" byte-identically because both runs used the old build).
  Benchmarks add more ways to time the wrong binary: `Coding - Performance.md` §2.
- **Assertions:** standard xUnit (`Assert.Equal`, `True`/`False`, `NotNull`/`Null`, `Single`).
- **Serializable types:** one fact per type with `SerializationCheck` and a direct copy-constructor assertion —
  `Coding - Serialization.md` §9.
- **Tolerance boundaries:** assert just inside and just outside the tolerance (`Tolerance.Distance`, `MacroDistance`).
- **Duration classes:**

  | Duration | Time per fact | Attribute |
  |---|---|---|
  | Short | ≤ 2 s | `[Fact]` |
  | Medium | 2–30 s, **or any fact calling a live external service** | `[MediumFact]`; `[MediumSkippableFact]` in the PostgreSQL/WebAPI projects |
  | Long | > 30 s | `[LongFact]` |
  - `DIGI_TEST_MAX_DURATION` = `Short`|`Medium`|`Long` runs everything up to that class and skips the rest with a reason;
    unset = **Medium** (plain `dotnet test` / *Run All* skips only Long).
  - Switch without rebuilding: VS *Test ▸ Configure Run Settings ▸ Select Solution Wide runsettings File* →
    `TestDuration.Short|Medium|Long.runsettings` (DiGi.Test root), or
    `dotnet test DiGi.Test.slnx --settings TestDuration.Short.runsettings`, or `$env:DIGI_TEST_MAX_DURATION = 'Long'`.
  - **Classify by measurement:** the project alone (Debug), never a parallel full-suite run, capped with
    `--blame-hang --blame-hang-timeout 30s --blame-hang-dump-type none`; the blame `Sequence_*.xml` names the one fact over
    30 s (one project = one sequential collection).
  - `[MediumFact]`/`[LongFact]` live in `DiGi.Core.xUnit/Classes/Attribute/`; `[MediumSkippableFact]` is copied into
    `DiGi.PostgreSQL.xUnit`, `DiGi.GIS.PostgreSQL.xUnit`, `DiGi.GIS.PostgreSQL.UI.xUnit`, `DiGi.GIS.WebAPI.xUnit`
    (from `SkippableFactAttribute`). All are in namespace `Xunit`, so the global using finds them. **Never
    `using DiGi.Core.xUnit;`** in a fact file (a second `Query` makes `Query.X` and crefs ambiguous, CS0104/CS1574), and
    never a `Constants` namespace under `DiGi.Core.xUnit` (hides `DiGi.Core.Constants`, CS0234).
  - Append to the `<summary>`: `<para>Medium test (10.5 s): runs when DIGI_TEST_MAX_DURATION is Medium (the default) or Long.</para>`.
  - Measured 2026-10-01: ~2 000 Short facts in 19 s for the whole suite in parallel; Medium adds 47 (83 s); Long adds 6.
    Report: `DiGi.Test/user files/reports/TestDuration.md`.
- **Benchmarks and parity facts** → `Coding - Performance.md` §2–§3.
- **Culture scope for keys and identities** (`Coding - General.md` §1.19): run the assertions a second time under a
  culture with another decimal separator, asserting the raw `ToString()` **differs** while the key does not.
  `CurrentCulture` is per thread, so this is safe under parallel collections:
  ```csharp
  CultureInfo cultureInfo = CultureInfo.CurrentCulture;
  try
  {
      CultureInfo.CurrentCulture = new CultureInfo("pl-PL");

      Assert.NotEqual("[0.5, 12.25]", range_Double.ToString());
      Assert.Equal("[0.5, 12.25]", Query.Key(range_Double));
  }
  finally
  {
      CultureInfo.CurrentCulture = cultureInfo;
  }
  ```
  Reference: `DiGi.Test/DiGi.Typology.Visual.xUnit/Facts/Query_Key.cs`.
- **Reproduce before fixing:** a defect fix opens with a fact that fails **on the unmodified code with the reported
  symptom** (its stack trace when there is one), committed with the fix; build the fixture from real data in
  `DiGi.Test/files/` if a synthetic one will not reproduce it (`Mesh3D_Difference_DenseCluster` and `Mesh3D_Difference_FaultIsolation` reproduced
  [DiGi.Geometry#2](https://github.com/DiGi-Organization/DiGi.Geometry/issues/2)'s `ConstraintEnforcementException` first).
- **Proving a kept fallback is dead:** replace the fallback call with `throw` and run the whole suite; if nothing fails,
  delete it (`DiGi.Geometry`'s conforming-Delaunay path, 326 → 126 lines).
- **A guard must be shown to fail.** A proactive assertion gets no proof for free: construct the violation, watch it
  fail, restore. A smoke fact asserting a predicted year in 1900–2100 "to prove features reached the model" passed for a
  row holding nothing but an identifier (`2012`) — the same binding failure that scored R² −1.771 in deployment.
  **Prefer a differential assertion to a plausibility range:** score the input complete and stripped of the thing under
  test, and assert the results differ.
- **Database facts leave the base as they found it:** connect through the project's own `*_Test.conf`, refuse one naming
  the host conf's database (one plain fact fails on it), snapshot touched rows and restore them in `finally`, remove
  scratch rows before and after, show the restore failing once without it — `Coding - PostgreSQL.md` §6 (reference:
  `bodyplan.PostgreSQL.xUnit`, bodyplan#47). **Create the fact's preconditions itself** (`Ensure*` tables/rows) rather
  than relying on an earlier run's state, and expect an empty database (`42P01` read as null/404, `Coding - PostgreSQL.md` §4).
- **Fixtures too symmetric to fail:** orientation/mirroring/normalisation facts need an asymmetric shape —
  `Coding - Geometry.md` §2.
- **Phantom tests in Test Explorer:** `.vs/<Solution>.slnx/v18/TestStore/0/*.testlog` keeps renamed, moved or deleted facts
  as "Not Run" forever. List them with
  `grep -oa "<Namespace>\.<OldClass>\.[A-Za-z0-9_]*" .vs/<Sln>.slnx/v18/TestStore/0/*.testlog | sort -u` against
  `dotnet test --list-tests`; close VS and delete `TestStore` (only run history is lost). Expect it after any rename sweep.
- **WPF controls without their host** (off-screen render harness) → `Coding - WPF Deferred Loading.md` §7.

## 5. Reference example (`/Facts/PlanarIntersectionResult.cs`)

```csharp
using DiGi.Geometry.Spatial;
using DiGi.Geometry.Spatial.Classes;

namespace DiGi.Geometry.xUnit
{
    public partial class Facts
    {
        /// <summary>
        /// Tests planar intersections just inside and just outside the macro distance tolerance.
        /// </summary>
        [Fact]
        public void PlanarIntersectionResult_ToleranceBoundaries()
        {
            Plane plane = Spatial.Constants.Plane.WorldZ;
            double tolerance = Core.Constants.Tolerance.MacroDistance;

            Segment3D segment3D_Inside = new(new Point3D(0, 0, tolerance - 1e-9), new Point3D(0, 0, 10));
            PlanarIntersectionResult? planarIntersectionResult_Inside = Create.PlanarIntersectionResult(plane, segment3D_Inside, tolerance);
            Assert.NotNull(planarIntersectionResult_Inside);
            Assert.True(planarIntersectionResult_Inside.Intersect);

            Segment3D segment3D_Outside = new(new Point3D(0, 0, tolerance + 1e-9), new Point3D(0, 0, 10));
            PlanarIntersectionResult? planarIntersectionResult_Outside = Create.PlanarIntersectionResult(plane, segment3D_Outside, tolerance);
            Assert.NotNull(planarIntersectionResult_Outside);
            Assert.False(planarIntersectionResult_Outside.Intersect);
        }
    }
}
```
