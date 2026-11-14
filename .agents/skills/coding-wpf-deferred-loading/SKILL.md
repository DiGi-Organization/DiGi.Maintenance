---
name: coding-wpf-deferred-loading
description: "Use when a WPF window or dialog needs slow data, or when checking WPF layout without its host - open at once, background read, progress bar, cancel on Closed, null means unknown, STA facts, off-screen render harness."
---

# AI Guidelines: WPF Deferred Loading (slow data in a window or dialog) & WPF Test Harnesses

Default for a WPF window or dialog needing slow data: **open at once, read in the background, show that it is loading
(status text + indeterminate progress bar, bottom-left), fill in place when it arrives.** A failed read says so and never
pretends to be an answer. Reference (workspace-relative):
`DiGi.GIS.PostgreSQL.UI/DiGi.GIS.PostgreSQL.UI/Windows/YearBuiltPredictionsOptionsWindow.xaml(.cs)`, fed by
`Query/PredictedYearBuiltCoverageFactorsAsync.cs`, opened by `Classes/BackgroundTask/UIYearBuiltPredictionsTask.cs`; facts
`DiGi.Test/DiGi.GIS.PostgreSQL.UI.xUnit/Facts/YearBuiltPredictionsOptionsWindow_Coverage*.cs` (DiGi.GIS.PostgreSQL.UI#40).

## Checklist
Read this first; open a section only when its line applies to the change (§6 maps a symptom to its cause).
- Essential data is read before the window opens (not inside `Dispatcher.Invoke`); decoration or slow data is deferred; fast bounded data inline (§1).
- The constructor takes the read as a `Func<CancellationToken, Task<T?>>?` delegate and starts it without awaiting; a public `SetX(T? x)` applies the result (§2.1).
- No `ConfigureAwait(false)` in the window; hide the bar in `finally` as well as in `SetX` (§2.2).
- Bar bottom-left `Collapsed` in markup, a status label near the data, controls never disabled (§2.3); refresh the items, never re-set the list (§2.4).
- `Closed` cancels and disposes the token source — every way out, OK included; the server stops only at its `commandtimeout`, so keep it ≤ the client wait (§2.5).
- The `Query` read returns `null` for every failure, is bounded by a linked timeout, batches with `Task.WhenAll`, rethrows only the caller's cancellation (§3).
- `null` = unknown: nothing marked and the status says so — never an empty result (§4).
- STA facts for no read, pending, completes, throws, closed-before-data; install a `DispatcherSynchronizationContext` and pump; never `ShowDialog` (§5).
- Layout without the host: off-screen render harness, walk the visual tree as well as the screenshot (§7).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
