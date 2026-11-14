---
name: coding-browser-testing
description: "Use when verifying interactive front-end behaviour in a real browser - Playwright, toggles, drag-resize, keyboard, localStorage, phone layouts, rendered output by screenshot statistics; host shell only."
---

# AI Guidelines: Browser Testing (Interactive DoD)

Verify *interactive* front-end behaviour — panel toggles, drag-resize with clamps, keyboard operability, `localStorage`
persistence, responsive stacking, shared header/footer collapse, visual effects — in a real browser rather than by reading
code. Not for server-side C# logic (xUnit) or a one-off "does it render" check (`curl` is enough). WPF counterpart:
`Coding - WPF Deferred Loading.md` §7.

## 1. Confirm the toolchain on THIS machine first
Availability is per machine; observed versions are one machine's state, not a requirement.
- Python + pip (`python --version`, `pip --version`).
- Playwright for Python (`python -m pip show playwright`; install with `python -m pip install playwright` — no Node.js
  needed). `playwright.__version__` does not exist; use `pip show`.
- A Chromium browser: Edge `channel="msedge"`, Chrome `channel="chrome"`, or `python -m playwright install chromium`.
```
python -c "from playwright.sync_api import sync_playwright; p=sync_playwright().start(); b=p.chromium.launch(channel='msedge', headless=True); b.close(); p.stop()"
```
If the launch fails, try the next channel, else install Chromium. Headless by default.

## 2. Run with the host shell, never an isolated sandbox
A sandboxed interpreter has no host filesystem, network or `localhost`, so it can neither start nor drive the app. Keep
the script and screenshots in the scratchpad.

## 3. Recipe
1. Start the app from its build output (the folder with `<App>.dll` and `wwwroot/`): `dotnet <App>.dll` with
   `ASPNETCORE_ENVIRONMENT=Development`, `ASPNETCORE_URLS=http://localhost:<port>`.
2. Poll a cheap endpoint until 200 (bounded) before opening the browser.
3. `page.goto(url, wait_until="networkidle")`.
4. Drive: `page.click(...)`, `page.keyboard.press("Enter" | "Space")`, `page.mouse.move/down/up` in steps for drag-resize.
5. Assert computed styles (`getComputedStyle`), `get_attribute(sel, "aria-expanded")`, `localStorage.getItem(key)`, and no
   horizontal overflow (`document.documentElement.scrollWidth <= window.innerWidth`).
6. `page.set_viewport_size({...})` for breakpoints — including a phone (375×812, §4); `page.screenshot(...)` for a look.
7. **Terminate the server in `finally`.**

## 4. Gotchas
- **A collapsed-by-default panel measures 0** (`display:none`) — open it, then measure; the `localStorage` value is the
  source of truth. Folded side-panel cards (`.gltf-card-collapsed`) cannot be clicked into either — a `Locator.click` on a
  checkbox inside times out like a missing control; click `.gltf-card-title` first.
- **Drag with `page.mouse` steps**, not a one-shot `.drag_to()` (the handlers listen for real `mousemove`/`mouseup`).
- **Settle before asserting** — a short `page.wait_for_timeout(...)` after a toggle that re-fits on `resize` or a transition.
- **Rebuild before re-verifying a `.cshtml` change** — Razor views compile at build time; CSS/JS serve live from `wwwroot`
  (except files a build copies in, `Coding - General.md` §3).
- **The `hidden` attribute loses to any `display` rule:** `.typology-viewport-empty { display:flex }` keeps a "hidden",
  transparent overlay swallowing every click on the map. Components that set `display` on a `hidden`-toggled element need
  `[hidden] { display:none; }`. Symptom: clicks landing on nothing, no console error — check `document.elementFromPoint(x, y)`.
- **Phone size (375×812) has its own traps** (bodyplan #123, #125): `100vh` is taller than the visible area — use `100dvh`
  plus safe-area padding; a fixed negative margin clips content under an `overflow:hidden` body; an absolutely positioned
  hidden input with no positioned ancestor scrolls the page to a blank screen when tapped.

## 5. Verify rendered output, not state
On DiGi.GIS.WebAPI.UI#43 every state assertion (`renderer.shadowMap.enabled`, `light.castShadow`, `getEnvironmentState()`)
passed while no shade had ever reached the screen; only a screenshot statistic could have failed.
- **Assert a pixel statistic:** crop `page.screenshot()` (PIL + numpy) and compare mean luminance — off must differ from on
  beyond the noise floor, on → off → on must restore within ~1 unit. A WebGL canvas cannot be read through `toDataURL`
  without `preserveDrawingBuffer`, but the compositor screenshot always works.
- **A per-pixel minimum across parameter values isolates parameter-independent artefacts:** the same pose under three sun
  positions and effect-off, `min(off - shot_i)` — whatever remains darkens under *every* value (it exposed the winding bug).
- **GPU cost is not rAF cadence** (that is CPU submit time): wrap `renderer.render` in `EXT_disjoint_timer_query_webgl2`
  (`beginQuery`/`endQuery`, drain on `QUERY_RESULT_AVAILABLE`, discard on `GPU_DISJOINT_EXT`), launch **headed** with
  `--disable-frame-rate-limit --disable-gpu-vsync`. Headless `--use-angle=swiftshader` gives unusable numbers. On a fast GPU
  report the ranking between variants, not absolutes.

## 6. DoD → assertion map
| Interactive DoD item | Assertion |
|---|---|
| Panel open/closed default | `offsetWidth > 0` vs `display === none`, plus `aria-expanded` |
| Toggle flips state | click → `aria-expanded` flips, modifier class toggles, resizer shows/hides |
| Drag-resize with clamp | `page.mouse` drag → width within min/max, `localStorage` key set |
| Widths persist across reload | reload → (open if default closed) → width restored from `localStorage` |
| Keyboard operable | `focus()` + `keyboard.press("Enter")`/`("Space")` → state toggles |
| Responsive stacking | `set_viewport_size(<1100px)` → `flex-direction: column`, resizers `display:none`, no overflow |
| Phone layout | 375×812 → nothing clipped, inputs tap without scrolling the page |
| Shared header/footer collapse | layout toggle → `body` class toggles, viewport height grows |
| Visual effect on/off | region luminance differs across the toggle and restores (§5) |
