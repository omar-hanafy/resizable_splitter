# Native macOS Splitter Demo - Design

Status: approved (design)
Date: 2026-06-23

## Summary

Add one example that showcases `ResizableSplitter` doing a sidebar-to-content
resize inside authentic macOS chrome, using `macos_ui ^2.2.2`
(`MacosWindow` -> `MacosScaffold` -> real `ToolBar`). It demonstrates the
`StickySnap` detents and a collapsible sidebar driven by the package's
`SplitterController`.

The macos_ui storybook screenshot was the inspiration, but reproducing that UI is
explicitly out of scope. The subject is the splitter and the native feel; the
start/end pane contents are deliberately minimal-but-native placeholders.

This is example-only work. The `resizable_splitter` library is not touched, so the
demo doubles as a real-consumer stress test of the public API.

## Goals

- Prove `ResizableSplitter` drops cleanly into a native-feeling macOS layout.
- Exercise `StickySnap` detents and `SplitterController` collapse/expand through
  the public API exactly as a consumer would.
- Keep the existing Material gallery intact; reach the native screen from it.
- No changes to the published package.

## Non-goals (deferred)

- Reproducing the macos_ui storybook content (CapacityIndicator, RatingIndicator,
  the full Indicators page, etc.). Pane content stays placeholder-grade.
- The modern transparent window chrome (transparent titlebar, wallpaper tinting).
  That needs native `MainFlutterWindow.swift` setup plus
  `WindowManipulator.initialize()` and is not warranted for an embedded demo.
- A 3-column layout (nested splitters).
- Any library/API change in `resizable_splitter`.

## Decisions (locked)

- Look: real `macos_ui ^2.2.2` chrome.
- Native root: a full-screen route launched from the existing gallery. The gallery
  stays a `MaterialApp`; the native screen is pushed and rooted under `MacosTheme`.
- Snap: `StickySnap` detents.
- Placement: a new entry in the existing example gallery.
- Pane content: minimal-but-native placeholders.

## Architecture

```
Gallery (MaterialApp, unchanged)
  list entry "Native macOS"  -> end pane shows a launcher card
        |
        | PushButton -> Navigator.of(ctx, rootNavigator: true).push(fullscreen route)
        v
MacosTheme(data: light/dark)              // the only ancestor macos_ui layout needs
  └─ MacosWindow(sidebar: null, titleBar: null)
       └─ MacosScaffold(
            toolBar: ToolBar(
              leading: MacosBackButton -> rootNavigator.pop(),
              title: Text('ResizableSplitter | macOS'),
              actions: [ collapse-sidebar toggle, light/dark toggle ],
            ),
            children: [ ContentArea(builder: (ctx, _) => <the splitter>) ],
          )

<the splitter> =
  LayoutBuilder(                            // measures available main extent
    ResizableSplitter(
      axis: Axis.horizontal,
      controller: _controller,
      startConstraints: SplitterPaneConstraints(
        minExtent: 200, maxExtent: 360, collapsedExtent: 0),
      snap: <StickySnap derived from pixel detents, see below>,
      divider: <macOS hairline style>,
      start: <MacosScrollbar + a few SidebarItems incl. one section header>,
      end:   <MacosScrollbar + a small native page>,
    ))
```

The full-width `ToolBar` over a sidebar|content split is the Xcode-style macOS
layout. No nested `MacosApp`; no `macos_window_utils` initialization.

## Components

### A. Gallery entry + launcher (`example/lib/main.dart`)

- Add one `_Demo` entry titled "Native macOS".
- Its end-pane builder renders a small launcher card: a short description plus a
  `PushButton` ("Open full-screen demo") that pushes the native route via the root
  navigator (`fullscreenDialog: true`). This keeps the gallery's
  selected-demo-in-pane model intact while still delivering a full-screen native
  experience.

### B. Native screen (`example/lib/native_macos_sidebar_demo.dart`, new)

- A `StatefulWidget` that owns a `SplitterController` (disposed in `dispose`) and a
  `brightness`/sidebar-collapsed bit of UI state.
- Builds the `MacosTheme -> MacosWindow -> MacosScaffold -> ToolBar + ContentArea`
  skeleton above.
- Keeping it in its own file isolates ~200 lines of demo from the 1150-line
  `main.dart` and keeps each unit focused.

### C. Splitter configuration

- `controller: SplitterController(initialPosition:
  SplitterPosition.startPixels(280))` - pins the sidebar to 280 px initially (the
  middle detent).
- `startConstraints: SplitterPaneConstraints(minExtent: 200, maxExtent: 360,
  collapsedExtent: 0)` - the `collapsedExtent` is what enables collapse.
- Collapse toggle in the `ToolBar` calls
  `controller.toggleCollapse(SplitterPane.start)` (collapse if open, expand if
  collapsed).
- `SplitterDividerStyle` tuned to a macOS hairline: thin visible thickness, a
  larger invisible `interactiveExtent` grab slop, and a state-dependent `color`
  sourced from `MacosTheme.of(context).dividerColor`.

### D. Panes (minimal, native)

- start: `MacosScrollbar` wrapping a `SidebarItems` with a handful of `SidebarItem`s
  including one `section: true` header, so it reads as a real macOS sidebar.
- end: `MacosScrollbar` wrapping a simple native page - a title plus a couple of
  `PushButton` / `MacosSwitch` / `MacosSlider` widgets. Clearly placeholder.

### E. Detent strategy

`StickySnap.points` are start fractions in `[0, 1]`, but a sidebar wants
fixed-pixel detents. So:

- Wrap the splitter in `LayoutBuilder` to read the available main extent.
- Convert each target width (220 / 280 / 340 px) to `targetPx / availableExtent`
  and build the `StickySnap` from those fractions, rebuilding it when the extent
  changes.
- Use `pixelTolerance` for a size-independent catch radius.

This makes detents feel fixed-size and doubles as the on-screen demonstration of
the documented fraction-vs-pixel snap workaround.

### F. Light/dark and platform

- Brightness defaults from `MediaQuery.platformBrightness`, with a `ToolBar` toggle
  to flip `MacosThemeData.light()` / `.dark()`.
- Shown on all platforms (macos_ui renders cross-platform); the native feel is best
  on macOS.

## Verified macos_ui 2.2.2 API facts

Confirmed by reading `~/.pub-cache/hosted/pub.dev/macos_ui-2.2.2`:

- `MacosWindow`, `MacosScaffold`, `ToolBar`, `SidebarItems`, `MacosScrollbar`
  require only a `MacosTheme` ancestor. No `MacosLocalizations.of` calls exist in
  `lib/src/layout`; `scaffold.dart` has no `MacosWindowScope` dependency; so a full
  `MacosApp` is not required.
- `macos_app.dart` does not call `WindowManipulator`, so embedding does not force
  native `macos_window_utils` initialization.
- `ContentArea({required ScrollableWidgetBuilder? builder, double minWidth = 300})`;
  the builder is `(BuildContext, ScrollController)`.
- `SidebarItems({required items, required currentIndex, required onChanged,
  itemSize, scrollController, ...})`.
- `SidebarItem(required label, leading?, section: bool? (true = unclickable
  header), disclosureItems?, expandDisclosureItems, trailing?, ...)`.
- `ToolBar({height, title?, leading?, automaticallyImplyLeading = true, actions?,
  centerTitle = false, ...})`.
- `MacosWindow({child?, titleBar?, sidebar?, endSidebar?, backgroundColor?, ...})`.
- `MacosThemeData.light()` / `.dark()`; `MacosThemeData({required brightness, ...})`.
- macos_ui 2.2.2 depends on `macos_window_utils ^1.9.0` (macOS-only native);
  requires Flutter `>=3.35.0`, Dart `>=3.9.2` (example SDK is `^3.9.2`, compatible).

## resizable_splitter API used (public surface)

- `ResizableSplitter(start, end, axis, controller, startConstraints, snap, divider,
  ...)`.
- `SplitterController(initialPosition:)` with `collapse(SplitterPane)` /
  `expand()` / `toggleCollapse(SplitterPane)`.
- `SplitterPaneConstraints(minExtent, maxExtent, collapsedExtent)`.
- `SplitterSnapBehavior.sticky(points, tolerance, pixelTolerance?, escapeFactor)`.
- `SplitterPosition.startPixels(...)` / `SplitterPosition.fraction(...)`.
- `SplitterDividerStyle(thickness, interactiveExtent, color, builder)`.

## Files changed

- `example/pubspec.yaml` - add `macos_ui: ^2.2.2`.
- `example/lib/main.dart` - one `_Demo` entry plus a launcher card (~30 lines).
- `example/lib/native_macos_sidebar_demo.dart` - new: the route screen, sidebar
  widget, content widget, detent logic, controller lifecycle.

## Testing and verification

- Widget test in `example/test/`: open the native route, find `ResizableSplitter`
  and `SidebarItems`; simulate a divider drag and assert the start pane width
  changes; tap the collapse toggle and assert collapse then expand; release a drag
  near a detent and assert it settles there.
- `dart analyze` (example scope) clean.
- Run the example on macOS to confirm the native feel.

## Contingencies

- If any chosen macos_ui widget turns out to need `MacosLocalizations`, wrap the
  route subtree in a `Localizations` with the macos delegate (or nest `MacosApp`).
  The planned widget set (window/scaffold/toolbar/sidebar/scrollbar/buttons/switch/
  slider) needs only `MacosTheme`.
- If `macos_window_utils` breaks non-macOS builds of the example, gate the gallery
  entry to macOS, mirroring the existing `_supportsPlatformViewDemo` gate.
