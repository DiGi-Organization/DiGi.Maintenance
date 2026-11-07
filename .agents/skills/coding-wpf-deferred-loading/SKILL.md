---
name: coding-wpf-deferred-loading
description: "Use when a WPF window or dialog needs data that takes noticeably long to read (over about half a second, or unbounded) - the default mechanism: open at once, start the read from the constructor as a Func<CancellationToken, Task<T?>> without awaiting it, show a status label plus an indeterminate progress bar in the bottom-left corner of the button row, apply the result through a public Set method that refreshes items in place (selection and scroll kept), cancel and dispose the token source on Closed (raised by OK too), hide the bar in finally, and what a close before the data arrives does end to end (passing the CancellationToken to the converter is necessary but, as deployed, not sufficient - the server keeps running an aborted query until commandtimeout, DiGi.GIS.WebAPI#77; throttled batches keep the SemaphoreSlim alive across Task.WhenAll). Also the traps: no ConfigureAwait(false) in the window (cross-thread exception), never read inside Dispatcher.Invoke or before ShowDialog, null means unknown and never an empty answer, the Query read returns null on every failure and bounds itself with a linked CancelAfter equal to the server commandtimeout, and the STA facts for no-read/pending/completed/failed reads plus the closed-before-data fact (install a DispatcherSynchronizationContext, Close, pump a DispatcherFrame)."
---

# AI Guidelines: WPF Deferred Loading (slow data in a window or dialog)

The default mechanism for a WPF window or dialog that needs data which takes noticeably long to read:
**open the window at once, read the slow data in the background, show that it is still loading (status
text plus an indeterminate progress bar in the bottom-left corner), and fill it in place when it
arrives.** A failed read says so and never pretends to be an answer.

Reference implementation (paths relative to the workspace root):
`DiGi.GIS.PostgreSQL.UI/DiGi.GIS.PostgreSQL.UI/Windows/YearBuiltPredictionsOptionsWindow.xaml(.cs)`,
fed by `Query/PredictedYearBuiltCoverageFactorsAsync.cs`, opened by
`Classes/BackgroundTask/UIYearBuiltPredictionsTask.cs`; facts in
`DiGi.Test/DiGi.GIS.PostgreSQL.UI.xUnit/Facts/YearBuiltPredictionsOptionsWindow_Coverage*.cs`
(DiGi.GIS.PostgreSQL.UI#40).

---

## 1. When it applies

| The data… | Do this |
|-----------|---------|
| is what the window cannot work without (the list to choose from) | Read it **before** the window opens, on the background task's thread, not inside `Dispatcher.Invoke`, and refuse to open if it fails. |
| decorates or annotates what is already shown (coverage markers, counts, previews, statuses), or can take longer than about half a second, or has no upper bound (grows with the estate) | **Defer it** with the mechanism below. |
| is fast and bounded | Read it inline. A progress bar that flashes for 50 ms is noise. |

**Why:** a dialog that waits for optional data keeps the operator staring at nothing, and work started
inside `Dispatcher.Invoke` freezes the whole UI thread for the duration of the query. The coverage
read behind the Year Built markers took 2.6 s for 0.66 M rows and is expected to take about a minute
at national coverage, so it had to be deferred.

## 2. The mechanism

### 2.1 Window contract
- The constructor takes the read as a **delegate**:
  `Func<CancellationToken, Task<T?>>? xAsync = null`.
  - The window starts the read itself. Nothing awaits it before `ShowDialog()`.
  - `null` means no read is done: nothing is marked, and the progress bar never appears.
  - Pass a lambda that captures what the read needs (manager, ids). The window knows nothing about HTTP.
- The window owns a `CancellationTokenSource`, and its `Closed` handler cancels it and then disposes it
  (§2.5). A read nobody is waiting for stops on the client, because the token reaches the request. The
  server query behind it does not stop yet (DiGi.GIS.WebAPI#77).
- The constructor fills everything that is already known first. Then it sets the status text, shows
  the progress bar, and starts the read without awaiting it: `_ = ReadXAsync(xAsync);`.
- A **public `SetX(T? x)`** applies the result:
  - it stores the value, updates the status text, hides the progress bar and redraws in place;
  - it is public so that facts and callers can apply a result without a real read.

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

- **No `ConfigureAwait(false)` in the window.** The continuation has to run on the UI thread that started
  it, otherwise touching a control throws a cross-thread `InvalidOperationException`. `ConfigureAwait(false)`
  belongs inside the `Query` member that does the I/O.
- **Hide the bar in `finally` as well as in `SetX`.** The cancelled path returns before `SetX`. A bar
  hidden only in `SetX` keeps spinning on a window whose read was abandoned.

### 2.3 Layout: the bottom-left progress bar

The button row is a two-column grid. The bar goes in the left column, otherwise empty, and the
buttons stay right-aligned. The status label above it says *what* is loading, and the bar shows that
it is still moving.

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

- `Visibility="Collapsed"` in the markup. The code shows the bar only when a read actually starts.
- Keep a **status label** next to the data, for example "Reading prediction coverage..." then the legend
  or the failure message. Without it, an unmarked item could mean either "not loaded yet" or "loaded,
  and the answer is no".
- The window stays fully usable while the read runs: selection, scrolling, OK and Cancel. Do not
  disable controls while the read runs.

### 2.4 Redraw in place
- Apply the result by **refreshing** the items (`ListBoxControl.RefreshItems()`, which re-runs the
  `ItemAdding` naming), never by re-setting the list. The data usually arrives while the operator is
  already selecting, and a rebuild discards the selection and the scroll position.
- Decide item text in the naming callback from the stored result, so the same code path serves both
  "not loaded yet" and "loaded".

### 2.5 Closing before the data arrives

```csharp
// In the constructor, before the read is started.
Closed += (sender, e) =>
{
    cancellationTokenSource.Cancel();
    cancellationTokenSource.Dispose();
};
```

What happens, end to end, when the window closes while the read is still running:

1. **Every way out cancels, OK included.** `Closed` is raised for OK, Cancel and the close box alike.
   That is intended: once the dialog is answered, nobody needs the decoration. Do not cancel only from
   the Cancel button.
2. **The client stops.** The window's token reaches the `Query` member, which links it to its timeout.
   Every `HttpClient.GetAsync` still running is abandoned, and requests still waiting for a throttling
   slot (§3) never start.
3. **Do not assume the server stops: as deployed, it does not (DiGi.GIS.WebAPI#77).**
   - Passing the token down is **necessary**. An endpoint that drops it keeps running its queries until
     `commandtimeout`. Check the controller when you add a read.
   - It is **not sufficient**. On 2026-11-07, `terrain/densitiesbycountyids` was measured on
     `api.digiproject.uk`. That endpoint passes its token all the way to `ExecuteReaderAsync`. A request
     whose client closed its socket at 4 s still went on loading the server for the rest of its run:
     a re-run took 18.9 s, against 14.1 s for a request alone and 20.5 s for two at once.
   - Until #77 is fixed, the time limit is what actually ends an abandoned query on the server. The
     server `commandtimeout` the `Query` member sends (§3) is that limit, so keep it no longer than the
     client wait.
   - Measure, do not read the code, before claiming that a close frees the server. The probe is in #77:
     the timing of a request alone, two at once, and a re-run straight after an explicit socket close.
4. **The `Query` member rethrows the cancellation.** It came from the caller's token, so the
   `catch (…) when (cancellationToken.IsCancellationRequested) { throw; }` filter lets it through rather
   than turning it into `null`.
5. **The window swallows it.** The read method returns before `SetX`, and its `finally` collapses the bar
   on the closed window, which is harmless. The status label and the items stay as they were. Nothing is
   logged, because a cancellation is not a failure.
6. **A result that arrives just as the window closes is dropped** by the `IsCancellationRequested` check
   after the `await` (§2.2). A closed window is never redrawn.
7. **The continuation still runs, later.** The tray application's dispatcher keeps running after
   `ShowDialog()` returns. The read method catches everything, so nothing is left unobserved.

Details that keep this correct:
- **Dispose after `Cancel`, in the same handler.** Before this, the source was cancelled and left for the
  finalizer, one per opened dialog. Disposing is safe because the read took `cancellationTokenSource.Token`
  synchronously in the constructor, and `IsCancellationRequested` still answers after `Dispose()`. Never
  read `.Token` after the window has closed: it throws `ObjectDisposedException`.
- **A cancellation can arrive as a different exception.** For example, an `HttpRequestException` from a
  connection torn down mid-response. The `Query` member's general `catch` then logs one spurious Warning and
  returns `null`. The window's `IsCancellationRequested` check still leaves it alone, so the only cost is
  that log line.

## 3. The read itself (`/Query/<Name>Async.cs`)

- A `Query` member, `public static async Task<T?> XAsync(…, CancellationToken cancellationToken = default)`,
  returning **`null` for every failure**:
  - unreachable server, error status, unparsable body, length mismatch, endpoint not available.
  - It logs a Warning for each of these and does not retry.
  - **Only the caller's own cancellation is rethrown**:
    `catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }`.
- **Bound it.**
  - Use a `CreateLinkedTokenSource(cancellationToken)` with `CancelAfter(timeout)`, and send the same
    number of seconds as the server's `commandtimeout`, so an abandoned query also stops on PostgreSQL.
  - Put the timeout in a `Constants` class, with a `<summary>` saying how it was measured.
- **Batch the requests.** A fixed number of requests for the whole list, sent together with
  `Task.WhenAll`, never one per item.
  - When an endpoint caps the batch size and the list needs many requests, throttle them with a
    `SemaphoreSlim` (`WaitAsync(token)`, `Release()` in `finally`). Keep the semaphore in a `using` that
    encloses the `await Task.WhenAll(…)`. `WhenAll` waits for every request to finish or cancel before it
    throws, so no `Release()` ever reaches a disposed semaphore. Reference:
    `Query/TerrainPointDensityResultsAsync.cs` (3 at a time).
  - Return `null` if **any** batch fails. A partial result leaves some items undecorated, which reads as
    "measured, nothing found".
- Prefer cheap sources for decoration: a planner estimate (`estimatedcounts…`) rather than `COUNT(*)`.
- No caching of the result (`Coding - General.md` §1.20). Each opening of the window reads afresh.

## 4. Failure semantics: unknown is not "no"

`null` from the read means **unknown**:
- nothing is marked;
- the status text says the data could not be read (for example "… could not be read - no county is marked").

Never fall back to an empty result: an empty dictionary renders exactly like "nothing has been done",
which is a false answer the operator will act on. The same holds for a value that is `null`, NaN or
missing for one item, which gets no decoration rather than a default.

## 5. Testing (xUnit facts, `Coding - Automatic Tests.md`)

Run each fact on an STA thread (`thread.SetApartmentState(ApartmentState.STA)`) and reach controls via
`window.FindName("…")`. Cover five cases:

| Case | Construct with | Assert |
|------|----------------|--------|
| No read | `xAsync: null` | bar `Collapsed`; status empty |
| Pending | `_ => new TaskCompletionSource<T?>().Task` | bar `Visible`; then `SetX(value)` → `Collapsed` |
| Completes at once | `_ => Task.FromResult<T?>(value)` | bar `Collapsed`; items decorated |
| Throws at once | `_ => Task.FromException<T?>(new InvalidOperationException())` | bar `Collapsed`; failure status; nothing decorated |
| Closed before data | a read that ends only when its token is cancelled; `window.Close()`; pump the dispatcher | token cancelled; bar `Collapsed`; status and items unchanged |

The **closed-before-data** fact (reference: `DiGi.Test/DiGi.GIS.PostgreSQL.UI.xUnit/Facts/OptionsWindows_CloseBeforeData.cs`,
one helper and one fact per window):
1. On the STA thread, first install the dispatcher context the application has:
   `SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher))`.
   Without it the window's `await` resumes on the thread pool, and the fact exercises a path the
   application never takes.
2. Construct with `token => { token.Register(() => taskCompletionSource.TrySetCanceled(token)); return taskCompletionSource.Task; }`,
   keeping the token.
3. `window.Close()`. This raises `Closed` on a window that was never shown. Assert that the token is cancelled.
4. Pump the posted continuation:
   `DispatcherFrame frame = new(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false)); Dispatcher.PushFrame(frame);`.
5. Assert that the bar is `Collapsed`, which only the `finally` can do here, and that the items and the
   status are unchanged, which proves `SetX` never ran.

Things a fact cannot do on that thread:
- **Never complete a pending task from the fact without pumping.** Its continuation is posted to a
  dispatcher the test thread does not pump, so it never runs. Either apply the result with the public
  `SetX`, or pump as in step 4 above.
- **Never show the window** (no `ShowDialog`). Keep modal message boxes and confirmations out of the
  window, in the caller (the background task), or a fact that clicks OK hangs.
- Layout cannot be measured on a window that was never shown, so check placement on screen once.

## 6. Traps checklist

| Symptom | Cause |
|---------|-------|
| The dialog opens late, or the whole UI freezes before it appears | The read is awaited before `ShowDialog()`, or run inside `Dispatcher.Invoke`. |
| `InvalidOperationException`: the calling thread cannot access this object | `ConfigureAwait(false)` in the window's read method. |
| The progress bar keeps spinning after the data shows or after closing | The bar is hidden only on the success path. Hide it in `finally`. |
| The selection is lost when the data arrives | The list was re-set instead of refreshed. |
| Every item reads as "not done" after a network error | A failed read was turned into an empty result instead of `null`. |
| The server keeps running a query after the window closed | The token was not passed to the request, or the controller does not pass its `CancellationToken` to the converter. **As deployed, it also happens when both are right** (DiGi.GIS.WebAPI#77). Until that is fixed, only the server `commandtimeout` ends the query, so keep it no longer than the client wait. |
| The read keeps running after OK | Cancellation hangs off the Cancel button instead of `Closed`. |
| `ObjectDisposedException` after the window closed | `.Token` read from the disposed source. Take the token once, when the read starts. |
| A Warning "could not be read" logged when a dialog was closed | A cancellation that surfaced as `HttpRequestException`. Harmless (§2.5), and not a failed read. |
| A closed-before-data fact passes without testing anything, or hangs | No `DispatcherSynchronizationContext` installed (the continuation runs on the thread pool), or the dispatcher is never pumped. |
| A fact hangs | A modal box inside the window, or a fact awaiting a continuation on an unpumped dispatcher. |
