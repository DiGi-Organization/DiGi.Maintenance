---
name: coding-webapi-gltf
description: "Use when building or extending a Web API on the DiGi.GLTF 3D framework - the pipeline, onboarding a consumer, IGLTFNodeConverter in WORLD coordinates, batched payloads, gltf-viewer-core.js edited only in DiGi.GLTF.WebAPI and committed in both repositories, live marquee selection, and what the payload does not carry (no normals, winding, shadow contract)."
---

# Coding — WebAPI glTF

ASP.NET Core Web APIs on the `DiGi.GLTF` 3D framework (engine `DiGi.GLTF.WebAPI`, consumer `DiGi.GIS.WebAPI.UI`). Scaffold
from `DiGi.WebAPI.GLTF.Template` (`Coding - Project Setup.md` §1).

## 1. Pipeline
1. **Input (consumer):** `ISerializableObject`s (e.g. `Building2D`).
2. **Conversion (consumer):** `IGLTFNodeConverter`s turn them into `GLTFNode`s in **WORLD coordinates**; registered at
   start-up, dispatched by `DiGi.GLTF`.
3. **Scene (engine):** `DiGi.GLTF.Create.GLTFScene` merges nodes, shifts geometry to a **local origin** (the removed offset
   kept in `GLTFScene.ReferencePoint` — mandatory: 32-bit WebGL floats jitter at GIS magnitudes), adds light and camera.
4. **View (engine JS):** `gltf-viewer-core.js` fetches binary `.glb`, renders, broadcasts selection.
Stream `.glb` (`model/gltf-binary`); never inline base64 into HTML.

## 2. New consuming project
1. Solution folder directly under the workspace root (2-level `HintPath`s).
2. `Microsoft.NET.Sdk.Web`, `net10.0`, `Nullable` enable, `LangVersion latest`, `CopyLocalLockFileAssemblies` true (host).
3. `NetTopologySuite`, `SharpGLTF.Toolkit`, `HintPath` to `DiGi.Core`, `DiGi.Geometry`, `DiGi.GLTF`.
4. Start-up:
   ```csharp
   WebApplicationBuilder builder = WebApplication.CreateBuilder(args);
   builder.Services.AddControllers();
   builder.Services.AddResponseCompression(options =>
   {
       options.EnableForHttps = true;
       options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(["model/gltf-binary"]);
   });

   DiGi.GLTF.Modify.Register(typeof(Program).Assembly); // scan for IGLTFNodeConverter implementations

   WebApplication app = builder.Build();
   app.UseResponseCompression();
   app.MapControllers();
   app.Run();
   ```
5. Endpoint:
   ```csharp
   [HttpPost("glb/fromobjects")]
   public IActionResult GLBFromObjects([FromBody] JsonArray? jsonArray, [FromQuery(Name = "name")] string? name = null)
   {
       if (jsonArray is null) return BadRequest();
       List<ISerializableObject>? serializableObjects = DiGi.Core.Create.SerializableObjects<ISerializableObject>(jsonArray);
       if (serializableObjects is null || serializableObjects.Count == 0) return NoContent();

       GLTFScene? gLTFScene = DiGi.GLTF.Create.GLTFScene(serializableObjects, name);
       if (gLTFScene is null) return NoContent();

       byte[]? bytes = DiGi.GLTF.Convert.ToSystem_Bytes(gLTFScene, true); // batched: true
       if (bytes is null || bytes.Length == 0) return NoContent();

       return File(bytes, "model/gltf-binary", $"{gLTFScene.Name ?? "scene"}.glb");
   }
   ```
6. `gltf-viewer-core.js` copied into `wwwroot/js/` at build time (§4).

## 3. Adding a 3D object type — a converter in the consuming project
Never modify `DiGi.GLTF` or the core controllers.
```csharp
public class MyDomainObjectGLTFNodeConverter : GLTFNodeConverter<MyDomainObject>
{
    public override List<GLTFNode>? Convert(MyDomainObject serializableObject, double tolerance)
    {
        DiGi.Geometry.Spatial.Interfaces.IGeometry3D? geometry3D = serializableObject.Geometry; // WORLD coordinates, never pre-shifted
        if (geometry3D is null) return null;

        DiGi.Core.Classes.Color color = new(byte.MaxValue, 222, 184, 135);
        string? reference = DiGi.Core.Create.UniqueReference(serializableObject)?.ToString();
        string? properties = DiGi.Core.Convert.ToSystem_String(serializableObject);

        GLTFNode? gLTFNode = DiGi.GLTF.Create.GLTFNode(geometry3D, serializableObject.GetType().Name, reference, color, 1.0, properties, tolerance);
        return gLTFNode is null ? null : [gLTFNode];
    }
}
```
- A 2D footprint is extruded: `Plane plane = DiGi.Geometry.Spatial.Create.Plane(0); PolygonalFace3D? face3D = plane.Convert(face2D);`
  then `new PolygonalFaceExtrusion(face3D, new Vector3D(0, 0, storeys * 3.0))` (storeys at least 1), referenced by
  `Building2D.Reference`.
- **Converters emit WORLD coordinates** — the scene shifts the origin; pre-shifting double-shifts.
- To match an interface, implement `IGLTFNodeConverter` directly: `CanConvert(ISerializableObject x) => x is IComponent`.

## 4. Performance and the engine script
- **Batching is mandatory for large sets:** `ToSystem_Bytes(scene, batched: true)` merges geometry into one draw unit per
  alpha mode with vertex `COLOR_0`. Every vertex carries its object id in `_OBJECTID`; contiguous ranges sit in the scene
  extras `objectMap`, so selection re-tints a vertex range in O(range).
- Parse `.glb` zero-copy; build BVH/edges after the first frame (`setTimeout(..., 0)`); `frustumCulled = true` on meshes.
- **`gltf-viewer-core.js` is edited only in its owner `DiGi.GLTF.WebAPI/DiGi.GLTF.WebAPI/wwwroot/js/`** — the consumer copy is
  a build artifact (`Coding - General.md` §3; `DiGi.GIS.WebAPI.UI#58` was lost that way until `#57`):
  ```xml
  <Target Name="CopyGLTFViewerCore" BeforeTargets="Build">
    <Copy SourceFiles="$(ProjectDir)..\..\DiGi.GLTF.WebAPI\DiGi.GLTF.WebAPI\wwwroot\js\gltf-viewer-core.js" DestinationFolder="$(ProjectDir)wwwroot\js\" SkipUnchangedFiles="true" />
  </Target>
  ```
  The copy is git-tracked: commit an engine change in both repositories. A build failing on a locked `bin\*.exe` never
  reaches the target — confirm the two files hash-identical (CR stripped) before committing. Opt out of Razor import-map
  rewriting with `<!script type="importmap">`; the UI serves the file with a `FileVersionProvider` fingerprint (`?v=…`) — an
  unchanged fingerprint after an edit means a stale served file.

## 5. What the batched payload does not carry (DiGi.GIS.WebAPI.UI#43)
- **No `NORMAL` attribute.** `GLTFLoader` sets `material.flatShading = true`, so lighting looks right, but any shader reading
  the vertex normal gets zeros: three.js's shadow receiver normalises it for `normalBias`, `normalize(vec3(0))` is NaN, every
  fragment fails the shadow test — lit everywhere. A populated depth map proves nothing about receivers.
- **Consistent winding** (DiGi.GLTF#1): terrain is up-facing (+Z, `Mesh3D.Difference` normalises the cut); building envelopes
  (`BuildingModel.GetExternalShell(Side.External, ...)`) are outward-consistent (reference scene: 18 077 shared edges
  opposite, 6 same-direction, all on two open envelopes — storey-split T-junctions, DiGi.Analytical#3). `FrontSide` and
  `DoubleSide` render it identically (79 of 469 260 pixels). three.js renders the depth map from the *opposite* side when
  `material.shadowSide` is null — pin `shadowSide` when changing `side`. Terrain slivers < 0.001 m² carry random signs —
  filter by area before counting.
- **Shade contract:** `renderer.shadowMap.autoUpdate = false`, shadow camera anchored to the scene centre, depth map
  rendered on change only — any mutation changing what casts shade (a caster type, a visibility filter, clipping) calls
  `requestShadowUpdate()`. Shadow-bias normals are computed once from the winding (`prepareShadowNormals`).
- **Box selection highlights live in both directions** (window left-to-right, crossing right-to-left, as in Revit/Rhino):
  `updateMarqueePreview` computes per-object screen bounds once per drag (`computeScreenBounds`), tests rectangles on each
  `pointermove`, re-tints only the difference (`applyHighlight(id, SELECTED_TINT)`) and dispatches `gltf-selectionchanged`
  only on release. A view with its own selection code must match it.

## 6. Checklist
- [ ] Solution folder under the workspace root; references `DiGi.Core`, `DiGi.Geometry`, `DiGi.GLTF`, `NetTopologySuite`, `SharpGLTF.Toolkit`?
- [ ] `DiGi.GLTF.Modify.Register(typeof(Program).Assembly)`; response compression for `model/gltf-binary`?
- [ ] New types via `IGLTFNodeConverter` in the consumer, emitting WORLD coordinates?
- [ ] `ToSystem_Bytes(scene, batched: true)`?
- [ ] `gltf-viewer-core.js` edited only in `DiGi.GLTF.WebAPI`, synced and committed in both repositories?
- [ ] Marquee selection live in both directions; nothing reads payload normals; `shadowSide` pinned when `side` changes?
