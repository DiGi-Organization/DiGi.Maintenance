---
name: coding-laya
description: "Use when working on the Laya decision model (DiGi.Python, DiGi.Laya, consumers) - checkpoint identity by DirectorySHA256 of the whole folder (never write inside a checkpoint), training outside the workspace, mandatory fine-tune and calibration, releasing to LAYA_MODELS_DIRECTORY and deploying with DeployLaya.ps1 (allowlist, manifest, -Remove only), the host venv from InstallPythonEnvironment.ps1 outside the synced directory."
---

# AI Guidelines: Laya Decision Model — Runner, Training & Deployment

Laya is not generative: one forward pass answers typed questions (`choice`, `score`, `noul`) about a state.

> **A checkpoint folder is identified by the SHA-256 of its whole content, so nothing is ever written inside a deployed
> one — no manifest, no calibration, no training output. Checkpoints are released outside the workspace, deployed by
> `DeployLaya.ps1` from an allowlist, and the Python environment is created on each host outside the synced software
> directory.**

## 1. Components
| Repository | Role |
|---|---|
| `DiGi.Python` | CPython interop shared with DiGi.YOLO: `Query.ExecuteProcess`, `PythonPath`, `MarkedJson`, `FileSHA256`, **`DirectorySHA256`**, `Modify.WriteScripts`, `PythonEnvironmentResult`. |
| `DiGi.Laya` | `Modify.PredictAsync`, `ClassifyAsync`, `TrainAsync`, `CalibrateAsync`, preflight `Query.LayaEnvironmentResult`; scripts in `files/Laya/` (`check.py`, `predict.py`, `train.py`, `calibrate.py`, `requirements.txt`). |
| Consumers (bodyplan, DigiProject-Organization/bodyplan#77) | Own the states, label sets, thresholds (`LayaClassificationOptions.Thresholds`), confs and their deploy script (which calls `DeployLaya.ps1`). |

- **One CPython process per batch** (JSONL request → `predict.py`, one model load → JSONL response) — not ONNX (`laya[onnx]`
  refuses parallel-layout checkpoints), not a resident service (`laya-serve` is undecided).
- Both libraries are `netstandard2.0` with `DiGi.Core` by `HintPath` (no NuGet gap); a host still carries
  `DiGi.Python.dll` and `DiGi.Laya.dll`.

## 2. Model identity
- **`ModelSHA256` = `DiGi.Python.Query.DirectorySHA256` of the whole folder:** every file recursively, `/`-separated
  relative paths sorted **ordinally**, a manifest of `path\nlowercase-sha256\n` per file, the lowercase SHA-256 of its UTF-8
  bytes. Reported by `LayaTrainingResult`, `LayaPredictionResult`, `LayaClassificationResult`, `LayaEnvironmentResult`;
  consumers store it with each suggestion. A PowerShell reimplementation sorts with
  `List[string].Sort([StringComparer]::Ordinal)` — `Sort-Object` is culture-aware and case-insensitive (`B.txt`/`a.txt`
  flip).
- Anything added inside changes the SHA — the deploy manifest and calibration sit **beside** the folder
  (`models\<name>.manifest.json`, `models\<name>.calibration.json`); `CalibrateAsync` refuses a path inside the checkpoint.
- `Query.LayaModelPath` refuses a model name or Hub id (only a local folder). Production never downloads
  (`Query.PythonProcessResult` and `utils.py` set `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`); `Query.LayaPythonPath` refuses an interpreter that does not resolve as
  given (DiGi.Python's `PythonPath` would fall back to any `python` on `PATH`).

## 3. Training lives outside the workspace
A checkpoint (`model.safetensors` alone is 644 MB for `laya-multilingual`, fp16) never sits in `user files/` (copied into
every build) or a synced `bin` (recopied every deploy, or deleted). One training directory on the training machine, named by
absolute path in the options of `TrainAsync`/`CalibrateAsync`, holds the venv, base checkpoints
(`checkpoints\convaiinnovations-laya\multilingual`), datasets, gold sets, runs, reports and scratch (`runs\<name>\`).
`Modify.TrainAsync` refuses an output inside a `Laya\models` or `DiGi.Laya\models` folder. laya's `laya-train` leaves
`checkpoint_latest\` (a full duplicate) — DiGi.Laya's `train.py` removes it and `DeployLaya.ps1` never deploys it.

## 4. Before trusting a probability
- **Fine-tune and calibrate on the consumer's data — both mandatory.** Shipped checkpoints are over-confident (temperature 1)
  and weak zero-shot. `CalibrateAsync` fits a temperature per question type on a gold split into the calibration file,
  read through `LayaPredictionOptions.CalibrationPath`.
- laya holds out `min(calib_max, int(n * calib_frac))` items and reports ECE only for buckets of ~2 500+ records — a small
  gold set gives no ECE, not a good one.
- Ship only a model that beats zero-shot **and** a deterministic baseline on held-out data; tune thresholds on calibrated
  scores only.

## 5. Releasing and deploying
A release is a folder plus an optional side file in `LAYA_MODELS_DIRECTORY` (`user files/Directories.conf`):
`<LAYA_MODELS_DIRECTORY>\recipe_classification\` + `recipe_classification.calibration.json`. With `INCLUDE_LAYA_MODELS=true`,
`Deploy.ps1` calls `DeployLaya.ps1` **after** the software syncs; a consumer's deploy script calls it directly.
- **Its own top-level destination** `<SOFTWARE_DIRECTORY>\DiGi.Laya\` (`requirements.txt`, `InstallPythonEnvironment.ps1`,
  `models\`), never a `$SyncList` entry — nested it is cleared by the parent's sync (`Coding - YOLO.md` §5); synced whole it
  recopies every checkpoint and deletes models a host still uses.
- **Allowlist:** `model.safetensors` and root `*.json` (`rl_agent_config.json`, `questions.json`, `train_report.json`),
  `encoder\*.json`, `tokenizer\*.json|*.model|*.txt`; everything else (`checkpoint_latest/`, `scratch/`, logs) is printed on
  `Not deployed:` — a new file type the layout needs is omitted silently until added.
- **The manifest makes redeploys cheap:** `models\<name>.manifest.json` records each file's SHA-256 and size,
  `directorySHA256`, `calibrationSHA256`, `sourcePath`, `deployedAt`. Unchanged and complete → `skipped (unchanged)`; changed
  → copied to `<name>.staging`, re-hashed, swapped in, manifest written last (an interrupted deploy recopies). Models never
  touch each other.
- **The released SHA is the deployed-folder SHA** (allowlisted files only): release a clean folder (DiGi.Laya's `train.py`
  output is) so `LayaTrainingResult.ModelSHA256` equals the manifest's.
- **Removal only by `-Remove <name>`;** a model missing at the source is reported, not deleted; turning
  `INCLUDE_LAYA_MODELS` off leaves `DiGi.Laya\` alone.
- **Read the size line:** `N file(s), X MB` per model (fine-tuned layout: seven files); above `-MaxFileCount` (50) or
  `-MaxMB` (4096) the five largest files are listed.

## 6. The host environment (on each host, never by `Deploy.ps1` — servers have no development tooling)
1. CPython ≥ 3.10, readable and executable by the service account running the consumer (`DiGi.WebAPI.WindowsService` on the
   database server).
2. `InstallPythonEnvironment.ps1 -PythonPath <python.exe> -RequirementsPath <SOFTWARE_DIRECTORY>\DiGi.Laya\requirements.txt -Destination <venv> -Torch cpu|cuda`
   — **`<venv>` outside the synced software directory** (several GB, host-specific; a sync service would spread it).
3. Consumer conf: `PythonPath` = the venv `python.exe`, `ModelPath` = `…\DiGi.Laya\models\<name>`, `CalibrationPath` =
   `…\DiGi.Laya\models\<name>.calibration.json`.
4. Run the consumer's preflight (`Query.LayaEnvironmentResult`, e.g. bodyplan's `--check`).
- `requirements.txt` pins `laya` exactly (`check.py` refuses others) with floors for `transformers`/`torch`; torch installs
  first from the variant's index (`cpu`, or `cu128` for `cuda` — Blackwell needs CUDA 12.8).
- `environment.json` records the install (Python, `pip freeze`, requirements SHA-256, torch variant/version, CUDA); the same
  requirements and variant is a no-op, a new `requirements.txt` makes the next run reinstall.

## 7. Running
- `InactivityTimeout` counts silence, not duration: `predict.py` prints per 256 states; `calibrate.py` prints nothing until
  done, so its limit covers the whole calibration.
- Two runs never share a `WorkingDirectory` (`null` = a temporary one).
- Measure latency on the host that runs it; GPU inference on the database server is out of scope.

## Checklist
- [ ] Released checkpoints outside the workspace, nothing added inside after training?
- [ ] Fine-tuned **and** calibrated on the consumer's data, beating zero-shot and the deterministic baseline held-out?
- [ ] Deploy prints `skipped (unchanged)` for untouched models and nothing unexpected under `Not deployed:`?
- [ ] Host conf names the venv `python.exe`, the model folder and its calibration file; preflight passes?
- [ ] Venv outside the synced software directory?
- [ ] Host-reported `ModelSHA256` = manifest `directorySHA256` = the training record?
