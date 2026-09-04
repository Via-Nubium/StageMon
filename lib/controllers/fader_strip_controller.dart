import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show HitTestResult, RenderMetaData;
import 'package:flutter/widgets.dart';

import '../models/fader_width.dart';
import '../widgets/custom_fader.dart';

// The marker [ForeignGestureArea] plants in the tree and _stripTargetAt looks
// for. Private: nothing outside this file needs to know how the exclusion is
// spelled, only to wrap the widget.
const Object _kForeignGestureArea = Object();

/// Wraps a control that sits inside the strip but keeps its own gesture
/// handling — a PanKnob, the MuteButton, the group config button. Touches on
/// it are excluded from both fader-drag and strip scroll/pinch.
class ForeignGestureArea extends StatelessWidget {
  const ForeignGestureArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: _kForeignGestureArea,
    behavior: HitTestBehavior.opaque,
    child: child,
  );
}

/// The bus column sits outside the pinch-resize, so it keeps a fixed width and
/// is accounted for separately in the strip-extent math.
const double kBusColumnWidth = 90;

// Movement needed to lock a pointer's role in (fader-drag vs. strip). This is
// the main "feel" knob: lower = faders react sooner, higher = fast horizontal
// swipes are less likely to get caught as a vertical drag.
const double _kAxisLockSlop = 12.0;

enum _PointerRole { undecided, fader, strip, ignored }

class _TrackedPointer {
  _TrackedPointer(this.downPosition, this.controller, this.role)
    : position = downPosition;
  final Offset downPosition;
  Offset position;
  final FaderDragController? controller;
  _PointerRole role;
}

/// Owns the fader strip's horizontal scroll, its pinch-to-resize width, and
/// the per-fader drag controllers — everything about how touches on the strip
/// are routed. The screen feeds it raw pointer events from a single
/// [Listener] and rebuilds when it notifies.
///
/// See lib/widgets/custom_fader.dart's FaderDragController doc comment for why
/// this isn't built out of nested GestureDetectors: a per-fader drag
/// recognizer nested inside a screen-wide scale recognizer makes every
/// two-finger touch a race between their independent slop thresholds, decided
/// by Flutter's gesture arena rather than by anything this code controls.
/// Instead, a single Listener (which never enters the arena) tracks raw
/// pointers and this class decides explicitly, per pointer: is it dragging a
/// fader (vertical intent, landed on one), or is it part of the strip's
/// scroll/pinch (horizontal intent, or landed elsewhere)?
class FaderStripController extends ChangeNotifier {
  /// Called when the user lifts the last finger after a pinch that actually
  /// changed the width. Where that width is kept — which layout, which group —
  /// is the screen's business, not this class's.
  final void Function(double width)? onWidthCommitted;

  FaderStripController({
    double initialWidth = kDefaultFaderWidth,
    this.onWidthCommitted,
  }) : _faderWidth = initialWidth,
       _committedWidth = initialWidth;

  final ScrollController scrollController = ScrollController();

  /// Width of every resizable column, the value a pinch changes.
  double get faderWidth => _faderWidth;
  double _faderWidth;

  // Last width handed to onWidthCommitted, so releasing the strip after a
  // plain scroll doesn't report a change that didn't happen.
  double _committedWidth;

  /// Adopts a width decided elsewhere — a layout being loaded or imported.
  void applyWidth(double width) {
    final clamped = clampFaderWidth(width);
    if (clamped == _faderWidth) return;
    _faderWidth = clamped;
    _committedWidth = clamped;
    notifyListeners();
  }

  final Map<Object, FaderDragController> _faderControllers = {};
  final Map<int, _TrackedPointer> _pointers = {}; // insertion-ordered

  double _stripRefWidth = 90;
  double _stripRefDistance = 0;
  Offset _stripLastFocal = Offset.zero;

  // Strip content composition, refreshed on every build, so a pinch can
  // work out what the scroll extent *will be* at the width it's about to
  // apply. Clamping against ScrollPosition.maxScrollExtent instead would
  // use the extent of the width still on screen: pinching open near the
  // right-hand end pushes the anchored offset past that stale limit and
  // it gets silently truncated, which reads as the strip sliding out from
  // under the fingers — worse the faster the fingers move, since each
  // frame loses a little more.
  int _stripScalableColumns = 0;
  double _stripFixedWidth = 0;

  // Fling on release. Velocity is measured on how far the strip has *panned*
  // (the focal point's travel), not on the scroll offset: a pinch-resize moves
  // the offset a lot while the content under the fingers stays put, and
  // flinging off that would launch the strip after a gesture that never
  // panned. Accumulating the per-frame pan also keeps the measurement
  // continuous across finger-count changes, which the focal point itself is
  // not — it jumps whenever the strip pair is re-based.
  VelocityTracker? _stripPanVelocity;
  double _stripPanTravel = 0;
  bool _stripOverscrolled = false;

  // ── Strip composition, fed from the build ───────────────────────────────

  /// The drag controller for one column, created on first use so it survives
  /// rebuilds.
  FaderDragController controllerFor(Object id) =>
      _faderControllers.putIfAbsent(id, FaderDragController.new);

  /// Drops controllers for columns that no longer exist (deselected channel,
  /// hidden group, etc.) so they don't accumulate forever across rebuilds.
  void pruneControllers(Iterable<Object> liveIds) {
    _faderControllers.removeWhere((id, _) => !liveIds.contains(id));
  }

  /// What the strip is about to lay out: how many columns scale with
  /// [faderWidth], and how much width around them does not.
  void setContentMetrics({
    required int scalableColumns,
    required double fixedWidth,
  }) {
    _stripScalableColumns = scalableColumns;
    _stripFixedWidth = fixedWidth;
  }

  // ── Pointer routing ─────────────────────────────────────────────────────

  List<_TrackedPointer> get _stripPointers => _pointers.values
      .where((p) => p.role == _PointerRole.strip)
      .take(2)
      .toList();

  Object? _stripTargetAt(PointerEvent e) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, e.position, e.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderMetaData) continue;
      final meta = target.metaData;
      if (meta is FaderDragController ||
          identical(meta, _kForeignGestureArea)) {
        return meta;
      }
    }
    return null;
  }

  void onPointerDown(PointerDownEvent e) {
    _stopStripFling();
    final hit = _stripTargetAt(e);
    final p = _TrackedPointer(
      e.localPosition,
      hit is FaderDragController ? hit : null,
      identical(hit, _kForeignGestureArea)
          ? _PointerRole.ignored
          : _PointerRole.undecided,
    );
    _pointers[e.pointer] = p;
    // If the strip is already being manipulated, this finger joins it
    // rather than starting anything of its own — the re-baseline this
    // triggers is what keeps a finger that was sitting still on a fader
    // from causing a jump once a second finger commits to the strip.
    if (p.role == _PointerRole.undecided && _stripPointers.isNotEmpty) {
      _promoteToStrip(p);
    }
  }

  void onPointerMove(PointerMoveEvent e) {
    final p = _pointers[e.pointer];
    if (p == null) return;
    p.position = e.localPosition;
    switch (p.role) {
      case _PointerRole.ignored:
        break;
      case _PointerRole.undecided:
        _resolveRole(p);
      case _PointerRole.fader:
        p.controller!.updateDrag(e.localPosition.dy);
      case _PointerRole.strip:
        if (_stripPointers.contains(p)) _updateStrip(e.timeStamp);
    }
  }

  void onPointerUpOrCancel(PointerEvent e) {
    final p = _pointers.remove(e.pointer);
    if (p == null) return;
    if (p.role == _PointerRole.fader) {
      p.controller!.endDrag();
    } else if (p.role == _PointerRole.strip) {
      if (_faderWidth != _committedWidth) {
        _committedWidth = _faderWidth;
        onWidthCommitted?.call(_faderWidth);
      }
      if (_stripPointers.isEmpty) {
        _flingStrip();
      } else {
        _rebaseStrip(); // remaining strip finger(s) continue without a jump
      }
    }
  }

  void _resolveRole(_TrackedPointer p) {
    final d = p.position - p.downPosition;
    if (d.dx.abs() < _kAxisLockSlop && d.dy.abs() < _kAxisLockSlop) return;
    if (d.dy.abs() > d.dx.abs() &&
        p.controller != null &&
        !p.controller!.isDragging) {
      p.role = _PointerRole.fader;
      p.controller!.startDrag(p.position.dy); // baseline at the lock: no jump
    } else {
      _promoteToStrip(p);
    }
  }

  // The strip and individual fader drags don't run at the same time: a
  // pointer that commits to the strip cancels any fader drag in progress
  // and pulls in any pointer that hadn't committed to anything yet —
  // including one that's been sitting still since before this one landed.
  // Re-baselining right here, from current positions, is what removes the
  // jump that used to happen when Flutter's arena did this same handoff on
  // its own timing.
  void _promoteToStrip(_TrackedPointer p) {
    p.role = _PointerRole.strip;
    for (final other in _pointers.values) {
      if (other.role == _PointerRole.fader) {
        other.controller!.endDrag();
        other.role = _PointerRole.strip;
      } else if (other.role == _PointerRole.undecided) {
        other.role = _PointerRole.strip;
      }
    }
    _rebaseStrip();
  }

  // Scroll extent the strip will settle at once [faderWidth] is laid out.
  double _maxStripOffsetFor(double faderWidth, ScrollPosition pos) {
    final content = _stripScalableColumns * faderWidth + _stripFixedWidth;
    return (content - pos.viewportDimension).clamp(0.0, double.infinity);
  }

  void _rebaseStrip() {
    final s = _stripPointers;
    if (s.isEmpty) return;
    _stripRefWidth = _faderWidth;
    _stripRefDistance = s.length == 2
        ? (s[0].position - s[1].position).distance.clamp(1.0, double.infinity)
        : 0;
    _stripLastFocal = s.length == 2
        ? Offset.lerp(s[0].position, s[1].position, 0.5)!
        : s[0].position;
  }

  void _updateStrip(Duration timeStamp) {
    final s = _stripPointers;
    if (s.isEmpty) return;
    final focal = s.length == 2
        ? Offset.lerp(s[0].position, s[1].position, 0.5)!
        : s[0].position;
    final panDelta = focal.dx - _stripLastFocal.dx;
    final previousWidth = _faderWidth;
    double newWidth = previousWidth;
    if (s.length == 2 && _stripRefDistance > 0) {
      final distance = (s[0].position - s[1].position).distance.clamp(
        1.0,
        double.infinity,
      );
      newWidth = clampFaderWidth(_stripRefWidth * distance / _stripRefDistance);
    }
    if (scrollController.hasClients) {
      double offset = scrollController.offset;
      if (newWidth != previousWidth) {
        final ratio = newWidth / previousWidth;
        offset = ratio * offset + (ratio - 1) * focal.dx;
      }
      offset -= panDelta;
      final pos = scrollController.position;
      final clamped = offset.clamp(
        pos.minScrollExtent,
        _maxStripOffsetFor(newWidth, pos),
      );
      scrollController.jumpTo(clamped);
      if (offset != clamped) {
        _reportStripOverscroll(pos, offset - clamped, focal);
      }
    }
    if (_stripPanVelocity == null) {
      _stripPanVelocity = VelocityTracker.withKind(PointerDeviceKind.touch);
      _stripPanTravel = 0;
    }
    _stripPanTravel += panDelta;
    _stripPanVelocity!.addPosition(timeStamp, Offset(_stripPanTravel, 0));
    _stripLastFocal = focal;
    if (newWidth != _faderWidth) {
      _faderWidth = newWidth;
      notifyListeners();
    }
  }

  // The strip is scrolled by hand with jumpTo, which hard-clamps at the ends,
  // so Flutter never finds out that the user kept pushing past them. Reporting
  // that leftover travel ourselves is what lets the platform's own overscroll
  // indicator (the stretch effect on Android) respond to a drag, the same way
  // it already responds when a fling runs into the end.
  void _reportStripOverscroll(
    ScrollPosition position,
    double overscroll,
    Offset focal,
  ) {
    final notificationContext = position.context.notificationContext;
    if (notificationContext == null) return;
    _stripOverscrolled = true;
    OverscrollNotification(
      metrics: position.copyWith(),
      context: notificationContext,
      overscroll: overscroll,
      // A non-null dragDetails is what marks this as a pull to follow; with a
      // non-zero velocity instead, the indicator reads it as a fling's impact.
      dragDetails: DragUpdateDetails(
        globalPosition: focal,
        delta: Offset(-overscroll, 0),
        primaryDelta: -overscroll,
      ),
    ).dispatch(notificationContext);
  }

  // Lets the stretch recoil once the fingers are gone.
  void _endStripOverscroll() {
    if (!_stripOverscrolled) return;
    _stripOverscrolled = false;
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final notificationContext = position.context.notificationContext;
    if (notificationContext == null) return;
    ScrollEndNotification(
      metrics: position.copyWith(),
      context: notificationContext,
    ).dispatch(notificationContext);
  }

  // Hands the wind-down to the platform's own scroll physics, so releasing the
  // strip decelerates exactly like every other scrollable in the app.
  // NeverScrollableScrollPhysics only refuses *user* drags; it delegates
  // createBallisticSimulation to its parent, which is the platform default.
  void _flingStrip() {
    _endStripOverscroll();
    final tracker = _stripPanVelocity;
    _stripPanVelocity = null;
    if (tracker == null || !scrollController.hasClients) return;
    final position = scrollController.position;
    if (position is! ScrollPositionWithSingleContext) return;
    // Scroll offset runs opposite to the content travelling under the finger.
    final velocity = -tracker.getVelocity().pixelsPerSecond.dx;
    if (velocity.abs() < kMinFlingVelocity) {
      position.goIdle();
      return;
    }
    position.goBallistic(velocity.clamp(-kMaxFlingVelocity, kMaxFlingVelocity));
  }

  // A touch stops a fling in progress, the same as any scrollable.
  void _stopStripFling() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position is ScrollPositionWithSingleContext) position.goIdle();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
