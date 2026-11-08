---
name: coding-yolo
description: "Use when working on the YOLO Year Built detector (DiGi.YOLO, DiGi.GIS.YOLO.UI and its runner) - model.pt path resolution and SHA-256, the first-confident-detection predictor, training data and scratch outside the workspace (never in user files/), chunked scratch folders and score-only runs reading results.bbrf, deploying the runner extension from an allowlist (only model.pt)."
---

# AI Guidelines: YOLO Year Built Detector — Runner, Training & Deployment

> **Only the shipped detector `YOLO/models/model.pt` is deployment content. Training inputs, earlier weights and run
> scratch live in a training directory outside the workspace, and the runner extension is deployed from an allowlist —
> never a blocklist.**

## 1. Components
| Repository / project | Role |
|---|---|
| `DiGi.Python` | CPython process interop shared with DiGi.Laya: `Query.ExecuteProcess` (→ `PythonProcessResult`, inactivity stall, process-tree kill), `Query.PythonPath`/`PythonPaths`, `Query.MarkedJson`, `Query.FileSHA256`, `Query.NormalizedPath`, `Modify.WriteScripts` (moved out of DiGi.YOLO, DiGi.YOLO#23). Reached by `HintPath`, so every project compiling against it re-declares it and each host (runner, tray, facts) carries `DiGi.Python.dll`. |
| `DiGi.YOLO` | The ultralytics wrapper: prediction, `train.py`/`val.py`, `Modify.Train`/`Validate`, the preflight `YOLOEnvironmentResult` (kept a plain `SerializableResult` — deriving from `PythonEnvironmentResult` would add `"Packages": null` and reorder stored JSON), its scripts and marker pairs (`Constants.Marker`). |
| `DiGi.YOLO.ONNX` | In-process ONNX inference (`Microsoft.ML.OnnxRuntime.Managed`) — **not** the pipeline default (DiGi.GIS.YOLO.UI#1 closed not planned); `model.onnx` kept in sync with `model.pt` (DiGi.YOLO.ONNX#2). |
| `DiGi.GIS.YOLO` | `Create.Building2DYearBuiltPredictions` — detector boxes → per-building predictions. |
| `DiGi.GIS.YOLO.UI` | The pipeline library: options, `Modify.RunYearBuiltPredictionsAsync`, dataset build, training orchestration. |
| `DiGi.GIS.YOLO.UI.ConsoleApp` | The headless runner: no flag = prediction run with the options file as first argument; `--dataset`, `--check-labels`, `--evaluate-detector` take a `YOLOTrainingDatasetOptions` file; `--train` a `YOLOTrainingRunOptions` file. |
| `DiGi.GIS.PostgreSQL.UI` | The tray: `UIYearBuiltPredictionsTask`, `UIYOLOTrainingTask` start the runner with `Process.Start` from `bin\extensions\DiGi.GIS.YOLO.UI.ConsoleApp\` (§5). |

- **Prediction runs on CPython with `model.pt`.** Every inference host needs the ultralytics version the weights were
  trained with (8.4.165 for `train9_fresh`; YOLO26 does not load under 8.3.130); the preflight refuses older
  (DiGi.GIS.YOLO.UI#23). GPU inference through Emgu is unavailable (`Coding - Host Dependencies.md` §1).
- **The detector dates every building directly — no regressor in the scoring path** (DiGi.GIS.ML#15):
  `Query.PredictedYearBuilts` predicts the first year `model.pt` detected the building with confidence ≥ 0.5, else its first
  detection, and leaves out a building never detected; `ModelId` = `first-confident-detection@0.5`. Detector quality is
  the year's quality. `OrtoBuildingDetectionModel.mlnet` stays in DiGi.GIS.ML only as an evaluation baseline (DiGi.GIS.ML#17,
  parked): it memorised its training counties (coordinates, each county's orthophoto-year pattern) and dated an unseen
  county years late (76–89 % after the first confident detection). A model returns only by beating the heuristic on a
  held-out county, and never scores another detector's detections.

## 2. Weights — `model.pt` and path resolution
- `ModelPath` defaults to `user files/YOLO/models/model.pt` (`YearBuiltPredictionPipelineOptions`,
  `YOLOTrainingDatasetOptions`). `Query.ModelPath` tries it as given, then against the application base directory, then —
  for a `user files/` prefix — with that segment stripped against the base and current directories (`CopyUserFiles`
  flattens it into `bin`), so one value works in a checkout and beside a deployed executable. An absolute path is used as is.
- **`model.pt` is replaced in place** when a new detector ships: a file name says nothing — compare the SHA-256 the run log
  records at start.
- The replaced detector (`model_train8.pt`, its ONNX export) is kept in the training directory, not beside `model.pt`.
- A preflight resolves the path as the runner will before calling it absent (`Coding - General.md` §1.15).

## 3. Training data lives outside the workspace
`user files/` ships (`Coding - General.md` §3), so DiGi.GIS.YOLO.UI's holds only what the runner reads:
`GIS_WebAPI_Client.conf`, the prediction options, `YOLO/models/model.pt` (it once carried 1.17 GB of model variants plus a
38 MB legacy table to every deploy). The **training directory outside the workspace** on the training machine holds
earlier/alternative weights (`model_train8.*`, `model_train9_*`), ONNX exports, base weights (`base/yolo26x.pt`), the legacy
table `Data_2025.05.27.tsv`, datasets, runs (`runs/<RunName>/`), training/experiment options and reports, and training and
labelling scratch (§4). Its options name inputs by **absolute path** and are passed explicitly (`--dataset <path>`,
`--train <path>`, or the first argument of a prediction run).

**Known gap — tray training defaults.** `UIYOLOTrainingTask` resolves its start weights (`YOLO/models/base/yolo26x.pt`) and
the dataset step's `LegacyReferencesFilePath` (`user files/Data_2025.05.27.tsv`) beside the runner, where they are no longer
deployed. Weights can be typed into the dialog; the legacy table cannot, so a tray run with the Dataset step is refused —
run that step from the console with an options file in the training directory. Update this when the tray gets a
configurable training location.

## 4. Scratch folders
- **`ScratchDirectory` resolves against the current directory** — the runner's own `bin` (or the **tray's** current
  directory, normally `DiGi.GIS.PostgreSQL.UI\bin`, when started from the tray), so a relative value writes imagery into a
  deployable folder. Production prediction runs may use the relative default `scratch` (they clean up; a failed county keeps
  ~370 000 images / 6 GB); **training and labelling runs** (`CleanScratchDirectory: false`) set an absolute path in the
  training directory — `scratch_train9` in `bin` was 235 042 files / 3.4 GB.
- **No image folder holds a whole county.** Buildings are sorted ordinally into `chunks/<index>/` of `ChunkSize` (default
  5000 buildings, ~55 000 files); each chunk is exported, detected into `chunks/<index>.bbrf`, marked by
  `chunks/<index>.json`, then its imagery removed; `results.bbrf` joins the chunks after the last one (a pre-DiGi.GIS.YOLO.UI#30
  folder has a flat `images/`, still read). The flat folder failed on a stock machine — m. st. Warszawa (55417, 1.72 M images):

  | Condition | Export rate |
  |---|---|
  | ≤ ~0.8 M files in one folder, 8.3 names on | 185–215 images/s |
  | ~1.38 M files, 8.3 on | 6.5–8 images/s |
  | same, after `fsutil 8dot3name set C: 1` | 204 images/s |
  | 100 000 files flat, 8.3 off | 6 218 files/s |

  The 8.3 setting is per machine, needs an administrator and came back within days — code must not depend on it. Refuted:
  the per-reference resume scan is not quadratic (0.09 ms over 1.72 M files, NTFS answers prefixes from its index); folder
  size does not limit the detector (flat 110 images/s, the `predict.py` loop is the limit).
- **A chunk marker carries the weights' SHA-256 and `Confidence`;** with `Resume` a chunk is skipped only when its marker
  matches its buildings, weights and threshold (a marker naming only buildings would let an earlier detector stand in for the
  replaced `model.pt`).
- **`CleanScratchDirectory` (default `true`)** removes a county's folder after a clean finish; a failed county keeps it so a
  re-run costs seconds. `false` only for a run whose scratch you will read.
- **`Resume`** also skips images already on disk. With `RunPrediction` on, every chunk without a matching marker is
  detected again; **with it off (score-only), the county's `results.bbrf` in scratch is the input** — stored detection
  columns are never read back, so scratch left by a replaced detector is scored as current. Delete it.

## 5. Deploying the runner extension
`DiGi.GIS.PostgreSQL.UI\bin\extensions\DiGi.GIS.YOLO.UI.ConsoleApp\` holds a standalone executable, never loaded into the
tray (`Coding - Host Dependencies.md` §4).
- **Its own deployment unit:** its own dependency closure and its own `GIS_WebAPI_Client.conf` (not the tray's);
  `CheckHostDependencies.ps1` audits it as a separate unit.
- **Absence is supported:** `Deploy.ps1` assembles it only with `INCLUDE_YEAR_BUILT_PREDICTION_EXTENSION` in
  `user files/Directories.conf`; without it the tray withholds the task rather than offering one that fails after counties
  were chosen.
- **Assemble it by a LOCAL sync into the host's own `bin`**, never as a software destination of its own — `SyncDirectory.ps1`
  clears each destination's top level, so a nested destination is wiped by its parent's sync and `$SyncList` order becomes
  load-bearing. In `bin` first, it travels with the application and resolves by the same path everywhere.
- **Allowlist, never blocklist** (excluding `scratch` by name let `scratch_train9` — 235 042 files — reach the host).
  `Deploy.ps1` copies: root files minus `Data_*.tsv`, `YOLOTraining*Options*.json`, `*.hold`, `*.log` (`-ExcludeFile`);
  `runtimes` and satellite resource folders (`*.resources.dll` only, `Test-DeployableDirectory`); of `YOLO` only
  `YOLO\models\model.pt` (`IncludePath`; `model.onnx` is not read and not deployed).
- **The tray's own `bin` is allowlisted too:** only `extensions`, `runtimes` and satellite folders reach the software
  directory; the rest (`scratch`, `logs`) is printed on `DiGi.GIS.PostgreSQL.UI - not deployed:`. A new runtime folder must
  be added explicitly.
- **Read the size line:** `Year Built prediction extension: N file(s), X MB. Not deployed: …` — about 212 files / 268 MB;
  it warns above 1 000 files or 1 GB or without `model.pt`. An allowlist omits a newly needed runtime folder **silently**
  until added to `Test-DeployableDirectory`/`IncludePath` — `Not deployed:` shows it.
- **The runner declares its NuGet closure itself** (`DiGi.GIS.YOLO.UI.ConsoleApp.csproj`) — only packages actually loaded:
  stale `TorchSharp`/`OneDal` once shipped ~1.6 GB of native runtimes. Verify with `CheckHostDependencies.ps1`.

## Checklist
- [ ] `user files/` holds only the conf, prediction options and `model.pt`?
- [ ] Training/labelling options name an absolute `ScratchDirectory` and absolute inputs in the training directory?
- [ ] New imagery-writing code uses bounded chunk folders, never one flat per-county folder?
- [ ] After a deploy: ~212 files / 268 MB, `scratch*`, `logs`, `reports` under `Not deployed:`, no warning?
- [ ] New detector: `model.pt` replaced, old weights kept in the training directory, SHA-256 on the issue, year built
      re-measured with `YearBuiltPredictionEvaluationConsoleApp`?
