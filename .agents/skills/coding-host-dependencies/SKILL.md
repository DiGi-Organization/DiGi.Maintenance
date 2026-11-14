---
name: coding-host-dependencies
description: "Use when adding a NuGet package, when a host throws FileNotFoundException or returns a partial result, or on CS0012/CS0246 walls - HintPath drops transitive packages, stale deps.json, CheckHostDependencies.ps1, rebuilding consumers."
---

# AI Guidelines: Host Dependencies — `HintPath` Opacity

DiGi projects reference each other with `<Reference><HintPath>..\..\X\bin\X.dll</HintPath>`, never `<ProjectReference>`.
A raw assembly reference is **opaque to NuGet and to MSBuild's build graph**, and DiGi libraries do not copy their own
packages into `bin`. Everything below follows from that. (Formerly `Coding - General.md` §4.) Build-order consequence for
tests — `dotnet test` never rebuilds the library under test: `Coding - Automatic Tests.md` §4.

## Checklist
Read this first; open a section only when its line applies to the change (§6 maps a build error to its fix).
- Before adding a package: check the packages already referenced, the consuming project's TFM folder and the runtime/native variant at the version in use (§1).
- A package a `HintPath`-referenced library needs is re-declared on every deployed host at the exact same version, with a comment naming the owner — unless the target framework provides it (`NU1510`); audit the whole closure (§2).
- A run that completes but delivers less than it should: check the host's output for missing assemblies first — the symptom is a partial result, not an error; green tests prove nothing (§3).
- WebAPI extensions are one probing set with their host; shared dependencies are declared once on `DiGi.WebAPI.WindowsService` (§4).
- After changing a consumed library's assembly references, rebuild the executable with `--no-incremental` — a stale `deps.json` gives the same `FileNotFoundException` with the dll present (§5).
- `CS0012` on an overloaded call: fix the `.csproj`; a `CS0246`/`CS0234` wall that vanishes under `-m:1` is a build race; never a solution-wide `--no-incremental` (§6).
- After changing a public surface, rebuild every consumer: `BuildAll.ps1 -Summary` (§7).
- After building a host: `CheckHostDependencies.ps1` (it does not check `deps.json` membership) (§8).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
