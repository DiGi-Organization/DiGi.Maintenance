---
name: coding-grasshopper
description: "Use when writing or changing a Grasshopper/Rhino plug-in component (DiGi.*.Rhino) - VariableParameterComponent anatomy, a fixed ComponentGuid that never changes, name-based Params.IndexOfInputParam lookups (a typo silently returns -1), Goo and Param pairs per file, Inspect methods, RhinoInfo, and the .csproj (Grasshopper IncludeAssets compile;build, OutputPath ..\\bin, .gha copy)."
---

# AI Guidelines: Grasshopper / Rhino Plug-ins (`DiGi.*.Rhino`)

Conventions of the twelve `DiGi.*.Rhino` projects (`DiGi.Rhino`, `DiGi.Analytical.Rhino`, `DiGi.GIS.Rhino`,
`DiGi.Solar.Rhino`, …). Shared base types live in `DiGi.Rhino/DiGi.Rhino.Core`. Reference component:
`DiGi.Rhino.Core/Classes/Component/SetValue.cs`. (`DiGi.Revit.UI` has one `ExternalApplication` and no pattern yet; there
is no Dynamo repository.)

## 1. Component anatomy
- Derive from `VariableParameterComponent` (or `EnumComponent<T>` for an enum picker) — 65 of 73 components.
- Constructor: `base("Area.Action", "Area.Action", "description", "DiGi", "DiGi.Area")` — name and nickname
  `Area.Action`, category `DiGi`, subcategory `DiGi.<Area>`.
- `public override Guid ComponentGuid => new("…");` — a fresh GUID per component, **never changed after release**: a
  changed GUID orphans the component in every saved `.gh` file. `Exposure => GH_Exposure.primary`.
- `Inputs`/`Outputs` return `Param[]` built as
  `new Param(new GooXParam() { Name = "X", NickName = "X", Description = "…", Access = GH_ParamAccess.item }, ParameterVisibility.Binding)`
  (`ParameterVisibility.Voluntary` for optional ones).
- `SolveInstance` looks every parameter up **by name**, then validates:
  ```csharp
  int index = Params.IndexOfInputParam("ParametrizedObject");
  IParametrizedObject? parametrizedObject = null;
  if (index == -1 || !dataAccess.GetData(index, ref parametrizedObject) || parametrizedObject == null)
  {
      AddRuntimeMessage(GH_RuntimeMessageLevel.Error, "Invalid data");
      return;
  }
  ```
  A typo in the name string returns `-1` and the component silently produces nothing — keep the strings identical to the
  `Name` in `Inputs`/`Outputs`. Outputs: `index = Params.IndexOfOutputParam("X"); if (index != -1) dataAccess.SetData(index, …);`.
- Clone a DiGi input before modifying it (`DiGi.Core.Query.Clone(x)`) — Grasshopper shares instances between components.

## 2. Goo and parameters
- One file per wrapped type holds the pair `GooX : GooSerializableObject<T>` (or `GooBakeAwareSerializableObject<T>` with
  `Geometries` for baking) **and** `GooXParam : GooPersistentParam<…>` / `GooSerializablePersistentParam<…>` (or
  `GooBakeAwareSerializableParam<GooX, T>`) — the sanctioned exception to one type per file.
- Each Goo and each Param carries its own fixed GUID; `Duplicate()` returns `new GooX(Value)`.
- Files under `Classes/Goo/` and `Classes/Component/` keep the `[Project].Classes` namespace (`Coding - General.md` §2).

## 3. Inspect
Property inspection is `public static partial class Inspect` in `/Inspect/<Type>.cs`, one-parameter extension methods
tagged `[Inspect("Name", "Nick", "Description")]` returning Goo-wrapped values or `null`. `InspectManager` discovers them
by reflection; a method with more than one parameter is skipped silently.

## 4. Project file
- Each assembly has a `RhinoInfo : GH_AssemblyInfo`.
- `PackageReference Include="Grasshopper" … IncludeAssets="compile;build"` — without it Grasshopper/RhinoCommon dlls are
  copied into `bin` and clash with Rhino's own.
- DiGi libraries by `HintPath` (`..\..\DiGi.X\bin\DiGi.X.dll`, `Coding - Host Dependencies.md`); `OutputPath ..\bin\`
  with `AppendTargetFrameworkToOutputPath=false`; a post-build step copies the `.dll` to `.gha`.
- Target frameworks are split (`net8.0-windows` × 7, `net10.0-windows` × 5); match the sibling you extend.
