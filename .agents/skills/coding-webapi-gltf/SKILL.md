---
name: coding-webapi-gltf
description: "Use when building a Web API on the DiGi.GLTF 3D framework - IGLTFNodeConverter in WORLD coordinates, batched payloads, gltf-viewer-core.js edited only in its owner, what the payload does not carry."
---

# Coding — WebAPI glTF

ASP.NET Core Web APIs on the `DiGi.GLTF` 3D framework (engine `DiGi.GLTF.WebAPI`, consumer `DiGi.GIS.WebAPI.UI`). Scaffold
from `DiGi.WebAPI.GLTF.Template` (`Coding - Project Setup.md` §1).

## Checklist
Read this first; open a section only when its line applies to the change.
- Solution folder under the workspace root; references `DiGi.Core`, `DiGi.Geometry`, `DiGi.GLTF`, `NetTopologySuite`, `SharpGLTF.Toolkit`?
- `DiGi.GLTF.Modify.Register(typeof(Program).Assembly)`; response compression for `model/gltf-binary`?
- New types via `IGLTFNodeConverter` in the consumer, emitting WORLD coordinates?
- `ToSystem_Bytes(scene, batched: true)`?
- `gltf-viewer-core.js` edited only in `DiGi.GLTF.WebAPI`, synced and committed in both repositories?
- Marquee selection live in both directions; nothing reads payload normals; `shadowSide` pinned when `side` changes?

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
