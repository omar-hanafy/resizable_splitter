part of 'resizable_splitter.dart';

/// The resolved-layout observable behind [SplitterController.layoutListenable].
///
/// Its value updates synchronously (via [prime], during the splitter's build,
/// so read-outs are fresh in the same frame) while the listener notification is
/// deferred to [flush] (post-frame), so publishing the layout can never trigger
/// a listener's `setState` during build.
class _SplitterLayoutNotifier extends ChangeNotifier
    implements ValueListenable<SplitterLayout?> {
  SplitterLayout? _value;
  bool _dirty = false;

  @override
  SplitterLayout? get value => _value;

  /// Sets [next] immediately; returns true if it changed (so the caller knows a
  /// [flush] should be scheduled).
  bool prime(SplitterLayout? next) {
    if (_value == next) return false;
    _value = next;
    _dirty = true;
    return true;
  }

  /// Notifies listeners once if the value changed since the last flush.
  void flush() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }
}
