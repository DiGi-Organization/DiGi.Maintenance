---
name: coding-wpf-deferred-loading
description: "Use when a WPF window or dialog needs slow data, or when verifying WPF layout without its host - open at once, read from the constructor without awaiting, bottom-left progress bar and status label, refresh in place, cancel and dispose on Closed (OK included; the server keeps running until commandtimeout, DiGi.GIS.WebAPI#77), no ConfigureAwait(false) in the window, null means unknown, STA facts with a DispatcherSynchronizationContext, the off-screen render harness."
---

# AI Guidelines: WPF Deferred Loading (slow data in a window or dialog) & WPF Test Harnesses

Default for a WPF window or dialog needing slow data: **open at once, read in the background, show that it is loading
(status text + indeterminate progress bar, bottom-left), fill in place when it arrives.** A failed read says so and never
pretends to be an answer. Reference (workspace-relative):
`DiGi.GIS.PostgreSQL.UI/DiGi.GIS.PostgreSQL.UI/Windows/YearBuiltPredictionsOptionsWindow.xaml(.cs)`, fed by
`Query/PredictedYearBuiltCoverageFactorsAsync.cs`, opened by `Classes/BackgroundTask/UIYearBuiltPredictionsTask.cs`; facts
`DiGi.Test/DiGi.GIS.PostgreSQL.UI.xUnit/Facts/YearBuiltPredictionsOptionsWindow_Coverage*.cs` (DiGi.GIS.PostgreSQL.UI#40).

## 1. When it applies
| The data… | Do |
|---|---|
| is what the window cannot work without (the list to choose from) | Read it **before** the window opens, on the background task's thread (not inside `Dispatcher.Invoke`); refuse to open if it fails. |
| decorates what is shown (coverage markers, counts, statuses), or may take > ~0.5 s, or grows with the estate | **Defer it** (below). |
| is fast and bounded | Read inline — a 50 ms progress flash is noise. |

Work started inside `Dispatcher.Invoke` freezes the whole UI; the Year Built coverage read took 2.6 s for 0.66 M rows and
will take about a minute at national coverage.

## 2. The mechanism
### 2.1 Window contract
- The constructor takes the read as a delegate, `Func<CancellationToken, Task<T?>>? xAsync = null`, a lambda capturing what
  it needs (the window knows nothing about HTTP). `null` = no read: nothing marked, no progress bar.
- The window owns a `CancellationTokenSource`; `Closed` cancels and disposes it (§2.5).
- The constructor fills what is known, sets the status text, shows the bar and starts the read **without awaiting**:
  `_ = ReadXAsync(xAsync);`.
- A **public `SetX(T? x)`** stores the value, updates the status, hides the bar and redraws in place (public so facts and
  callers can apply a result without a read).

### 2.2 The private read method
```csharp
private async Task ReadXAsync(Func<CancellationToken, Task<Dictionary<int, double>?>> xAsync)
{
    try
    {
        Dictionary<int, double>? x_Read;
        try
        {
            x_Read = await xAsync(cancellationTokenSource.Token); // no ConfigureAwait(false): resume on the UI thread
        }
        catch (OperationCanceledException) when (cancellationTokenSource.IsCancellationRequested)
        {
            return;
        }
        catch (Exception exception)
        {
            Serilog.Modify.Log(Serilog.Enums.LogEventLevel.Warning, "X could not be read: {Message}", exception.Message);
            x_Read = null;
        }

        if (cancellationTokenSource.IsCancellationRequested)
        {
            return; // the window closed meanwhile - leave it alone
        }

        SetX(x_Read);
    }
    finally
    {
        ProgressBar_X.Visibility = Visibility.Collapsed; // every exit, including the cancelled returns
    }
}
```
- **No `ConfigureAwait(false)` in the window** (touching a control off the UI thread throws); it belongs inside the
  `Query` member doing the I/O.
- **Hide the bar in `finally` as well as in `SetX`** — the cancelled path returns before `SetX`.

### 2.3 Layout
The button row is a two-column grid: the bar in the empty left column, buttons right-aligned.
```xml
<Grid Grid.Row="1">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*" />
        <ColumnDefinition Width="Auto" />
    </Grid.ColumnDefinitions>
    <ProgressBar x:Name="ProgressBar_X" Grid.Column="0" IsIndeterminate="True" Width="150" Height="14" Margin="10,0,10,0" HorizontalAlignment="Left" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Reading X" />
    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="5,5,5,5">
        <!-- OK / Cancel -->
    </StackPanel>
</Grid>
```
`Collapsed` in markup; a **status label** near the data says what is loading, then the legend or the failure (without
it an unmarked item reads as "loaded, answer is no"). Never disable controls while reading.

### 2.4 Redraw in place
Refresh the items (`ListBoxControl.RefreshItems()`, re-running the `ItemAdding` naming), never re-set the list — that
discards selection and scroll. Item text is decided in the naming callback from the stored result, so one path serves
"not loaded" and "loaded".

### 2.5 Closing before the data arrives
```csharp
// In the constructor, before the read starts.
Closed += (sender, e) =>
{
    cancellationTokenSource.Cancel();
    cancellationTokenSource.Dispose();
};
```
1. **Every way out cancels, OK included** (`Closed` fires for OK, Cancel and the close box) — never only the Cancel button.
2. **The client stops:** the token reaches the `Query` member (linked to its timeout); running `HttpClient` calls are
   abandoned and throttled requests never start.
3. **The server does not stop as deployed (DiGi.GIS.WebAPI#77).** Passing the token down is necessary (an endpoint that
   drops it runs until `commandtimeout` — check the controller when adding a read) but not sufficient:
   `terrain/densitiesbycountyids` passes it to `ExecuteReaderAsync`, yet a request whose socket closed at 4 s kept loading
   the server (re-run 18.9 s vs 14.1 s alone, 20.5 s for two at once, 2026-11-07). Until #77 is fixed the server
   `commandtimeout` the `Query` member sends is what ends an abandoned query — keep it no longer than the client wait.
   Measure (the #77 probe), do not read code, before claiming a close frees the server.
4. The `Query` member rethrows the caller's cancellation (`catch (…) when (cancellationToken.IsCancellationRequested) { throw; }`).
5. The window returns before `SetX`; `finally` collapses the bar; status and items stay; nothing is logged (a
   cancellation is not a failure).
6. A result arriving as the window closes is dropped by the post-`await` check — a closed window is never redrawn.
7. The continuation still runs later (the tray dispatcher keeps running); the read method catches everything.
- **Dispose after `Cancel` in the same handler** (it was once left to the finalizer per dialog). Safe because the read took
  `.Token` synchronously in the constructor and `IsCancellationRequested` still answers after `Dispose()`; never read
  `.Token` after close (`ObjectDisposedException`).
- A cancellation can surface as another exception (`HttpRequestException` on a torn connection): one spurious Warning from
  the `Query` member, otherwise harmless.

## 3. The read itself (`/Query/<Name>Async.cs`)
- `public static async Task<T?> XAsync(…, CancellationToken cancellationToken = default)` returning **`null` for every
  failure** (unreachable, error status, unparsable, length mismatch, endpoint absent), logging a Warning each, no retry;
  only the caller's own cancellation is rethrown.
- **Bound it:** `CreateLinkedTokenSource(cancellationToken)` + `CancelAfter(timeout)`, sending the same seconds as the
  server's `commandtimeout`; the timeout lives in a `Constants` class with a `<summary>` saying how it was measured.
- **Batch:** a fixed number of requests via `Task.WhenAll`, never one per item. With many capped batches throttle with a
  `SemaphoreSlim` (`WaitAsync(token)`, `Release()` in `finally`) held in a `using` that encloses the `await Task.WhenAll(…)`
  — `WhenAll` waits for every request, so no `Release()` hits a disposed semaphore (reference:
  `Query/TerrainPointDensityResultsAsync.cs`, 3 at a time). Return `null` if **any** batch fails — a partial result reads
  as "measured, nothing found".
- Prefer cheap sources for decoration (a planner estimate, `estimatedcounts…`, over `COUNT(*)`); no caching
  (`Coding - General.md` §1.20).

## 4. Unknown is not "no"
`null` = unknown: nothing marked, the status says the data could not be read ("… could not be read - no county is
marked"). Never fall back to an empty result — it renders exactly like "nothing done". A `null`/NaN/missing value for one
item gets no decoration rather than a default.

## 5. Facts (`thread.SetApartmentState(ApartmentState.STA)`, controls via `window.FindName("…")`)
| Case | Construct with | Assert |
|---|---|---|
| No read | `xAsync: null` | bar `Collapsed`; status empty |
| Pending | `_ => new TaskCompletionSource<T?>().Task` | bar `Visible`; `SetX(value)` → `Collapsed` |
| Completes at once | `_ => Task.FromResult<T?>(value)` | bar `Collapsed`; items decorated |
| Throws at once | `_ => Task.FromException<T?>(new InvalidOperationException())` | bar `Collapsed`; failure status; nothing decorated |
| Closed before data | a read ending only on cancellation; `window.Close()`; pump | token cancelled; bar `Collapsed`; status/items unchanged |

Closed-before-data (`DiGi.Test/DiGi.GIS.PostgreSQL.UI.xUnit/Facts/OptionsWindows_CloseBeforeData.cs`, one helper + one
fact per window):
1. Install the application's context first:
   `SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher))` —
   otherwise the `await` resumes on the pool and the fact tests a path the application never takes.
2. Construct with `token => { token.Register(() => taskCompletionSource.TrySetCanceled(token)); return taskCompletionSource.Task; }`.
3. `window.Close()` (raises `Closed` on a never-shown window); assert the token is cancelled.
4. Pump: `DispatcherFrame frame = new(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false)); Dispatcher.PushFrame(frame);`.
5. Assert the bar `Collapsed` (only `finally` can do it) and items/status unchanged (`SetX` never ran).

Never complete a pending task without pumping (the continuation never runs) — use `SetX` or step 4. Never `ShowDialog`;
keep message boxes in the caller, or a fact clicking OK hangs. Layout of a never-shown window cannot be measured — check
placement on screen once (or §7).

## 6. Traps
| Symptom | Cause |
|---|---|
| Dialog opens late / UI freezes first | Read awaited before `ShowDialog()` or run inside `Dispatcher.Invoke` |
| Cross-thread `InvalidOperationException` | `ConfigureAwait(false)` in the window's read method |
| Bar keeps spinning after data or close | Bar hidden only on the success path — hide it in `finally` |
| Selection lost when data arrives | List re-set instead of refreshed |
| Every item "not done" after a network error | Failed read turned into an empty result instead of `null` |
| Server keeps querying after close | Token not passed down, or the controller drops it — **and, as deployed, even when both are right** (#77): keep the server `commandtimeout` ≤ the client wait |
| Read continues after OK | Cancellation on the Cancel button instead of `Closed` |
| `ObjectDisposedException` after close | `.Token` read from the disposed source |
| Warning "could not be read" on close | Cancellation surfaced as `HttpRequestException` — harmless |
| Closed-before-data fact passes vacuously or hangs | No `DispatcherSynchronizationContext`, or dispatcher never pumped |
| A fact hangs | Modal box in the window, or awaiting a continuation on an unpumped dispatcher |

## 7. WPF controls without their host — off-screen render harness
The WPF counterpart of `Coding - Browser Testing.md`. Most `DiGi.UI.WPF` controls appear only in the tray application
(credentials + database needed), so verify layout in a scratchpad console project (`net8.0-windows`, `UseWPF`,
`HintPath` to `DiGi.UI.WPF` and `DiGi.Core`):
- Mock the control's item interface in the harness with the plain properties the XAML binds to (WPF binds by reflection on
  the runtime type).
- `new Application();` first; host the control in a mirror of the real layout (its `TabControl`, margins) sized to the
  host's **client** area (an 800×450 window is ~784×411 of content).
- `Measure`/`Arrange`/`UpdateLayout`, then pump `Dispatcher.CurrentDispatcher.Invoke(DispatcherPriority.SystemIdle, …)`
  two or three times (a `DataGrid` generates rows in a background pass); `RenderTargetBitmap` at 192 dpi →
  `PngBitmapEncoder`.
- **Walk the visual tree, do not only screenshot:** print each `TextBlock`'s `TextWrapping`/`TextTrimming`/`MaxHeight`/
  `ToolTip` via `VisualTreeHelper` — that caught **`Setter.Value` silently dropping a `MultiBinding`** (it takes a single
  `Binding`; no warning, the tooltip never appears). `DataGrid` has no `MaxRowHeight` — cap a wrapping cell with
  `MaxHeight` on the `TextBlock`.
- Drive a dialog with `window.Loaded` → `RenderTargetBitmap`, `FindName`, `RaiseEvent(ButtonBase.ClickEvent)`; dismiss
  validation boxes with a `DispatcherTimer` + `FindWindow("#32770", title)` + `WM_CLOSE`. Rebuild the harness after
  rebuilding the UI project (it copies the dll at its own build time).
