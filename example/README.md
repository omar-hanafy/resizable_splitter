# resizable_splitter - interactive showcase

A single-page, instrument-style demo for the
[`resizable_splitter`](https://pub.dev/packages/resizable_splitter) package. It is
built **entirely out of the package** - every divider on the page, including the
chrome, is a live `ResizableSplitter`.

**[Live demo](https://omar-hanafy.github.io/resizable-splitter/)**

## The idea

The package's thesis is *store the intent, resolve every frame*: you keep a
**request** (a fraction or a pixel pin), and a pure constraint solver resolves it
into on-screen geometry every layout pass. The showcase makes that duality
visible - the hero pits the **request** channel (a dashed "ghost" you can drive
past the legal band) against the **result** channel (the divider the solver
actually draws), with a live readout and a band meter in between.

## What it tours

| # | Section | Demonstrates |
|---|---------|--------------|
| - | Hero "Live solver" | request vs. result readout, the request-ghost, the legal-band meter, resolution badge, pixel pins, `animateTo` |
| 01 | Position model | a pixel pin holding its width vs. a fraction holding its ratio as the container resizes |
| 02 | Constraints & policies | per-pane min/max, `constraintPolicy` (shortage), `surplusPolicy` incl. `leaveGap` rendering a real gap |
| 03 | Snapping | `release` / `magnetic` / `sticky` modes against shared detents |
| 04 | Collapse & animate | collapse with restore, `toggleCollapse`, vsync `animateTo` |
| 05 | Composition | nested splitters forming an IDE (pinned explorer + editor/terminal) |
| 06 | Accessibility | keyboard (arrows / page / home-end), slider semantics, RTL, double-tap reset |
| 07 | Get started | install + the minimum usage |

## Run it

```bash
cd example
flutter run -d chrome      # web (the primary target)
flutter run                # or any connected device / desktop
```

The app is pure Flutter (no platform plugins beyond `url_launcher` for the
header links), so it runs on web, desktop, and mobile from one codebase.

```bash
flutter test               # smoke tests across desktop / tablet / mobile widths
flutter build web --base-href /resizable-splitter/   # production build
```

## Code map

```
lib/
  main.dart              app shell, theme toggle, sections, scroll reveal
  theme/
    tokens.dart          AppTokens (semantic colors as a ThemeExtension), spacing, type
    app_theme.dart       ThemeData + ColorScheme + the package's ResizableSplitterThemeData
  widgets/
    hero_solver.dart     the live solver: request-ghost overlay, readout, intent controls
    band_meter.dart      the legal-band instrument
    instrument.dart      shared kit (panels, badges, painters, brand mark, segmented toggle)
    code_block.dart      copyable, lightly-highlighted code
    lab_station.dart     the section/demo-stage scaffold
    top_bar.dart         the pinned header
  stations/              one file per capability (01-06)
  data/sample.dart       realistic pane content (file tree, editor, terminal, nav)
assets/fonts/            bundled variable fonts (Bricolage Grotesque, Hanken Grotesk, JetBrains Mono)
```

## Design notes

- **Palette**: a graphite "drafting table" with one bold amber signal for the
  *resolved* channel and a muted slate for the *intent* channel - the two colors
  encode the package's two channels, not decoration.
- **Type**: Bricolage Grotesque (display), Hanken Grotesk (UI), JetBrains Mono
  (the instrument readouts), all bundled so the GitHub Pages build is
  self-contained with no font flash.
- Light and dark themes are designed together; the toggle lerps the whole palette
  and swaps the package's `ResizableSplitterThemeData`.
