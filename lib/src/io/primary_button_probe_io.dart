/// Hardware primary-mouse-button probe for desktop platforms.
///
/// A platform view (e.g. a WebView) that takes the OS mouse capture can swallow
/// the pointer-up so it never reaches Flutter, stranding a splitter drag. When
/// the framework can't observe the release, the only authority left is the OS
/// itself: poll the physical button state and end the drag when it lifts.
///
/// This reads the *current physical* state (not a timeout), so a user holding
/// the button motionless keeps dragging for as long as they like.
library;

import 'dart:ffi';
import 'dart:io';

/// Returns a probe that reports whether the physical primary mouse button is
/// held, or `null` on a platform without one (so the watchdog stays off).
bool Function()? createPrimaryMouseButtonProbe() {
  try {
    if (Platform.isMacOS) return _macOSProbe();
    if (Platform.isWindows) return _windowsProbe();
  } on Object {
    // Any failure to bind the native symbol degrades gracefully to "no probe".
    return null;
  }
  return null;
}

// macOS: CoreGraphics.
//   bool CGEventSourceButtonState(CGEventSourceStateID stateID,
//                                 CGMouseButton button);
// kCGEventSourceStateHIDSystemState = 1 (the actual hardware state),
// kCGMouseButtonLeft = 0.
typedef _CGButtonStateNative = Bool Function(Uint32, Uint32);
typedef _CGButtonStateDart = bool Function(int, int);

bool Function()? _macOSProbe() {
  // CoreGraphics is already loaded into every Flutter macOS process, so the
  // symbol is reachable through the current process; fall back to opening the
  // framework explicitly (e.g. a pure-Dart host) if it is not.
  DynamicLibrary library;
  try {
    final process = DynamicLibrary.process();
    process.lookup<NativeFunction<_CGButtonStateNative>>(
      'CGEventSourceButtonState',
    );
    library = process;
  } on Object {
    library = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
  }
  final buttonState = library
      .lookupFunction<_CGButtonStateNative, _CGButtonStateDart>(
        'CGEventSourceButtonState',
      );
  return () => buttonState(1, 0);
}

// Windows: user32.
//   SHORT GetAsyncKeyState(int vKey);  // high bit set => currently down
// VK_LBUTTON = 0x01. (The OS already maps a swapped primary button to the
// logical left button for VK_LBUTTON.)
typedef _GetAsyncKeyStateNative = Int16 Function(Int32);
typedef _GetAsyncKeyStateDart = int Function(int);

bool Function()? _windowsProbe() {
  final user32 = DynamicLibrary.open('user32.dll');
  final getAsyncKeyState = user32
      .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
        'GetAsyncKeyState',
      );
  const vkLButton = 0x01;
  return () => getAsyncKeyState(vkLButton) & 0x8000 != 0;
}
