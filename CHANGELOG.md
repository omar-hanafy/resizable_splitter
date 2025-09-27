# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.1

- Refined drag coalescing, semantics percentages, and anti-alias minima handling.

## 1.1.0

- Theming refresh: `ResizableSplitterTheme` plus a `ThemeExtension` drive divider styling, keyboard steps, overlays, and
  unbounded policies.
- Layout policies: `UnboundedBehavior` (`LimitedBox` opt-in), `CrampedBehavior`, and `antiAliasingWorkaround` for crisp
  panes.
- Interactions: `resizable` toggle, `onHandleTap` / `onHandleDoubleTap`, and controller multi-attach guard.
- Fixed precedence so per-instance constructor arguments override themed switches.
- Tests expanded to cover new theming, policies, and interaction paths.

## 1.0.0

- Initial release of `ResizableSplitter` with drag-to-resize layouts.
- Keyboard navigation, screen-reader semantics, and customizable divider styling.
- `SplitterController` for programmatic control and testing.
