---
name: digi-verify
description: "Use after changing C# in a DiGi repository, before reporting the work done or committing - rule check on the changed files, build the changed library, run the facts; prints failures only."
---

# Verify a C# change

Run from `DiGi.Maintenance/Scripts` (workspace-relative), host shell. Each script prints only what needs attention;
do not read build or test logs, and do not re-read the changed files to check rules a script checks.

1. **Rules no analyzer enforces** (one public method per `Query`/`Modify`/`Create` file, no private methods there,
   `Get` prefix in `Query`, `using Xunit;`, `TODO` without `[Marker]`, machine paths in markdown):
   ```powershell
   PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineRules.ps1" -Repo "<Repo>" -Changed
   ```
   A reported line is a candidate: fix it, or state why it is a deliberate exception.
2. **Build the changed library, then run its facts** - the test project reaches the library by `HintPath`, so
   `dotnet test` alone runs the stale binary. Zero warnings is the bar (`TreatWarningsAsErrors`).
   ```powershell
   PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\TestSummary.ps1" -Library "<path>\<Library>.csproj" -Project "<path>\<Library>.xUnit"
   ```
   Add `-Filter "FullyQualifiedName~<Fact>"` while iterating; run unfiltered before finishing.
3. **A public surface changed?** Rebuild every consumer in order: `.\BuildAll.ps1 -Configuration Debug -Summary`
   (`-Solution "<Repo>"` for one). A host gained a package or a reference: `.\CheckHostDependencies.ps1 -Unit "<Host>"`.

Report: the three results in one line each. What the scripts do not check and stays yours: explicit types and
naming by type, XML documentation on every new public member, a `SerializationCheck` fact plus a direct
copy-constructor assertion for a serializable type (`Coding - General.md`, `Coding - Serialization.md`,
`XML Documentation.md` - read the Checklist of the one that applies).
