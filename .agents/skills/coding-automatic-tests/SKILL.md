---
name: coding-automatic-tests
description: "Use when writing xUnit facts - Facts layout, fixtures in DiGi.Test/files, build the library before dotnet test, Short/Medium/Long attributes, reproduce-first, guards that can fail, database facts on *_Test.conf."
---

# AI Guidelines: Automatic Tests (xUnit)

## Checklist
Read this first; open a section only when its line applies to the change.
- Production coding rules apply unchanged (§1).
- `[ProjectName].xUnit` under `DiGi.Test/`, `public partial class Facts` in `/Facts/`, no `using Xunit;`, a `<summary>` on every fact (§2).
- Fixtures in `DiGi.Test/files/` via `Core.xUnit.Query.FilePath(...)`; everything written goes to `assembly.ReportsDirectory()` (§3).
- Build the changed library before `dotnet test` (`HintPath`); an identical result means a stale binary — one call: `DiGi.Maintenance/Scripts/TestSummary.ps1 -Library <csproj> -Project <xUnit>` (§4).
- Serializable types: `SerializationCheck` plus a direct copy-constructor assertion (`Coding - Serialization.md` §9) (§4).
- Tolerance facts just inside and just outside (§4, example §5).
- `[Fact]` ≤ 2 s, `[MediumFact]` 2–30 s or any live service (`[MediumSkippableFact]` in PostgreSQL/WebAPI projects), `[LongFact]` > 30 s; classify by measurement; never `using DiGi.Core.xUnit;` (§4).
- Keys and identities asserted a second time under `pl-PL` (§4).
- A defect fix opens with a fact failing on the unmodified code; a guard is shown to fail; prefer a differential assertion to a plausibility range (§4).
- Database facts: own `*_Test.conf`, refuse the host's database, snapshot and restore, create their own preconditions (§4).
- Phantom Test Explorer entries after a rename: delete `TestStore` (§4).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
