# AI Guidelines: Geometry & Solar Conventions (`DiGi.Geometry`, `DiGi.Solar`)

Traps of the geometry stack the signatures do not show; each produced a **plausible wrong answer rather than an error**.
Geometry primitives keep their interface-contract instance methods (`Coding - General.md` §2).

## Checklist
Read this first; open a section only when its line applies to the change.
- Sun/light direction negated before dotting with a normal?
- Zero-length guard on `Length`, not `Unit == null` or `Angle`?
- Orientation facts include an asymmetric face?
- Closure as "closes at some tolerance ≤ T"?
- Sub-tolerance corners removed before `Triangulate`?
- Grouping hash keys rounded, ordinates mixed sequentially, buckets histogrammed?
- Point sweeps through `PolygonalFace2DPointRelationSolver`, coordinates flattened in hot loops?

## 1. Vectors and directions
- **`DiGi.Solar.Query.SunDirection` is a propagation vector — it points AWAY from the sun:**
  `-(cos el·sin az, cos el·cos az, sin el)`, so `z = -sin(elevation)` points down while the sun is up. Incidence is
  `cos θ = -(s.Unit · n.Unit)`. Implemented as `s · n` (as DiGi.Solar#1 specified), every lit surface scored zero and every
  averted one lit up, while a fact asserting only `Length == 1` passed. Pin it with a fact fed **real** `SunDirection`
  output (`IrradianceResult_SunDirectionConvention`, `DiGi.Solar.xUnit`). Frame: X = East, Y = North, Z = Up (a south
  wall's normal is `(0, -1, 0)`).
- **`Vector3D.Unit` never returns `null`** (despite `Vector3D?` and its docs): a zero vector comes back degenerate, so
  `if (v.Unit == null)` never fires — a `(0,0,0)` normal produced a full-sky `Create.IrradianceResult`. Guard first:
  `if (v == null || double.IsNaN(v.Length) || v.Length <= 0) return null;`.
- **`Vector3D.Angle` returns `0`, not `NaN`, for a zero vector** — no degeneracy test either.
- **Never compute a cosine through `Angle`:** the `acos` → `cos` round trip is ill-conditioned at the ends (a vertical
  surface gives `6.12e-17`, not `0`). Use the dot product or the ordinate (`v.Z`).

## 2. Orientation and normalisation
- **Test orientation with asymmetric fixtures — a rectangle cannot fail.** Until DiGi.Geometry#6 `Planar.Flip` turned the
  plane but not `geometry2D`, mirroring every flipped face (a wall dropped a storey, a floor moved 700 km); every box
  fixture passed because `Create.Plane(points)` centres the origin and a rectangle is its own mirror image. Use a
  trapezoid, gable, L-shape or real swept wall, and assert invariants independent of the code (rings keep their 3D points,
  shared edges run opposite, signed volume positive): `DiGi.Geometry.xUnit/Facts/Flip.cs`, `BuildingModelGetExternalShell_*`
  on `DiGi.Test/files/BuildingModel_Envelope.json`.
- **A face normal is `Plane.Normal`; ring winding is separate** and runs against it after a turn — a consumer deriving
  triangle winding (glTF) passes `Orientation.CounterClockwise, Orientation.Clockwise` explicitly.

## 3. Closure and tolerance
- **`Spatial.Query.IsClosed(polyhedron, tolerance)` is not monotonic in `tolerance`:** welding merges vertices, edges
  collapse and the even-count parity breaks — stored `BuildingModel`s close at `1e-6` and report open at `0.05`.
- So "enclosed at T" means "closes at some tolerance ≤ T": walk an ascending ladder and take the first that closes (also the
  diagnostic); judge manifoldness (`IsClosed(manifold: true, …)`) at that tolerance. References:
  `DiGi.Analytical.Building/Query/IsEnclosed.cs`, `BuildingModelValidationResult` (`DiGi.GIS.Analytical`).

## 4. Triangulation
- **`Planar.Query.Triangulate(Polygon?, double)` recursed forever on corners closer than the tolerance**
  (`PrecisionModel(1 / tolerance)` collapses them, the clip returns the polygon unchanged). A `StackOverflowException`
  cannot be caught — the process dies with `0xC00000FD`, no log, a web host just drops the connection. A recursion guard
  now drops a no-progress piece (small area loss, not a fix): **remove consecutive corners within the tolerance first** —
  copy the `Clean` local function of `Spatial.Query.Difference(Mesh3D, …)`. Trigger: cutting building outlines out of one
  terrain triangle at PL-1992 magnitudes; fixture `Triangulate_SubToleranceCorners`.
- **Check NetTopologySuite before writing a geometry algorithm** (already referenced; its `NetTopologySuite.xml` lists every
  type). `NetTopologySuite.Triangulate.Polygon.PolygonTriangulator` (ear clipping, holes joined by `PolygonHoleJoiner`) is
  the general polygon triangulator, `ConstrainedDelaunayTriangulator` when triangle quality matters.
  `ConformingDelaunayTriangulationBuilder` is **not**: it inserts its own Steiner points and throws
  `ConstraintEnforcementException` on narrow slivers.

## 5. Spatial hash keys
Both traps keep answers correct but slow (a collision or split key only demotes work), so they pass review and tests.
- **Round the cell index, do not floor it, when the key must group identical points:** `Floor(v * invTolerance)` puts a
  boundary on every tolerance multiple, exactly where clean geometry sits (`z = 0` vs `-1e-16` land in different cells).
  A grid for **neighbour probing** keeps `Floor` and probes the surrounding cells.
- **Mix ordinates one at a time, each exclusive-or followed by a multiply.** Over 1 500 edge keys of a 500-gon extrusion,
  `(x*A) ^ (y*B) ^ (z*C)` collided 108 times, `((x ^ y) * K1) ^ z` 694 times (symmetric xor, swapped ordinates), FNV-1a +
  murmur avalanche 0:
  ```csharp
  ulong hash = 0xCBF29CE484222325UL;
  hash = (hash ^ (ulong)(long)Math.Round(x * invTolerance)) * 0x100000001B3UL;   // repeat for y, z
  hash ^= hash >> 33; hash *= 0xFF51AFD7ED558CCDUL; hash ^= hash >> 33;
  ```
- Detect either by histogramming bucket sizes against an exact tuple key (`Dictionary<(long, long, long), …>`).

## 6. Hot loops
- **Many points against one polygon: `Planar.Classes.PolygonalFace2DPointRelationSolver`**, one per polygon:
  `Input = point; Solve(); Output == PointRelation.Inside`. Warsaw's 4 260-point outline against 155 000 points: 25 ms vs
  1 655 ms for `PolygonalFace2D.Inside`. Same semantics (boundary within tolerance is `On`, holes excluded); not
  thread-safe (scratch buffer) — one per thread.
- **Copy coordinates out of `List<Point2D>` before a hot loop:** `Point2D.X` is `values[0]` on a heap `double[]` (~14 ns per
  edge test vs ~2.4 ns over a flat `double[]`).
- **Write parity facts before trusting "same semantics"** — they exposed a `PolygonalFace2D.InRange` bug (the outline's `On`
  dropped when the face had holes). Measuring: `Coding - Performance.md`.

## 7. Checklist → the `## Checklist` at the top of this file
