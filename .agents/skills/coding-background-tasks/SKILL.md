---
name: coding-background-tasks
description: "Use when writing or changing a tray-application background task (DiGi.GIS.PostgreSQL.UI) - PostgreSQL<X>Task : ReportableBackgroundTask<long>, options property named after its type, an Error log before every return false, progress and cancellation, the UI<Task> wrapper showing its options window inside Dispatcher.Invoke on a copy, registration in Create.VisualBackgroundTasks, client <Type>sPostTask uploads with CountyIds."
---

# AI Guidelines: Background Tasks (server tasks, tray wrappers, post tasks)

Long-running jobs of the GIS tray application (`DiGi.GIS.PostgreSQL.UI`) and their client-side counterparts.
Reference pair: `DiGi.GIS.PostgreSQL/.../Classes/BackgroundTask/PostgreSQLTerrainPointFillGapsTask.cs` and
`DiGi.GIS.PostgreSQL.UI/.../Classes/BackgroundTask/UIPostgreSQLTerrainPointFillGapsTask.cs`. Base classes:
`DiGi.Core/Classes/BackgroundTask/` (`BackgroundTask`, `CancelableBackgroundTask`, `ReportableBackgroundTask<T>`).

## 1. The server task
- **Shape:** `public class PostgreSQL<X>Task : ReportableBackgroundTask<long>, IGISPostgreSQLObject` (a plain
  `BackgroundTask` only for one-shot DDL such as the create-database tasks). Dependencies come through the constructor
  (`GISPostgreSQLConverterManager`, `HttpClient?`); throw `ArgumentNullException` for a required one.
- **Options:** a property named after its type, `public PostgreSQL<X>Options PostgreSQL<X>Options { get; set; } = new();`
  — the options class is `<task name without "Task">Options : SerializableOptions` in `Classes/Options/`
  (mutable by design, `Coding - Serialization.md` §8).
- **Refuse with a logged reason, then `return false`:**
  `Serilog.Modify.Log(Serilog.Enums.LogEventLevel.Error, "{Type}: ...", nameof(PostgreSQL<X>Task))`. `BackgroundTask` wraps
  a `false` without an exception into `BackgroundTaskFailureException` ("a reason, if one was logged, is in the logs
  folder") — without the Error line the row points at a log that holds nothing.
- **Progress:** `progress.Report(count)` with a running total (`long`); expose result counters as get-only properties
  (`PointCount`, `FailedBatchCount`, …) and keep bounded samples of failures (cap the list, never the count).
- **Cancellation:** pass the token everywhere and rethrow only a requested cancel
  (`catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }`, `Coding - General.md`
  §1.22). `CancelableBackgroundTask` reports Canceled only when its own source was cancelled; a timeout or a cancel from
  elsewhere is a failure.
- **Per-item failures** inside a county/batch loop are logged and counted, and the loop moves on — but a general
  `catch` must sit after the cancellation filter, or Stop is swallowed and the run continues.
- **Scope by county part:** take `CountyIds` (plural) and walk parts; a code with several parts is one group
  (`Coding - GIS Administrative Data.md` §4).

## 2. The tray wrapper (`UI<Task>`)
Every task offered with a dialog is a subclass `UI<BaseTask>` in `DiGi.GIS.PostgreSQL.UI/Classes/BackgroundTask/`
(30 of 30) overriding `ExecuteAsync(IProgress<long>, CancellationToken)`:
1. Check what the run cannot do without (a client, a converter) **before** the dialog, logging Error and returning `false`.
2. `System.Windows.Application.Current` — none means no UI thread: log and `return false`.
3. Read what the dialog cannot work without on **this** thread (not inside the dispatcher callback, which would freeze
   the UI); slow decoration is read by the window itself (`Coding - WPF Deferred Loading.md`).
4. `application.Dispatcher.Invoke(() => { … new <X>OptionsWindow(<X>Options, …); ShowDialog() … })` — a window cannot be
   created on the thread-pool thread the task runs on.
5. The window works on a **copy** (`new XOptions(x)`) exposed as a property named after its type; a cancelled dialog
   leaves the task's options untouched and ends the run (`Log(...)` + `return false`).
6. Copy the window's options back, then `return await base.ExecuteAsync(progress, cancellationToken);`.

## 3. Registration
`DiGi.GIS.PostgreSQL.UI/Create/VisualBackgroundTasks.cs`: `result.Add(Visual(new UI<X>Task(...), "Name", "Description"))`
inside the `Mode.Server` or `Mode.Client` block (both also run under `Mode.ServerAndClient`). An unregistered task never
appears in the tray; the `Visual` wrapper is where a failed task's exception is
logged. The description says what the dialog will ask for and any prerequisite task ("Import the sheet index first").
A task needing an optional deployment (the Year Built runner) is withheld when that part is absent rather than offered
and failed (`Coding - YOLO.md` §5).

## 4. Client-side post tasks
Tasks that upload through the GIS Web API are `<Type>sPostTask : SerializableObjectsPostTask<T>` in
`DiGi.GIS.WebAPI/.../Classes/BackgroundTask/`. Set `CountyIds` (plural); the scalar `CountyId` forwards one id onto the
trusted single-id branch (`Coding - GIS Administrative Data.md` §4). Size `PostOptions.Delay` for the batch
(`Coding - WebAPI Contracts.md` §3).

## 5. Where a run's evidence is
The tray application runs on both servers; a task's log is on the machine that ran it, and a development machine may run
a second instance from its repository `bin` (`Coding - Deployed WebAPI.md` §5). Production row counts and coverage are
read through the API, never through a `*.conf` (`Coding - PostgreSQL.md` §6).
