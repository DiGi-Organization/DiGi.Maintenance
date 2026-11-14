# Evidence: Coding - General.md

Incidents, measurements and history behind the rules of [Coding - General.md](../Coding%20-%20General.md), keyed by its
section numbers. Read only when a rule is disputed or being changed; the rule itself lives in the guideline.

## §1.8 `CancellationToken` last, named arguments after a skipped default
DiGi.PostgreSQL `7cd4937` inserted `int maxGroups` before `commandTimeout`, and every positional caller's timeout became
the group cap (`cd88e7a`, #16).

## §1.9 Same-named extension methods bind by `using`
`column.UniqueId()` returns the content hash wherever `DiGi.Core.IO` is not imported — a projection built from hashes
matched no column, and a regressor fitted a full-looking 174-column table of zeros.

## §1.12 Temporary code markers
`TerrainCuttingMaxBuildingCount = 250` said "temporary" in prose only and outlived its cause; correct form:
`TODO [TerrainCuttingCap]: remove once DiGi-Organization/DiGi.Geometry#2 ships the triangulator fix.`

## §1.13 Hand-fixes to generated code
One regeneration of `DiGi.GIS.ML/OrtoBuildingDetectionModel.*.cs` reverted five at once: explicit `Plotly.NET`
`LinearAxis.init` type arguments, `<paramref>` instead of a `<param>` in prose, initialisers for non-nullable members, a
deployment-aware model path resolver, a qualified `Query.UniqueId` (§1.9).

## §1.15 A check that skips absent input fails open
`YOLOEnvironmentResult` probed the weights only `if (!string.IsNullOrWhiteSpace(path_Model))`, so a `null` `ModelPath`
passed the preflight, exported 55 366 images over 4.5 minutes and failed on the first real open (`DiGi.GIS.YOLO.UI#6`).

## §1.16 Options defaults are the contract
`YearBuiltPredictionPipelineOptions.ModelPath` defaulted to `null` (its `<summary>` promised a search that no longer
existed), fatal to every tray run, whose dialog offers no weights control (`DiGi.GIS.PostgreSQL.UI#9`).

## §1.17 Extension receivers box
In `DiGi.Core#5` the issue, the implementation summary and the review draft disagreed about the binding; a 40-line probe
showed the issue right and nothing ambiguous.

## §1.18 Reflection by name
`type.GetMethod(nameof(RuleData))` forbids hiding `RuleData` with `new` — the `DiGi.Typology.Visual` rules had to be
re-parented onto `TypologyFilterRule`.

## §3 Solution assets
- **`user files/` ships:** 1.17 GB of model variants once rode along on every deploy (`Coding - YOLO.md` §3).
- **Never print a conf:** a `sed -E 's/(Password|pwd)=[^;]*/…/'` written for `Key=value;` matched nothing in a conf shaped
  `PASSWORD="value"` and the password reached the transcript.
- **Build-copied assets:** the overwrite looked like a mysterious revert in `DiGi.GIS.WebAPI.UI#58`; bodyplan `94aa1b6`
  lost its #123 fix.
