// ignore_for_file: use_setters_to_change_properties
part of 'resizable_splitter.dart';

/// Internal widget for the draggable divider handle.
class _DividerHandle extends StatefulWidget {
  const _DividerHandle({
    required this.axis,
    required this.controller,
    required this.thickness,
    required this.geometryListenable,
    required this.dividerColor,
    required this.dragBarrierColor,
    required this.dragBarrierBuilder,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    required this.enableKeyboard,
    required this.enableHaptics,
    required this.keyboardStep,
    required this.pageStep,
    required this.focusNode,
    required this.semanticsLabel,
    required this.semantics,
    required this.shieldPlatformViews,
    required this.snap,
    required this.handleBuilder,
    required this.holdScrollWhileDragging,
    required this.interactiveSlop,
    required this.doubleTapResetTo,
    required this.resizable,
    this.onTap,
    this.onDoubleTap,
    this.deferred = false,
    this.onPreviewChanged,
    required this.localMainAxisOf,
  });

  final Axis axis;
  final SplitterController controller;
  final double thickness;

  /// The resolved geometry the render object published from its last layout
  /// pass, or null before the first layout / while detached (the handle then
  /// falls back to the controller's published layout). Event handlers read this
  /// live, so a drag, key press, or assistive action is never a frame stale; the
  /// build listens to it so the rendered semantics track a container resize that
  /// leaves the request unchanged.
  final ValueListenable<_ResolvedSplitterGeometry?> geometryListenable;
  final WidgetStateProperty<Color?>? dividerColor;
  final Color? dragBarrierColor;
  final Widget Function(BuildContext context)? dragBarrierBuilder;
  final ValueChanged<SplitterChangeDetails>? onChanged;
  final ValueChanged<SplitterChangeDetails>? onChangeStart;
  final ValueChanged<SplitterChangeDetails>? onChangeEnd;
  final bool enableKeyboard;
  final bool enableHaptics;
  final double keyboardStep;
  final double pageStep;
  final FocusNode focusNode;
  final String? semanticsLabel;
  final SplitterSemanticsLabels semantics;
  final bool shieldPlatformViews;
  final SplitterSnapBehavior? snap;
  final Widget Function(BuildContext, SplitterHandleDetails)? handleBuilder;
  final bool holdScrollWhileDragging;

  /// Overhang on each side of the visible bar that the catcher overlays onto the
  /// panels (half of `interactiveExtent - thickness`, zero when not resizable).
  final double interactiveSlop;
  final double? doubleTapResetTo;
  final bool resizable;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Whether to defer the resize until release, tracking the drag with a preview
  /// line instead of resizing the panes every frame.
  final bool deferred;

  /// Reports the live preview fraction during a deferred drag (null on release).
  final ValueChanged<double?>? onPreviewChanged;

  /// Maps a global pointer position to the splitter's local main-axis
  /// coordinate so drag math is transform-safe. Returns null if unavailable.
  final double? Function(Offset globalPosition) localMainAxisOf;

  @override
  State<_DividerHandle> createState() => _DividerHandleState();
}

class _DividerHandleState extends State<_DividerHandle> {
  // The active drag, or null when not dragging. A single nullable field is the
  // whole drag state machine: `_session != null` means dragging, and the
  // terminal [_endDrag] claims it before any user code, so a cancel, a
  // reconfiguration, a disposal, the router backup, or a throwing callback can
  // never double-fire, snap on a cancel, or strand the controller.
  _DragSession? _session;
  bool get _isDragging => _session != null;
  // MouseRegion covers the full grab target, including transparent slop over
  // the panes. Store the local pointer position and derive visual hover from
  // the visible bar bounds so hidden slop can grab without painting as hover.
  Offset? _hoverLocalPosition;
  // Whether the keyboard focus highlight should show. Driven by
  // FocusableActionDetector.onShowFocusHighlight and the splitter's own input
  // modality tracking, so pointer-acquired focus can still receive arrow keys
  // without painting a stale keyboard focus affordance.
  bool _isFocused = false;
  bool _suppressFocusHighlightUntilKeyboard = false;
  // Set when a PointerCancelEvent arrives for the active drag pointer. Flutter's
  // drag recognizer reports BOTH a normal release and a mid-drag cancel through
  // onEnd, so this flag - set by the Listener, which sees the raw cancel before
  // the recognizer's onEnd - is what lets _onDragEnd tell them apart so a cancel
  // never snaps or fires a successful onChangeEnd.
  bool _activePointerCanceled = false;
  // The last fraction written to the controller/preview this drag, its source,
  // and (for sticky) the captured point's index. These supersede a single
  // "last ratio": a live mode's written request, its visible position, and the
  // raw pointer are three different values.
  double? _lastDragRequestFraction;
  SplitterChangeSource? _lastDragSource;
  int? _stickyCapturedIndex;
  OverlayEntry? _dragOverlay;
  ScrollHoldController? _scrollHold;
  final List<_PendingPointer> _pendingPointers = <_PendingPointer>[];

  @override
  void initState() {
    super.initState();
    // A drag is only valid while there is geometry to resize against; watch for
    // it disappearing (see _handleGeometryChanged).
    widget.geometryListenable.addListener(_handleGeometryChanged);
  }

  // Interrupts an in-flight drag the moment the splitter loses its geometry (e.g.
  // its main axis becomes unbounded mid-drag): tears down on the controller the
  // drag began on - no commit, no snap, no phantom end - instead of freezing the
  // drag and later reporting a zeroed change payload. Fires post-frame (the
  // notifier flush is deferred), so calling _endDrag here is safe.
  void _handleGeometryChanged() {
    if (_isDragging && widget.geometryListenable.value == null) {
      _endDrag(_DragEndReason.interrupted);
    }
  }

  void _haptic() {
    if (widget.enableHaptics) unawaited(HapticFeedback.selectionClick());
  }

  // The resolved geometry from the render object's last layout pass (read live),
  // or null before the first layout / while detached. Event handlers read this
  // so a drag, key press, or assistive action always uses the current solver.
  _ResolvedSplitterGeometry? get _geometry => widget.geometryListenable.value;

  // The live solver, or null with no geometry. The single source every value
  // read shares, so the "no live solver" fallback is decided in one place
  // (_changeDetailsFromController / the controller's own derivation) instead of
  // being reinvented per method.
  SplitterSolver? get _solver => _geometry?.solver;

  // The pointer's position along the main axis in the splitter's local frame
  // (transform-safe), falling back to the raw global coordinate if the render
  // box is unavailable.
  double _mainAxisPosition(Offset globalPosition) =>
      widget.localMainAxisOf(globalPosition) ??
      (widget.axis.isH ? globalPosition.dx : globalPosition.dy);

  bool get _isHovering {
    final localPosition = _hoverLocalPosition;
    if (localPosition == null || !widget.resizable || widget.thickness <= 0) {
      return false;
    }
    final crossAxisPosition = widget.axis.isH
        ? localPosition.dx
        : localPosition.dy;
    final visibleStart = widget.interactiveSlop;
    final visibleEnd = visibleStart + widget.thickness;
    return crossAxisPosition >= visibleStart && crossAxisPosition <= visibleEnd;
  }

  void _updateHoverPosition(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final wasHovering = _isHovering;
    _hoverLocalPosition = event.localPosition;
    if (wasHovering != _isHovering && mounted) setState(() {});
  }

  void _clearHoverPosition() {
    final wasHovering = _isHovering;
    _hoverLocalPosition = null;
    if (wasHovering && mounted) setState(() {});
  }

  void _suppressPointerFocusHighlight() {
    _suppressFocusHighlightUntilKeyboard = true;
    if (_isFocused && mounted) setState(() => _isFocused = false);
  }

  void _showKeyboardFocusHighlight() {
    _suppressFocusHighlightUntilKeyboard = false;
    if (widget.focusNode.hasFocus && !_isFocused && mounted) {
      setState(() => _isFocused = true);
    }
  }

  void _setFocusHighlight(bool show) {
    final isVisible = show && !_suppressFocusHighlightUntilKeyboard;
    if (isVisible != _isFocused && mounted) {
      setState(() => _isFocused = isVisible);
    }
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) return;
    _suppressFocusHighlightUntilKeyboard = false;
    if (_isFocused && mounted) setState(() => _isFocused = false);
  }

  /// Builds the change payload for the effective [fraction], resolving the
  /// layout through the shared solver so the reported extents match what is
  /// drawn. [requestedPosition] is the controller's *actual* request - which may
  /// be a pixel pin - rather than a fraction fabricated from the effective value,
  /// so a drag that starts on a pinned pane reports the pin honestly.
  SplitterChangeDetails _changeDetails(
    double fraction,
    SplitterChangeSource source, {
    SplitterChangeEnd? end,
  }) {
    final solver = _solver;
    if (solver == null) return _changeDetailsFromController(source, end: end);
    final solution = solver.solve(SplitterPosition.fraction(fraction));
    return SplitterChangeDetails(
      requestedPosition: widget.controller.value.position,
      effectiveFraction: solution.effectiveFraction,
      startExtent: solution.startExtent,
      endExtent: solution.endExtent,
      availableExtent: solver.available,
      source: source,
      end: end,
    );
  }

  /// The change payload when there is no live solver (before the first layout /
  /// while detached), derived entirely from the controller's published state -
  /// the SAME source [_effective] falls back to - so a payload built in this
  /// window can never disagree with the semantics value or the keyboard/drag
  /// accumulation base. A real interaction can't reach it (drag/keyboard/snap all
  /// refuse to act without a solver, and a drag that loses its geometry is
  /// interrupted); it backstops the settle/cancel terminals and the double-tap
  /// callback.
  SplitterChangeDetails _changeDetailsFromController(
    SplitterChangeSource source, {
    SplitterChangeEnd? end,
  }) {
    final controller = widget.controller;
    final layout = controller.layout;
    return SplitterChangeDetails(
      requestedPosition: controller.value.position,
      effectiveFraction: controller.effectiveFraction,
      startExtent: layout?.startExtent ?? 0,
      endExtent: layout?.endExtent ?? 0,
      availableExtent: layout?.availableExtent ?? 0,
      source: source,
      end: end,
    );
  }

  /// The current on-screen start fraction, freshly re-solved from the
  /// controller's requested position so synchronous adjustments accumulate
  /// against what is actually shown (not a stale build-time solution). With no
  /// live solver it falls back to the controller's own published derivation - the
  /// single shared fallback, see [_changeDetailsFromController].
  double get _effective =>
      _solver?.solve(widget.controller.value.position).effectiveFraction ??
      widget.controller.effectiveFraction;

  @override
  void didUpdateWidget(_DividerHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The geometry listenable is a stable field on the splitter state in
    // practice, but move the watcher if it is ever swapped so the drag-interrupt
    // can't be left listening to a dead notifier.
    if (!identical(oldWidget.geometryListenable, widget.geometryListenable)) {
      oldWidget.geometryListenable.removeListener(_handleGeometryChanged);
      widget.geometryListenable.addListener(_handleGeometryChanged);
    }
    final session = _session;
    if (session == null) return;
    // A drag is anchored to the controller, axis, and mode it began on. If the
    // parent swaps any of those (or turns resizing off) mid-drag, interrupt it
    // on the controller it began on (held by the session): no commit, no snap,
    // no onChangeEnd. The idempotent [_endDrag] guard also means a later gesture
    // end/cancel for the same pointer can no longer fire a phantom onChangeEnd.
    if (!identical(session.controller, widget.controller) ||
        session.axis != widget.axis ||
        session.deferred != widget.deferred ||
        session.snap != widget.snap ||
        !widget.resizable) {
      _endDrag(_DragEndReason.interrupted);
    }
  }

  @override
  void dispose() {
    widget.geometryListenable.removeListener(_handleGeometryChanged);
    // Tear down on the session's controller (not necessarily widget.controller)
    // without setState. No commit, snap, or onChangeEnd.
    final session = _session;
    _session = null;
    if (session != null) _teardown(session);
    widget.controller._setDragCallback(null);
    _removeOverlay();
    _scrollHold?.cancel();
    _scrollHold = null;
    _pendingPointers.clear();
    super.dispose();
  }

  /// Resolves the divider color for the active [states], falling back to a tint
  /// derived from the ambient [ColorScheme] when the style leaves it unset. The
  /// merge of widget-over-theme already happened upstream, so [dividerColor] is
  /// the single resolved property here.
  Color _resolveDividerColor(Set<WidgetState> states) {
    final resolved = widget.dividerColor?.resolve(states);
    if (resolved != null) return resolved;
    final cs = Theme.of(context).colorScheme;
    if (states.contains(WidgetState.dragged)) {
      return cs.onSurface.withAlpha(31);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return cs.onSurface.withAlpha(20);
    }
    return cs.outlineVariant;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.resizable || _isDragging) return;
    if (!_isSupportedPointerKind(details.kind)) return;

    final geometry = _geometry;
    // No resolved geometry yet (not laid out): nothing to drag against.
    if (geometry == null) return;

    final controller = widget.controller;
    final pending = _takePendingPointer(details.globalPosition);
    final pointerId = pending?.id ?? -1;
    final isRtl =
        widget.axis.isH && Directionality.maybeOf(context) == TextDirection.rtl;
    final session = _DragSession(
      controller: controller,
      pointerId: pointerId,
      axis: widget.axis,
      isRtl: isRtl,
      startEffectiveFraction: geometry.solver
          .solve(controller.value.position)
          .effectiveFraction,
      startLocalMainAxis: _mainAxisPosition(details.globalPosition),
      availableExtent: geometry.solver.available,
      deferred: widget.deferred,
      snap: widget.snap,
      onPreviewChanged: widget.onPreviewChanged,
    );
    setState(() => _session = session);
    _lastDragRequestFraction = null;
    _lastDragSource = null;
    _stickyCapturedIndex = null;
    _activePointerCanceled = false;

    controller
      .._cancelAnimation()
      .._setDragging(true)
      .._setDragCallback(_endDrag);
    // Register both the exact pointer (for a normal up/cancel) and, for a mouse,
    // its device - so a release the platform view swallows can still be
    // recovered from the next no-button hover (see [_GlobalPointerRouter]).
    SplitterController._globalRouter.beginDrag(
      controller,
      pointerId,
      device: pending?.device,
      viewId: pending?.viewId,
      kind: pending?.kind,
    );

    if (widget.holdScrollWhileDragging) {
      _scrollHold?.cancel();
      _scrollHold = Scrollable.maybeOf(context)?.position.hold(() {});
    }

    // The shield is already armed on pointer-down (see [_rememberPointer]),
    // before this recognizer accepts, so a divider that waits for touch slop is
    // never momentarily unshielded. Now that the drag is live, repaint the
    // (already-inserted) shield so its visible barrier appears. This runs in the
    // gesture phase, so marking the overlay dirty here is safe.
    _dragOverlay?.markNeedsBuild();

    _haptic();
    _suppressPointerFocusHighlight();
    widget.focusNode.requestFocus();
    widget.onChangeStart?.call(
      _changeDetails(session.startEffectiveFraction, SplitterChangeSource.drag),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final session = _session;
    if (session == null) return;
    final geometry = _geometry;
    if (geometry == null) return;

    // The session captured the start anchors and available extent, so the math
    // stays stable even if the container resizes mid-drag; the live solver still
    // clamps to current constraints (no dead zone, no inverted clamp).
    final currentPos = _mainAxisPosition(details.globalPosition);
    final rawPointer = session.fractionFor(currentPos, geometry.solver);
    final applied = _applyLiveSnap(rawPointer, geometry, session.snap);
    _lastDragRequestFraction = applied.requestFraction;
    _lastDragSource = applied.source;

    if (session.deferred) {
      // Defer the resize: move only the preview line. The panes keep their
      // committed size and onChanged stays silent until the drag is released.
      session.onPreviewChanged?.call(applied.requestFraction);
      return;
    }

    final previous = _effective;
    // Live modes (magnetic/sticky) need their exact request written so the
    // divider can land on a point and not lag the visible value; release/none
    // keep the per-update threshold that tames chatty pointer streams.
    if (applied.live) {
      _writeExactDragRequest(widget.controller, applied.requestFraction);
    } else {
      widget.controller.updateRatio(applied.requestFraction);
    }
    final current = _effective;
    if ((current - previous).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, applied.source));
    }
  }

  // Transforms the raw pointer fraction for the active snap mode. Release/none
  // pass through (release snapping settles on release); magnetic applies a
  // continuous pull; sticky captures/holds/escapes, threading the captured
  // index through [_stickyCapturedIndex].
  _LiveSnapResult _applyLiveSnap(
    double rawPointer,
    _ResolvedSplitterGeometry geometry,
    SplitterSnapBehavior? snap,
  ) {
    switch (snap) {
      case null:
      case ReleaseSnap():
        _stickyCapturedIndex = null;
        return _LiveSnapResult(
          rawPointer,
          SplitterChangeSource.drag,
          live: false,
        );
      case MagneticSnap():
        _stickyCapturedIndex = null;
        final pulled = magneticPull(
          pointer: rawPointer,
          resolver: SnapResolver(snap, geometry.solver),
          strength: snap.strength,
          curve: snap.falloff,
          settleFactor: snap.settleFactor,
        );
        return _LiveSnapResult(pulled, SplitterChangeSource.drag, live: true);
      case StickySnap():
        final step = stickyStep(
          pointer: rawPointer,
          capturedIndex: _stickyCapturedIndex,
          resolver: SnapResolver(snap, geometry.solver),
          escapeFactor: snap.escapeFactor,
        );
        _stickyCapturedIndex = step.capturedIndex;
        return _LiveSnapResult(step.requestFraction, step.source, live: true);
    }
  }

  // Writes [fraction] to [controller] exactly (no update threshold), as a fresh
  // fractional intent. The guard avoids a redundant write when the request is
  // already in effect and no collapse needs clearing.
  void _writeExactDragRequest(SplitterController controller, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    final position = SplitterPosition.fraction(clamped);
    if (controller.value.position != position ||
        controller.value.collapsedPane != null) {
      controller.jumpTo(position);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    // Flutter routes a mid-drag pointer cancel through onEnd, so classify it
    // with the flag the Listener set from the raw PointerCancelEvent.
    _endDrag(
      _activePointerCanceled
          ? _DragEndReason.canceled
          : _DragEndReason.completed,
    );
  }

  // Fires only when a drag is rejected before it is accepted (the session, if
  // any, is already gone); the idempotent _endDrag makes it a safe no-op.
  void _onDragCancel() => _endDrag(_DragEndReason.canceled);

  // The single, idempotent terminal for a drag. Claims the session before any
  // user code so a re-entrant call (the router backup plus the gesture end, or
  // a callback that triggers a rebuild) no-ops; settles only on a real
  // completion; and ALWAYS tears down, even if a user callback throws.
  void _endDrag(_DragEndReason reason) {
    final session = _session;
    if (session == null) return;
    _session = null;
    if (mounted) setState(() {}); // drop the dragged visual state

    SplitterChangeDetails? endDetails;
    try {
      switch (reason) {
        case _DragEndReason.completed:
          // A real release: settle (commit / snap) and report a committed end.
          endDetails = _settle(session);
        case _DragEndReason.canceled:
          // A system cancel: commit nothing and do not snap, but still report a
          // balanced end (marked canceled) so every onChangeStart has its end.
          endDetails = _changeDetails(
            _effective,
            SplitterChangeSource.drag,
            end: SplitterChangeEnd.canceled,
          );
        case _DragEndReason.interrupted:
          // A mid-drag reconfiguration tears down from didUpdateWidget; calling
          // back during a parent rebuild would be unsafe, so fire no end.
          endDetails = null;
      }
    } finally {
      _teardown(session);
    }

    // Fire after teardown (so the controller already reads isDragging == false),
    // and never if settle threw (endDetails stays null).
    if (endDetails != null && mounted) widget.onChangeEnd?.call(endDetails);
  }

  // Commits the final position (or a snap) for a completed drag and returns the
  // end payload. May invoke onChanged; if that throws, [_endDrag]'s finally
  // still tears the drag down.
  SplitterChangeDetails _settle(_DragSession session) {
    session.onPreviewChanged?.call(null);

    // The live transform already settled magnetic/sticky during the drag, so the
    // request is whatever was last written/previewed; in deferred mode that is
    // the last preview (the controller has not moved yet).
    var request = _lastDragRequestFraction ?? _effective;
    var source = _lastDragSource ?? SplitterChangeSource.drag;

    // Release snapping settles here: pick the nearest point within tolerance.
    final snap = session.snap;
    if (snap is ReleaseSnap) {
      final snapped = _maybeSnap(snap, request);
      if (snapped != null) {
        request = snapped;
        source = SplitterChangeSource.snap;
      }
    }

    // One commit path, written exactly: the per-update threshold can otherwise
    // leave the handle a fraction short of where the pointer let go (and in
    // deferred mode the controller has not moved at all).
    final previous = _effective;
    _writeExactDragRequest(session.controller, request);
    final current = _effective;
    if ((current - previous).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, source));
    }

    return _changeDetails(current, source, end: SplitterChangeEnd.committed);
  }

  // Releases the session's controller (the one the drag began on, never a
  // swapped-in one) and clears all per-drag resources, using the preview
  // callback captured at start so the preview clears even if the parent flipped
  // deferredResize/resizable off mid-drag. Commits nothing and never calls
  // setState, so it is safe to run from dispose.
  void _teardown(_DragSession session) {
    final controller = session.controller;
    controller
      .._setDragging(false)
      .._setDragCallback(null);
    SplitterController._globalRouter.endDrag(controller);
    session.onPreviewChanged?.call(null);
    // Drop the shield unless another pending pointer still needs it (it is also
    // removed unconditionally in dispose).
    _removeShieldIfIdle();
    _scrollHold?.cancel();
    _scrollHold = null;
    _lastDragRequestFraction = null;
    _lastDragSource = null;
    _stickyCapturedIndex = null;
    _activePointerCanceled = false;
    if (session.pointerId >= 0) {
      _pendingPointers.removeWhere(
        (pointer) => pointer.id == session.pointerId,
      );
    }
  }

  // Pure release-snap selection: the nearest point's resolved fraction when the
  // released [value] is within tolerance, else null. The distance is measured in
  // effective space (or pixels when pixelTolerance is set), so a point that
  // constraints push aside is matched by where it actually lands. No writes and
  // no callbacks - [_settle] owns the single commit.
  double? _maybeSnap(ReleaseSnap snap, double value) {
    final geometry = _geometry;
    if (geometry == null || geometry.solver.available <= 0) return null;
    final resolver = SnapResolver(snap, geometry.solver);
    final nearest = resolver.nearest(value);
    if (nearest == null) return null;
    return nearest.distance <= resolver.radius
        ? nearest.effectiveFraction
        : null;
  }

  void _insertOverlay() {
    if (_dragOverlay != null) return;

    // The shield needs a root Overlay to sit above platform views. Apps built on
    // MaterialApp/Navigator have one; if there is none, degrade gracefully - the
    // drag still works, just without the platform-view shield - rather than
    // throwing from a reusable layout primitive (Overlay.of would).
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      assert(() {
        debugPrint(
          'ResizableSplitter: no Overlay ancestor, so the drag platform-view '
          'shield is disabled. Provide a MaterialApp/Navigator (or any Overlay), '
          'or set shieldPlatformViews: false to opt out and silence this.',
        );
        return true;
      }());
      return;
    }

    final entry = OverlayEntry(
      builder: (context) => _DragOverlay(
        axis: widget.axis,
        // The shield is opaque from the moment it is inserted (on pointer-down),
        // but its visible barrier tracks the live drag state so a press that is
        // not (yet) a drag paints nothing. _onDragStart marks this entry dirty
        // so the barrier appears the instant the drag is accepted.
        isDragging: _isDragging,
        dragBarrierColor: widget.dragBarrierColor,
        barrierBuilder: widget.dragBarrierBuilder,
      ),
    );

    // Only record the entry once it is actually inserted, so _removeOverlay can
    // always pair a remove() with the dispose() (mounted tracks the built
    // widget, not overlay membership).
    overlay.insert(entry);
    _dragOverlay = entry;
  }

  void _removeOverlay() {
    final overlay = _dragOverlay;
    _dragOverlay = null;
    if (overlay == null) return;
    overlay
      ..remove()
      ..dispose();
  }

  // The shield brackets the pointer, not just the accepted drag: it is armed on
  // pointer-down and must come down once neither a live press nor an active drag
  // needs it. Calling this on every pointer-up/cancel (and after teardown) keeps
  // the shield from ever outliving the pointer/session that armed it.
  void _removeShieldIfIdle() {
    if (_pendingPointers.isEmpty && !_isDragging) _removeOverlay();
  }

  void _rememberPointer(PointerDownEvent event) {
    if (!widget.resizable || _isDragging) return;
    _updateHoverPosition(event);

    final isPrimaryMouse =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton;
    final isTouchLike =
        event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.trackpad ||
        event.kind == PointerDeviceKind.unknown;

    if (!isPrimaryMouse && !isTouchLike) return;

    // Pressing the handle focuses it, so keyboard adjustment works after a tap
    // (not only after a drag).
    if (widget.enableKeyboard && widget.resizable) {
      _suppressPointerFocusHighlight();
      widget.focusNode.requestFocus();
    }

    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
    _pendingPointers.add(_PendingPointer(event));

    // Arm the platform-view shield from the press itself, not from drag
    // acceptance. A divider that also handles a tap/double-tap only wins the
    // drag after touch slop, so arming it in [_onDragStart] would leave a window
    // in which a neighboring platform view (e.g. a WebView) can capture the OS
    // pointer and swallow the release - stranding the drag with no end event.
    // The opaque shield wins every hit from the first event; its visible barrier
    // still appears only while a drag is actually active (see [_DragOverlay]), so
    // a press that turns out to be a tap flashes nothing.
    if (widget.shieldPlatformViews) _insertOverlay();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _updateHoverPosition(event);
  }

  void _handlePointerUp(PointerEvent event) {
    _updateHoverPosition(event);
    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
    // The divider's own Listener sits in the in-flight pointer's captured
    // hit-test path, so its up fires for the real release whenever that release
    // reaches the framework. Make it an authoritative terminal rather than mere
    // cleanup: the recognizer's onEnd and the global route become redundant
    // (idempotent) backups, and teardown no longer depends on either firing.
    final session = _session;
    if (session != null && event.pointer == session.pointerId) {
      _endDrag(_DragEndReason.completed);
      return;
    }
    // A press that never became a drag (a tap) drops the shield here, so it can
    // never outlive the pointer that armed it.
    _removeShieldIfIdle();
  }

  void _handlePointerCancel(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) _clearHoverPosition();
    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
    final session = _session;
    if (session != null && event.pointer == session.pointerId) {
      // The raw cancel is authoritative; settle nothing, fire a balanced
      // canceled end. (The flag also keeps a later recognizer onEnd, if one
      // still arrives, from misclassifying this as a completion.)
      _activePointerCanceled = true;
      _endDrag(_DragEndReason.canceled);
      return;
    }
    _removeShieldIfIdle();
  }

  _PendingPointer? _takePendingPointer(Offset globalPosition) {
    if (_pendingPointers.isEmpty) return null;

    const double toleranceSquared = 16.0;
    _PendingPointer? match;
    var matchIndex = -1;

    for (var i = _pendingPointers.length - 1; i >= 0; i--) {
      final candidate = _pendingPointers[i];
      final diff = candidate.downPosition - globalPosition;
      if (diff.distanceSquared <= toleranceSquared) {
        match = candidate;
        matchIndex = i;
        break;
      }
    }

    match ??= _pendingPointers.first;
    matchIndex = matchIndex >= 0 ? matchIndex : 0;
    _pendingPointers.removeAt(matchIndex);
    return match;
  }

  bool _isSupportedPointerKind(PointerDeviceKind? kind) {
    if (kind == null) return true;
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.mouse ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.trackpad ||
        kind == PointerDeviceKind.unknown;
  }

  /// The on-screen ratio for an arbitrary hypothetical [ratio], honoring ratio
  /// caps and pixel minimums. Used for the semantics increase/decrease readouts.
  /// With no live solver a hypothetical ratio cannot be resolved, so it degrades
  /// to a plain clamp - but every call site is gated on a non-null solution (the
  /// canIncrease/canDecrease flags in build), so that fallback is unreachable in
  /// practice and exists only for total safety.
  double _effectiveRatio(double ratio) =>
      _solver?.solve(SplitterPosition.fraction(ratio)).effectiveFraction ??
      ratio.clamp(0.0, 1.0).toDouble();

  void _nudge(double delta, SplitterChangeSource source) {
    if (!widget.resizable) return;
    final geometry = _geometry;
    if (geometry == null) return;

    // Step from the current *effective* position (re-solved fresh, so repeated
    // presses without a rebuild still accumulate), then re-solve to clamp. This
    // moves the divider by the step in what the user actually sees, instead of
    // nudging a stored value through a dead band.
    final base = _effective;
    final newRatio = geometry.solver
        .solve(SplitterPosition.fraction(base + delta))
        .effectiveFraction;
    widget.controller.jumpTo(SplitterPosition.fraction(newRatio));
    final current = _effective;
    if ((current - base).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, source));
      _haptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the resolved geometry changes (e.g. a container resize that
    // leaves the request unchanged), so the semantics value and affordances
    // track what is actually drawn.
    return ValueListenableBuilder<_ResolvedSplitterGeometry?>(
      valueListenable: widget.geometryListenable,
      builder: (context, _, _) => _buildHandle(context),
    );
  }

  Widget _buildHandle(BuildContext context) {
    // Focus is only meaningful when the handle is a keyboard-navigable resize
    // affordance; gate it so a stale highlight (e.g. after keyboard support is
    // turned off) can never paint a ring on a non-interactive divider.
    final isFocused = _isFocused && widget.enableKeyboard && widget.resizable;
    final states = <WidgetState>{
      if (!widget.resizable) WidgetState.disabled,
      if (_isHovering) WidgetState.hovered,
      if (isFocused) WidgetState.focused,
      if (_isDragging) WidgetState.dragged,
    };
    // The default focus ring is a border on the bar. A custom grip builder owns
    // its own focus visual (it receives isFocused), so the default ring is
    // suppressed when a builder is supplied to avoid a doubled indicator.
    final showFocusRing = isFocused && widget.handleBuilder == null;
    final currentDecoration = BoxDecoration(
      color: _resolveDividerColor(states),
      border: showFocusRing
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
          : null,
    );

    final grip =
        widget.handleBuilder?.call(
          context,
          SplitterHandleDetails(
            isDragging: _isDragging,
            isHovering: _isHovering,
            isFocused: isFocused,
            axis: widget.axis,
            thickness: widget.thickness,
          ),
        ) ??
        // Default subtle grip.
        Center(
          child: Container(
            width: widget.axis.isH ? 2 : 24,
            height: widget.axis.isH ? 24 : 2,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(77),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );

    Widget handle = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: currentDecoration,
      child: grip,
    );

    if (widget.axis.isH) {
      handle = SizedBox(width: widget.thickness, child: handle);
    } else {
      handle = SizedBox(height: widget.thickness, child: handle);
    }

    // Widen the *grab* area across the divider's thin dimension without moving
    // the visible bar: the slop is transparent padding that still sits inside
    // the opaque Listener below, so it hit-tests. The matching extent was
    // already reserved out of the panels via the divider footprint.
    if (widget.interactiveSlop > 0) {
      handle = Padding(
        padding: widget.axis.isH
            ? EdgeInsets.symmetric(horizontal: widget.interactiveSlop)
            : EdgeInsets.symmetric(vertical: widget.interactiveSlop),
        child: handle,
      );
    }

    Widget divider = GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      excludeFromSemantics: true,
      onHorizontalDragStart: widget.axis.isH ? _onDragStart : null,
      onHorizontalDragUpdate: widget.axis.isH ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.axis.isH ? _onDragEnd : null,
      onHorizontalDragCancel: widget.axis.isH ? _onDragCancel : null,
      onVerticalDragStart: widget.axis.isH ? null : _onDragStart,
      onVerticalDragUpdate: widget.axis.isH ? null : _onDragUpdate,
      onVerticalDragEnd: widget.axis.isH ? null : _onDragEnd,
      onVerticalDragCancel: widget.axis.isH ? null : _onDragCancel,
      onTap: widget.onTap,
      onDoubleTap:
          (widget.onDoubleTap != null || widget.doubleTapResetTo != null)
          ? () {
              widget.onDoubleTap?.call();
              if (widget.doubleTapResetTo != null && widget.resizable) {
                final target = widget.doubleTapResetTo!;
                final startValue = widget.controller.effectiveFraction;
                unawaited(
                  widget.controller.animateTo(target).then((status) {
                    // Only report a settle when the animation actually reached
                    // the target; a drag/value-write that cancelled it, or a
                    // disposal, must not emit a phantom programmatic change.
                    if (!mounted ||
                        status != SplitterAnimationStatus.completed) {
                      return;
                    }
                    final updated = _effective;
                    if ((updated - startValue).abs() > 1e-9) {
                      widget.onChanged?.call(
                        _changeDetails(
                          updated,
                          SplitterChangeSource.doubleTapReset,
                        ),
                      );
                    }
                  }),
                );
              }
            }
          : null,
      child: MouseRegion(
        cursor: widget.resizable
            ? widget.axis.cursor
            : SystemMouseCursors.basic,
        onEnter: _updateHoverPosition,
        onHover: _updateHoverPosition,
        onExit: (_) => _clearHoverPosition(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _rememberPointer,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: handle,
        ),
      ),
    );

    // Value previews mirror what an adjust action actually does: move from the
    // current effective position by one step. Assistive adjustment is offered
    // whenever the splitter is resizable, independent of physical keyboard
    // support - a screen reader is its own input channel. Each direction is
    // additionally gated on whether the divider can actually move that way, so a
    // pane pinned at a hard bound drops the action it cannot perform rather than
    // announcing a no-op (review A#14).
    final effective = _effective;
    final labels = widget.semantics;
    String fmt(double ratio) => labels.formatValue(ratio.clamp(0.0, 1.0));
    final solution = _geometry?.solution;
    final canIncrease =
        widget.resizable && (solution?.canIncreaseStart ?? false);
    final canDecrease =
        widget.resizable && (solution?.canDecreaseStart ?? false);

    divider = Semantics(
      slider: true,
      enabled: widget.resizable,
      textDirection: Directionality.maybeOf(context),
      label:
          widget.semanticsLabel ??
          labels.label(axis: widget.axis, resizable: widget.resizable),
      value: fmt(effective),
      increasedValue: canIncrease
          ? fmt(_effectiveRatio(effective + widget.keyboardStep))
          : null,
      decreasedValue: canDecrease
          ? fmt(_effectiveRatio(effective - widget.keyboardStep))
          : null,
      onIncrease: canIncrease
          ? () => _nudge(widget.keyboardStep, SplitterChangeSource.semantics)
          : null,
      onDecrease: canDecrease
          ? () => _nudge(-widget.keyboardStep, SplitterChangeSource.semantics)
          : null,
      child: divider,
    );

    if (widget.enableKeyboard && widget.resizable) {
      final isRtl =
          widget.axis.isH && Directionality.of(context) == TextDirection.rtl;
      final decreaseKey = widget.axis.isH
          ? (isRtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)
          : LogicalKeyboardKey.arrowUp;
      final increaseKey = widget.axis.isH
          ? (isRtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight)
          : LogicalKeyboardKey.arrowDown;
      divider = FocusableActionDetector(
        focusNode: widget.focusNode,
        // Tracks Flutter's focus highlight mode so the ring shows for keyboard
        // traversal but not for a touch/mouse focus.
        onShowFocusHighlight: _setFocusHighlight,
        onFocusChange: _handleFocusChange,
        shortcuts: <LogicalKeySet, Intent>{
          // Fine step (left/right swap under RTL on the horizontal axis).
          LogicalKeySet(decreaseKey): _AdjustIntent(-widget.keyboardStep),
          LogicalKeySet(increaseKey): _AdjustIntent(widget.keyboardStep),
          // Page step
          LogicalKeySet(LogicalKeyboardKey.pageUp): _AdjustIntent(
            -widget.pageStep,
          ),
          LogicalKeySet(LogicalKeyboardKey.pageDown): _AdjustIntent(
            widget.pageStep,
          ),
          // Jump to bounds
          LogicalKeySet(LogicalKeyboardKey.home): const _JumpIntent.toMin(),
          LogicalKeySet(LogicalKeyboardKey.end): const _JumpIntent.toMax(),
        },
        actions: <Type, Action<Intent>>{
          _AdjustIntent: CallbackAction<_AdjustIntent>(
            onInvoke: (intent) {
              _showKeyboardFocusHighlight();
              _nudge(intent.delta, SplitterChangeSource.keyboard);
              return null;
            },
          ),
          _JumpIntent: CallbackAction<_JumpIntent>(
            onInvoke: (intent) {
              _showKeyboardFocusHighlight();
              final geometry = _geometry;
              if (geometry == null) return null;
              final previous = _effective;
              final dest = intent.toMin
                  ? geometry.solver
                        .solve(const SplitterPosition.fraction(0))
                        .effectiveFraction
                  : geometry.solver
                        .solve(const SplitterPosition.fraction(1))
                        .effectiveFraction;
              widget.controller.jumpTo(SplitterPosition.fraction(dest));
              final current = _effective;
              if ((current - previous).abs() > 1e-9) {
                widget.onChanged?.call(
                  _changeDetails(current, SplitterChangeSource.keyboard),
                );
                _haptic();
              }
              return null;
            },
          ),
        },
        child: divider,
      );
    }

    return divider;
  }
}

class _PendingPointer {
  _PendingPointer(PointerDownEvent event)
    : id = event.pointer,
      device = event.device,
      viewId = event.viewId,
      kind = event.kind,
      downPosition = event.position;

  final int id;
  final int device;
  final int viewId;
  final PointerDeviceKind kind;

  /// The global (window) position at down. With `dragStartBehavior.down` the
  /// drag start reports this same down position, so the pending pointer is
  /// matched on it - never on a mutable latest-move position that intervening
  /// moves would have shifted out of tolerance.
  final Offset downPosition;
}

/// An invisible overlay that acts as a shield to block pointer events
/// from reaching platform views during a drag operation.
class _DragOverlay extends StatelessWidget {
  const _DragOverlay({
    required this.axis,
    required this.isDragging,
    this.dragBarrierColor,
    this.barrierBuilder,
  });

  final Axis axis;

  /// Whether a drag is actually in progress. The opaque shield is active the
  /// whole time the overlay is inserted (from pointer-down), but the *visible*
  /// barrier is painted only while [isDragging], so arming the shield early
  /// never flashes a barrier on a press that turns out to be a tap. The handle
  /// rebuilds this entry (via [OverlayEntry.markNeedsBuild]) when the drag
  /// begins, rather than having the overlay subscribe to the controller - a
  /// subscription would try to rebuild when teardown flips the flag during a
  /// locked phase (dispose / a mid-drag reconfiguration) and throw.
  final bool isDragging;
  final Color? dragBarrierColor;
  final Widget Function(BuildContext context)? barrierBuilder;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: axis.cursor,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            // The opaque Listener wins every hit regardless of paint, so the
            // shield blocks platform views from the moment of press - before the
            // drag is even recognized and even with a transparent barrier.
            // IgnorePointer additionally keeps a custom barrierBuilder strictly
            // visual: its own recognizers or buttons can never receive the
            // pointer events (review A#16).
            child: IgnorePointer(
              child: isDragging
                  ? (barrierBuilder?.call(context) ??
                        ColoredBox(
                          color: dragBarrierColor ?? Colors.transparent,
                        ))
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
