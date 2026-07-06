import 'package:flutter/widgets.dart';

/// Non-web variant of the platform-view input interceptor: a pure
/// pass-through.
///
/// On non-web targets the splitter's platform-view shielding works by
/// PAINTING (see `_shieldBaseColor` in `split_handle.dart`): the OS routes
/// pointer input above a platform view to Flutter wherever a later Flutter
/// layer actually paints, so no extra element is needed - and on iOS, where
/// painting is not enough either, no DOM equivalent exists to mount (a native
/// interceptor would need an iOS-only plugin dependency, which would cost the
/// package its other platform tags on pub.dev; see the web variant's note).
///
/// The web variant (selected by the `dart.library.js_interop` conditional
/// import in `resizable_splitter.dart`) mounts a real DOM element instead.
class WebPlatformViewInterceptor extends StatelessWidget {
  /// Wraps [child]; on this (non-web) target it changes nothing.
  const WebPlatformViewInterceptor({required this.child, super.key});

  /// The subtree to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
