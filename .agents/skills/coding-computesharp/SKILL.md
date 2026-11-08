---
name: coding-computesharp
description: "Use when writing or changing a ComputeSharp IComputeShader (DiGi.ComputeSharp) - constant buffer layout (12-byte header, free slot at offset 12, declaration order is layout order), the NVIDIA defect where an odd root constant count with an odd resource count silently corrupts doubles (reorder or pad, never drop a resource), the layout guard and parity facts, GPU fact conventions, probing a suspected driver defect."
---

# AI Guidelines: ComputeSharp Compute Shaders

Writing or changing an `IComputeShader` struct (ComputeSharp 3.2, D3D12; all live in `DiGi.ComputeSharp`). A shader that
runs, returns the right shape and raises no error can still compute garbage.

> **Never an odd number of 32-bit root constants AND an odd number of bound resources. Prefer an even root constant count
> (`ConstantBufferSize` a multiple of 8) for every new shader.**

## 1. Constant buffer layout
Every value field (not a `ReadOnlyBuffer`/`ReadWriteBuffer`/texture) goes into one constant buffer bound as 32-bit root
constants (`Num32BitValues = ConstantBufferSize / 4`); each buffer is a *resource* (one descriptor range).
- Bytes 0–11 hold the dispatch header `__x`, `__y`, `__z`. **Offset 12 is a free 4-byte slot** — a 4-byte field (`int`,
  `float`, `Bool`) declared first lands there at no cost.
- A `double` is 8-byte aligned (the first lands at 16); a struct field (`Coordinate3`, `Line2`, `Triangle3`) starts on the
  next 16-byte row.
- **Declaration order is layout order** (for a primary-constructor struct, the order of the captured parameters) — moving a
  field changes `ConstantBufferSize`.
- DXC records the `cbuffer` size equal to `ConstantBufferSize` (not padded to 16); ComputeSharp builds the root signature at
  run time (none embedded in the DXIL).

**Read the layout, do not compute it:** build with
`-p:EmitCompilerGeneratedFiles=true -p:CompilerGeneratedFilesOutputPath=<dir>` and read `ConstantBufferSize =>` and the
`[FieldOffset]`s in the generated `*.g.cs`, or read the static descriptor members (no GPU needed):
```csharp
public static int ConstantBufferSize<T>() where T : struct, IComputeShader, IComputeShaderDescriptor<T>
{
    return T.ConstantBufferSize; // also T.ResourceDescriptorRanges, T.HlslSource, T.HlslBytecode
}
```

## 2. The odd/odd driver defect (DiGi.ComputeSharp#3)
NVIDIA GeForce RTX 5090, driver 617.14: a shader whose root constant count **and** resource count (SRV + UAV) are both odd
returns **wrong double-precision results for every thread** — no exception, no device removal, also with the D3D12 debug
layer. Measured with a ~40-line shader (cross product → Newton `Sqrt` → normalize → dot), the extra field never read:

| Root constants | Resources | RTX 5090 | WARP |
|---|---|---|---|
| 14, 16 | 1–6 | correct | correct (14, 16 with 3) |
| 10, 12, 18 | 3 | correct | — |
| 15, 17 | 2, 4, 6 | correct | correct (15 with 2) |
| 33 | 2 | correct | — |
| 15, 17 | 1, 3, 5 | **wrong** | correct (15 with 3) |
| 11, 13 | 3 | **wrong** | — |

- The DXIL of a failing and a working shader differs only in the cbuffer size (56 → 60 B) and WARP computes both: the fault
  is the driver's DXIL-to-native compile.
- Inputs arrive intact (echoed correctly); the arithmetic returns a denormal or `0` (`-1.5E-323` instead of `-0.9995…`).
- A trivial body (summing constants) was correct at 15/3 — a smoke shader proves nothing; only the rule does.

**Fix by reordering or padding, never by dropping a resource:** put a 4-byte field first (offset 12) or add an unused `int`.
`Triangle3ExternalShadingRowOffsetComputeShader` declares `int rowOffset` first — 56 B / 14 constants like
`Triangle3ExternalShadingComputeShader`; appended it was 60 B / 15 with 3 resources and returned zero hits where the CPU
found five. This order is **permanent** — no `TODO [Marker]` (`Coding - General.md` §1.12).

## 3. A layout change needs a guard and a parity fact
- **Guard:** `DiGi.Test/DiGi.ComputeSharp.xUnit/Facts/ComputeShader_ConstantBufferLayout.cs` enumerates every
  `IComputeShader`, fails on odd/odd and pins each `ConstantBufferSize` and resource count — any new, added, removed or moved
  field fails it until the table is updated deliberately. No GPU needed.
- **Parity:** a new or re-laid-out shader is compared **cell for cell** with a proven shader or the CPU reference (two
  directions, two tolerances); a shader compared only with itself cannot show a layout defect.
- **Show the guard failing** (`Coding - Automatic Tests.md` §4): on #3, moving `rowOffset` last failed the guard and the GPU
  parity fact; padding to 64 B failed only the pinned size.

## 4. GPU fact conventions
- Gate on the device: `if (!Query.IsComputeSharpSupported(testOutputHelper)) { return; }` (no FP64 GPU → skip).
- Catch `UnsupportedDoubleOperationException` by type name and write a warning instead of failing.
- **Assert a non-vacuous scenario** — a mix of hits and misses (`nonNaN > 0 && nonNaN < count`); all-NaN equals all-NaN,
  exactly what #3 produces.
- Keep layout facts GPU-free (§1's static members).

## 5. Probing a suspected GPU defect
- **WARP on a reduced shader** (`GraphicsDevice.QueryDevices(info => !info.IsHardwareAccelerated).First()`) splits a driver
  fault from a DXC/ComputeSharp one. Reduce first: WARP took ~20 minutes per dispatch of the ~90 k-character intersection
  routine and is **not trustworthy there** (0 hits where CPU and RTX 5090 found 5, unexplained); on the reduced repro it
  matched the CPU everywhere.
- **Diff the DXIL:** write `T.HlslBytecode` to disk, `dxc.exe -dumpbin` (Windows SDK) both variants — identical
  instructions + different results = driver.
- **Echo before bisecting:** write constants and inputs back from the failing thread; if right, bisect the body stage by
  stage.
- **Debug layer:** `ComputeSharpEnableDebugOutput=true` (MSBuild); messages go to the Windows debug output, not the console.
- Mutation tests: a file restored with `cp`/`mv` keeps an old mtime and the mutant stays live — `Coding - Performance.md` §2.
