---
name: coding-general
description: "Use when writing or editing any C# - no var, type-prefixed naming, parameter line breaks, CancellationToken last, Query/Modify/Create/Convert, cheap constructors, enums, constants, files vs user files, logging, cancellation filter, TODO [Marker], binding traps."
---

# AI Guidelines: C# General Coding Standards & Architecture

Applies to every C# change. Task-specific detail lives in its own file: serialization (`Coding - Serialization.md`),
NuGet / `HintPath` host dependencies and build errors (`Coding - Host Dependencies.md`), project and `.editorconfig`
setup (`Coding - Project Setup.md`), optimizing and benchmarks (`Coding - Performance.md`). Section and rule numbers are
stable — moved items keep a pointer. Incidents and measurements behind the rules:
[Evidence](evidence.md) (read only when a rule is disputed or being changed).

## Checklist
Read this first; open a section only when its line applies to the change.
- English only; no `var`; target-typed `new()`; collection expressions `[]`; block-scoped namespaces; zero warnings (§1.1–1.5).
- Names start with the type name in camelCase + `_` qualifier; acronym types lowercase the first letter only; collections = pluralized element type (§1.3).
- ≤ 7 parameters on one line however long, ≥ 8 one per line (`DIGI0001`) (§1.6). Async names end with `Async` (§1.7).
- `CancellationToken` last; new optional parameters before it; name every argument after a skipped default (§1.8).
- Simplify member access, then rebuild; namespaces bind innermost-outwards; call a same-named extension fully qualified (§1.9).
- Temporary code: `TODO [MarkerName]:` + removal condition at every site; never on permanent code (§1.12).
- A fix to generated code goes into the generator (§1.13). Scripted edits: `Maintenance - Scripts.md` §6 (§1.14).
- A check that skips absent input fails open — decide what absence means (§1.15). Options defaults are the contract (§1.16).
- Extension receivers box, never convert — one overload per primitive; probe binding claims, don't reason (§1.17).
- Reflection by name is a contract on the hierarchy — document both ends, probe `GetMethod` (§1.18).
- `ToString()` is not a key — identity strings render through `InvariantCulture` (§1.19).
- No caching in an optimization unless allowed (§1.20). Log via `Serilog.Modify.Log` templates (§1.21).
- Rethrow only a requested cancellation, before any general catch (§1.22).
- Architecture: data in `/Classes`, behavior in `Query`/`Modify`/`Create`/`Convert` extensions; no service classes; category folders add no namespace (§2).
- Interface-contract members stay instance methods; constructors only assign and clone, work goes in a nullable `Create` factory (§2).
- One public method per file in `Query`/`Modify`/`Create`; no private methods there; `Convert` first for conversions; `Query` names property-like; `IResult` types end in `Result` (§2).
- Enums start with `Undefined`; constants in `X.Constants` categories; tolerances from `DiGi.Core.Constants.Tolerance` (§2).
- Secrets and generated output in git-ignored `user files/`, committed assets in `files/`; never print a conf; edit a build-copied asset at its source (§3).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
