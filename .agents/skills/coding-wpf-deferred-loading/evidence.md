# Evidence: Coding - WPF Deferred Loading.md

Incidents, measurements and history behind the rules of [Coding - WPF Deferred Loading.md](../Coding%20-%20WPF%20Deferred%20Loading.md),
keyed by its section numbers. Read only when a rule is disputed or being changed; the rule itself lives in the guideline.

## §2.5 Closing before the data arrives: does the server stop?

### Symptom (DiGi.GIS.WebAPI#77, 2026-11-07)
`terrain/densitiesbycountyids` passed its token down to `ExecuteReaderAsync`, yet a request whose socket was closed at
4 s kept loading the server. Measured on `api.digiproject.uk` with one 50-part batch, `commandtimeout=300`, warm cache:

| Situation | Time |
|---|---|
| Alone | 14.2, 14.0, 14.2, 13.8, 14.7 s (≈14.1 s) |
| Two identical requests at once | 20.5, 20.4 s |
| Re-run straight after a request shut down and closed at 4 s | 18.9, 19.0 s |

18.9 s matches "the aborted request ran on for its remaining ~10 s" (≈ 14 + 10/14 × 6.4 s), not "it stopped" (≈14 s).
Until the cause was fixed, the guideline told the dialogs to rely on the server `commandtimeout` alone.

### Cause (DiGi.GIS.WebAPI#92, 2026-11-17)
The local `RequestAborted` facts (`DiGi.WebAPI.WindowsService.xUnit`) cancelled within 1 s, so the host was not at
fault. On production a temporary `requestabortedprobe` action awaited `Task.Delay(60 s, token)`. A raw TLS client closed
its socket at 2 s, and the probe logged `completed after 60010.7691 ms without cancellation` (also 59997.7081 and
120005.1212 ms).

A connection sampler on the database server showed every client connection arriving from the LAN reverse proxy, an
**Apache 2.4.68 `mod_proxy_http`** on a Raspberry Pi. The aborted client's upstream connection stayed `Established` for
the whole remaining sampling window. Apache does not watch the client while it waits for the backend, so Kestrel was
never told. Apache forwarded the upstream `Server: Kestrel` header unchanged, which is why #77 believed nothing sat in
between.

### Fix and re-measure (#92, 2026-11-17)
nginx 1.22.1 replaced Apache on 80/443. Its default `proxy_ignore_client_abort off` closes the upstream connection when
the client aborts. The probe then logged `cancelled after 1964.4043 ms` and `1962.4779 ms`, about 0.05 s after the close.

`densitiesbycountyids`, run through nginx with the first 50 of 406 county ids and `commandtimeout=300`:

| Situation | Time | Server phase log |
|---|---|---|
| Alone | 13.05, 13.39, 12.42 s | `cancelled false` |
| Aborted at 4 s | — | total 4099.8 / 4015.1 ms, `cancelled true` (~0.1 s after the close) |
| Re-run straight after the abort | 12.99, 11.48 s | `cancelled false` |

H2 (uncancellable work) and H3 (Npgsql cancel not reaching PostgreSQL) were not causes: the cancellation exited through
`catch (OperationCanceledException)` with no Error, and the re-runs carried no leftover load.
