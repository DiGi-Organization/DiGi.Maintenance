---
name: coding-performance
description: "Use when optimizing code or measuring it - no caching unless the request allows it, benchmark facts measured in isolation (in-suite figures are not comparable), warm-up and ranges, A/B against a real baseline with both sides on the intended binary (Debug/Release, harness dll copies, cp/mv mtimes), parity tests bounded by a percentile plus an invariant, and the wiki Benchmark.md page format."
---

# AI Guidelines: Performance — Optimizing, Benchmarks, Parity, Publishing Figures

Test-writing basics (structure, build-before-test, durations): `Coding - Automatic Tests.md`.

## 1. Optimizing — no caching unless the request allows it
Do not add a cache — static `Dictionary`/`ConcurrentDictionary`, memoized reflection, cached
`MethodInfo`/`ConstructorInfo`/`Type` — unless the request says caching is allowed for that change (every repository).
A cache brings static mutable state, thread-safety obligations and unbounded memory into a library every host loads; an
optimization pass over `DiGi.Core` (`Description`, `Serialize`, `Value`, `Clone`) was rolled back for that.
- Reach for these first: drop throwaway allocations (`ToList().ConvertAll(...)`), avoid repeated enumeration, replace an
  `O(n²)` scan with a `HashSet`/`Dictionary` built for **one** pass, copy hot data out of object graphs into flat arrays
  (`Coding - Geometry.md` §6).
- When a cache really is the fix (typically a hot reflection path), propose it with the measurement and ask first.

## 2. Benchmark facts
0. **Measure in isolation:** `dotnet test <project> -c Release --filter "FullyQualifiedName~<TestName>"`. xUnit runs
   collections in parallel, so an in-suite figure is not comparable at all: `Mesh3D_Difference_Performance` read 983 ms
   in-suite vs 1306–1402 ms isolated before a fix, 1134 ms vs 623–790 ms after — comparing across would reverse the sign
   of a 1.9x gain.
1. One warm-up call first (JIT, shader compilation).
2. `System.Diagnostics.Stopwatch.StartNew()` over a large, realistic dataset.
3. Repeat three times, report the **range**.
4. `Assert.True(stopwatch.ElapsedMilliseconds < limit)` — the limit must clear the **in-suite** time (CI runs it that way);
   report the isolated range.
5. **A/B against a real baseline**, never a stale report: keep the pre-change file, swap it back, re-run under identical
   conditions.
6. **Make sure both sides ran the binary you think:**
   - `bin` holds whichever configuration was built last — a Debug `DiGi.Geometry.dll` reached by `HintPath` made new code
     look slower. Build both sides `-c Release`; check the consumed dll's size and timestamp.
   - A scratch harness copies its `HintPath` dll at **its own** build time — rebuild the harness after every library
     rebuild, or resolve from the library `bin` with `AssemblyLoadContext.Resolving`.
   - A file restored with `cp`/`mv` keeps its old mtime, so an incremental build skips it. `dotnet test` rejects
     `--no-incremental`: `dotnet build --no-incremental`, then `dotnet test --no-build`.

## 3. Parity tests — comparing two implementations
For a rewrite, port or second engine the acceptance is a comparison, and the shape of the bound decides its worth.
- **Measure the distribution before stating the tolerance** (median, percentiles, outliers), then write the assertion.
- **Bound a percentile plus a per-item structural invariant**, not a maximum. ONNX vs CUDA/torch detector over 2 000
  images: median deviation 0.004 px, p99 0.034 px, worst 3.31 px — a maximum would have needed ~4 px and noticed nothing;
  the invariant (matched-pair overlap > 0.95) guarantees no item became a different thing.
- **Diagnose the outlier before excusing it.** "Floating point" is a hypothesis: the 3.31 px pair had one item per side
  and confidences agreeing to 1e-5 while the geometry moved, which pointed at one stage (a softmax expectation in stride units).
- **Guard band around any reporting threshold** — exclude items on the cutoff from count comparisons and say so.
- **Write the report** to `assembly.ReportsDirectory()` and keep both outputs when a bound is missed.
- **Machine-specific inputs** (large models, an external interpreter) come from a git-ignored conf; the fact returns
  without asserting when absent. Put the sample size there too and assert a percentile only above a stated minimum count.

## 4. Publishing figures — the wiki `Benchmark.md` page
Location `DiGi/wiki/<repo>.wiki/Benchmark.md`, linked from `Home.md` (workflow: `GitHub Wiki.md`). Every number comes
from a committed `[Fact]` in `<repo>.xUnit`, measured per §2 — never hand-typed.
1. `# Benchmark` + a short summary pointing at the facts.
2. `## Test machine spec` — two-column table from the actual machine (`Get-CimInstance`, `dotnet --version`): CPU (with
   `Environment.ProcessorCount`), GPU (omit for CPU-only), RAM, OS, .NET SDK, build config; then "Numbers are
   machine-specific — re-run on your own hardware before drawing comparative conclusions."
3. One `## <Title> — \`<TestMethodName>\`` section per benchmark, in order: `**File:**` `Facts/<File>.cs`; methods compared,
   **fully qualified with parameter types** (`DiGi.Geometry.Planar.Query.Average(IEnumerable<Point2D>)`); description;
   editable knobs (`const`/`static readonly` sweep fields); result tables (numeric columns right-aligned `|---:|`, Release
   primary, Debug labelled *for reference*, a speed-up column, time **per call**:
   `repeats = Math.Max(1, TARGET_OPS / count)`); short analysis bullets.
4. `## Adding a new benchmark` with the checklist below.

Conventions: assert cross-implementation agreement before timing; seed RNGs with documented constants; note noise/GC at
small scales; overwrite tables on re-run (no historical duplicates).

Checklist: `[Fact]` under `Facts/` · sweep size as `const`/`static readonly` · warm-up · agreement asserts · Release,
filtered to the one fact, three runs, machine spec captured · page section updated · committed and pushed to the wiki's
`master`, linked from `Home.md`.
