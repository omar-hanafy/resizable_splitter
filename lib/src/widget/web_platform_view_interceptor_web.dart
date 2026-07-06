import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web variant of the platform-view input interceptor: mounts an invisible
/// DOM `<div>` platform view *underneath* [child] (in Flutter paint order) so
/// that pointer events over the wrapped area land on that div - which bubbles
/// them up to the Flutter engine - instead of falling through to a platform
/// view's `<iframe>`, which would swallow them (events inside an iframe never
/// reach the surrounding document, so Flutter never sees them; painting above
/// the iframe does not help on web because a canvas paint is not a DOM hit
/// target for content beneath it).
///
/// This is a minimal port of `package:pointer_interceptor_web` 0.10.3 (BSD,
/// the Flutter Authors). It is inlined behind a web-only conditional import
/// instead of depending on `package:pointer_interceptor`, because that plugin
/// declares only `ios` + `web` platform support and taking it as a dependency
/// drops this package's `android`/`windows`/`linux`/`macos` platform tags on
/// pub.dev (verified with pana). `package:web` is a plain JS-interop library
/// with no platform declarations, so it carries no such cost.
class WebPlatformViewInterceptor extends StatelessWidget {
  /// Wraps [child] with a DOM element that keeps pointer events over the
  /// wrapped area out of neighboring iframe platform views.
  const WebPlatformViewInterceptor({required this.child, super.key});

  /// The subtree to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            // The div renders nothing; telling the engine so lets it skip the
            // overlay-surface splitting a visible platform view would force.
            isVisible: false,
            onElementCreated: (Object element) {
              // Prevent the default action of `mousedown` events so a press on
              // the interceptor does not steal DOM focus from the active
              // element (same behavior as pointer_interceptor_web).
              (element as web.HTMLElement).addEventListener(
                'mousedown',
                (web.Event event) {
                  event.preventDefault();
                }.toJS,
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}
