/// Fallback used on platforms without `dart:io` (notably the web), where there
/// is no hardware button to poll. The conditional import in the splitter library
/// swaps in the `dart:io`/`dart:ffi` implementation on native platforms.
///
/// Returns `null` to mean "no probe available", so the drag watchdog simply does
/// not run.
library;

/// Creates a probe that reports whether the physical primary mouse button is
/// currently held, or `null` when the platform offers no such probe.
bool Function()? createPrimaryMouseButtonProbe() => null;
