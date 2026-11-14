---
name: coding-geometry
description: "Use when orienting, closing, triangulating, hashing or sweeping DiGi.Geometry/DiGi.Solar geometry - SunDirection points away from the sun, Vector3D.Unit never null, IsClosed not monotonic, sub-tolerance corners, hash keys."
---

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

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
