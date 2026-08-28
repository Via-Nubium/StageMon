import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show HitTestResult, RenderMetaData;
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
import '../services/xr18_simulator.dart';
import '../services/android_network_binder.dart';
import '../services/layout_import_service.dart';
import '../services/screen_awake_service.dart';
import '../widgets/custom_fader.dart';
import '../widgets/mute_button.dart';
import '../widgets/pan_knob.dart';
import '../widgets/group_fader.dart';
import '../models/snapshot_manager.dart';
import '../models/mixer_layout_state.dart';
import '../controllers/mixer_controller.dart';
import '../utils/bus_title.dart';
import 'settings_screen.dart';
import 'group_detail_screen.dart';

class MixerScreen extends StatefulWidget {
  final OscService service;
  final XR18Simulator? simulator;
  final String consoleModel;

  const MixerScreen({
    super.key,
    required this.service,
    this.simulator,
    required this.consoleModel,
  });

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

enum _PointerRole { undecided, fader, strip, ignored }

class _TrackedPointer {
  _TrackedPointer(this.downPosition, this.controller, this.role)
    : position = downPosition;
  final Offset downPosition;
  Offset position;
  final FaderDragController? controller;
  _PointerRole role;
}

class _MixerScreenState extends State<MixerScreen> {
  late final MixerController _ctrl;
  MixerLayoutState _layout = MixerLayoutState.defaults();
  final SnapshotManager _snapshots = SnapshotManager();

  // ── Pinch-to-resize / scroll / fader-drag: unified pointer owner ────────
  // See lib/widgets/custom_fader.dart's FaderDragController doc comment for
  // why this isn't built out of nested GestureDetectors: a per-fader drag
  // recognizer nested inside a screen-wide scale recognizer makes every
  // two-finger touch a race between their independent slop thresholds,
  // decided by Flutter's gesture arena rather than by anything this code
  // controls. Instead, a single Listener (which never enters the arena)
  // tracks raw pointers and this class decides explicitly, per pointer:
  // is it dragging a fader (vertical intent, landed on one), or is it part
  // of the strip's scroll/pinch (horizontal intent, or landed elsewhere)?
  static const double _minFaderWidth = 60;
  static const double _maxFaderWidth = 140;
  // The bus column sits outside the pinch-resize, so it keeps a fixed
  // width and is accounted for separately in the strip-extent math.
  static const double _kBusColumnWidth = 90;
  double _faderWidth = 90;
  final ScrollController _faderScrollController = ScrollController();

  // Marks PanKnob / MuteButton / the group config button inside the strip
  // so a touch there is excluded from both fader-drag and strip handling —
  // those widgets keep their own independent gesture handling untouched.
  static const Object _kForeignGestureArea = Object();

  // Movement needed to lock a pointer's role in (fader-drag vs. strip). This
  // is the main "feel" knob: lower = faders react sooner, higher = fast
  // horizontal swipes are less likely to get caught as a vertical drag.
  static const double _kAxisLockSlop = 12.0;

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
      if (meta is FaderDragController || identical(meta, _kForeignGestureArea)) {
        return meta;
      }
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
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

  void _onPointerMove(PointerMoveEvent e) {
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

  void _onPointerUpOrCancel(PointerEvent e) {
    final p = _pointers.remove(e.pointer);
    if (p == null) return;
    if (p.role == _PointerRole.fader) {
      p.controller!.endDrag();
    } else if (p.role == _PointerRole.strip) {
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setDouble('fader_width', _faderWidth),
      );
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
      newWidth = (_stripRefWidth * distance / _stripRefDistance).clamp(
        _minFaderWidth,
        _maxFaderWidth,
      );
    }
    if (_faderScrollController.hasClients) {
      double offset = _faderScrollController.offset;
      if (newWidth != previousWidth) {
        final ratio = newWidth / previousWidth;
        offset = ratio * offset + (ratio - 1) * focal.dx;
      }
      offset -= panDelta;
      final pos = _faderScrollController.position;
      final clamped = offset.clamp(
        pos.minScrollExtent,
        _maxStripOffsetFor(newWidth, pos),
      );
      _faderScrollController.jumpTo(clamped);
      if (offset != clamped) _reportStripOverscroll(pos, offset - clamped, focal);
    }
    if (_stripPanVelocity == null) {
      _stripPanVelocity = VelocityTracker.withKind(PointerDeviceKind.touch);
      _stripPanTravel = 0;
    }
    _stripPanTravel += panDelta;
    _stripPanVelocity!.addPosition(timeStamp, Offset(_stripPanTravel, 0));
    _stripLastFocal = focal;
    if (newWidth != _faderWidth) setState(() => _faderWidth = newWidth);
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
    if (!_faderScrollController.hasClients) return;
    final position = _faderScrollController.position;
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
    if (tracker == null || !_faderScrollController.hasClients) return;
    final position = _faderScrollController.position;
    if (position is! ScrollPositionWithSingleContext) return;
    // Scroll offset runs opposite to the content travelling under the finger.
    final velocity = -tracker.getVelocity().pixelsPerSecond.dx;
    if (velocity.abs() < kMinFlingVelocity) {
      position.goIdle();
      return;
    }
    position.goBallistic(
      velocity.clamp(-kMaxFlingVelocity, kMaxFlingVelocity),
    );
  }

  // A touch stops a fling in progress, the same as any scrollable.
  void _stopStripFling() {
    if (!_faderScrollController.hasClients) return;
    final position = _faderScrollController.position;
    if (position is ScrollPositionWithSingleContext) position.goIdle();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = MixerController(
      service: widget.service,
      simulator: widget.simulator,
    );
    ScreenAwakeService.start();
    _snapshots.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadPreferences();
    LayoutImportService.listen(_checkPendingLayoutImport);
    _checkPendingLayoutImport();
  }

  // Covers both a file that arrived while disconnected (cold start or the
  // connect screen — picked up here once a console/simulator is chosen and
  // this screen is finally created) and one that arrives while already
  // connected (the push from LayoutImportService.listen wakes this up).
  Future<void> _checkPendingLayoutImport() async {
    final content = await LayoutImportService.takePending();
    if (content == null || !mounted) return;
    // If Settings/Layouts (or anything else) is already open on top of this
    // screen, unwind back to it first — each screen's own normal pop
    // handling flushes its state into MixerScreen as it goes, the same as
    // if the user had pressed back that many times themselves. Without
    // this, a stale Settings screen still underneath would later overwrite
    // whatever the imported layout just applied when it's finally closed.
    while (mounted && ModalRoute.of(context)?.isCurrent != true) {
      final popped = await Navigator.of(context).maybePop();
      if (!popped) break;
    }
    if (!mounted) return;
    _openSettings(pendingImportContent: content);
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedFaderWidth = prefs.getDouble('fader_width');
    if (savedFaderWidth != null) {
      setState(
        () =>
            _faderWidth = savedFaderWidth.clamp(_minFaderWidth, _maxFaderWidth),
      );
    }
    final loaded = await MixerLayoutState.loadFromPrefs(fallbackBus: _ctrl.bus);
    if (!mounted) return;
    setState(() => _layout = loaded);
    if (loaded.bus != _ctrl.bus) _ctrl.changeBus(loaded.bus);
  }

  @override
  void dispose() {
    ScreenAwakeService.stop();
    _ctrl.dispose();
    widget.simulator?.stop();
    _faderScrollController.dispose();
    super.dispose();
  }

  // Drops controllers for columns that no longer exist (deselected channel,
  // hidden group, etc.) so they don't accumulate forever across rebuilds.
  void _pruneFaderControllers(Iterable<Object> liveIds) {
    _faderControllers.removeWhere((id, _) => !liveIds.contains(id));
  }

  // ── Navigation / dialogs ──────────────────────────────────────────────────

  void _openGroupDetail(int groupIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          configs: _layout.groups,
          groupIndex: groupIndex,
          busNum: _ctrl.effectiveBus,
          busPaired: _ctrl.busPaired,
          channelNames: _ctrl.channelNames,
          channelColors: _layout.channelColors,
          lineInColor: _layout.lineInColor,
          fxReturnColors: _layout.fxReturnColors,
          consoleChannelColors: _ctrl.consoleChannelColors,
          consoleLineInColor: _ctrl.consoleLineInColor,
          consoleFxReturnColors: _ctrl.consoleFxReturnColors,
          service: widget.service,
          meterLevels: _ctrl.meterLevels,
          fxReturnMeterL: _ctrl.fxReturnMeterL,
          fxReturnMeterR: _ctrl.fxReturnMeterR,
          lineInMeterL: _ctrl.lineInMeterL,
          lineInMeterR: _ctrl.lineInMeterR,
          onConfigsChanged: (newConfigs) {
            setState(() => _layout = _layout.copyWith(groups: newConfigs));
            _layout.saveToPrefs();
          },
        ),
      ),
    );
  }

  void _openSettings({String? pendingImportContent}) async {
    final result = await Navigator.push<MixerLayoutState>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          layout: _layout,
          channelNames: _ctrl.channelNames,
          busNames: _ctrl.busNames,
          busLinked: _ctrl.busLinked,
          consoleChannelColors: _ctrl.consoleChannelColors,
          consoleLineInColor: _ctrl.consoleLineInColor,
          consoleFxReturnColors: _ctrl.consoleFxReturnColors,
          consoleBusColors: _ctrl.consoleBusColors,
          consoleModel: widget.consoleModel,
          pendingImportContent: pendingImportContent,
        ),
      ),
    );
    if (result != null && mounted) {
      _ctrl.changeBus(result.bus);
      setState(() => _layout = result);
      _layout.saveToPrefs();
    }
  }

  void _confirmDisconnect() {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.disconnect),
        content: Text(l.disconnectConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: Text(
              l.disconnect,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _restoreSnapshot(FaderSnapshot snapshot) {
    final channelsToRestore = Set<int>.from(_layout.channels);
    for (final group in _layout.groups) {
      if (group.visible) channelsToRestore.addAll(group.channels);
    }
    for (final ch in channelsToRestore) {
      final value = snapshot.values[ch];
      if (value != null) _ctrl.service.send(_ctrl.busAddress(ch), value);
      if (_ctrl.busPaired) {
        final pan = snapshot.panValues[ch];
        if (pan != null) _ctrl.service.send(_ctrl.panAddress(ch), pan);
      }
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      if (!_layout.fxReturns.contains(rtn)) continue;
      final value = snapshot.fxReturnValues[rtn];
      if (value != null) _ctrl.service.send(_ctrl.fxReturnAddress(rtn), value);
      if (_ctrl.busPaired) {
        final pan = snapshot.fxReturnPanValues[rtn];
        if (pan != null) _ctrl.service.send(_ctrl.fxReturnPanAddress(rtn), pan);
      }
    }
    if (_layout.lineInVisible) {
      if (snapshot.lineInLevel != null) {
        _ctrl.service.send(_ctrl.lineInAddress(), snapshot.lineInLevel!);
      }
      if (_ctrl.busPaired && snapshot.lineInPan != null) {
        _ctrl.service.send(_ctrl.lineInPanAddress(), snapshot.lineInPan!);
      }
    }
    if (_layout.busFaderVisible) {
      if (snapshot.busLevel != null) {
        _ctrl.service.send(_ctrl.busFaderAddress(), snapshot.busLevel!);
      }
      if (snapshot.busMuted != null) {
        _ctrl.setBusMuted(snapshot.busMuted!);
      }
    }
  }

  Future<String?> _showNameDialog({required String defaultName}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(defaultName: defaultName),
    );
  }

  void _openSnapshotsSheet() {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final maxSheetHeight = MediaQuery.of(sheetCtx).size.height * 0.85;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          l.snapshotsTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l.saveCurrentState),
                          onPressed: () async {
                            final name = await _showNameDialog(
                              defaultName: l.snapshotDefaultName(
                                _snapshots.snapshots.length + 1,
                              ),
                            );
                            if (name == null || name.isEmpty) return;
                            await _snapshots.add(
                              name,
                              Map.of(_ctrl.faderValues),
                              panValues: Map.of(_ctrl.panValues),
                              busLevel: _ctrl.busFaderValue,
                              busMuted: _ctrl.busMuted,
                              fxReturnValues: Map.of(_ctrl.fxReturnValues),
                              fxReturnPanValues: Map.of(
                                _ctrl.fxReturnPanValues,
                              ),
                              lineInLevel: _ctrl.lineInFaderValue,
                              lineInPan: _ctrl.lineInPanValue,
                            );
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_snapshots.snapshots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(l.noSnapshotsSaved),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _snapshots.snapshots.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final snap = _snapshots.snapshots[i];
                          Future<void> showActions() async {
                            final action = await showDialog<String>(
                              context: context,
                              builder: (d) => SimpleDialog(
                                title: Text(snap.name),
                                children: [
                                  SimpleDialogOption(
                                    onPressed: () =>
                                        Navigator.pop(d, 'overwrite'),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.save_outlined),
                                        const SizedBox(width: 12),
                                        Text(l.saveSnapshot),
                                      ],
                                    ),
                                  ),
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d, 'rename'),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit_outlined),
                                        const SizedBox(width: 12),
                                        Text(l.rename),
                                      ],
                                    ),
                                  ),
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d, 'delete'),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          l.delete,
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 36),
                                        Text(l.cancel),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (!mounted) return;
                            if (action == 'overwrite') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: Text(l.saveSnapshot),
                                  content: Text(
                                    l.overwriteSnapshotConfirm(snap.name),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, false),
                                      child: Text(l.cancel),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, true),
                                      child: Text(l.save),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await _snapshots.overwrite(
                                  i,
                                  Map.of(_ctrl.faderValues),
                                  panValues: Map.of(_ctrl.panValues),
                                  busLevel: _ctrl.busFaderValue,
                                  busMuted: _ctrl.busMuted,
                                  fxReturnValues: Map.of(_ctrl.fxReturnValues),
                                  fxReturnPanValues: Map.of(
                                    _ctrl.fxReturnPanValues,
                                  ),
                                  lineInLevel: _ctrl.lineInFaderValue,
                                  lineInPan: _ctrl.lineInPanValue,
                                );
                                setSheetState(() {});
                              }
                            } else if (action == 'delete') {
                              await _snapshots.remove(i);
                              setSheetState(() {});
                            } else if (action == 'rename') {
                              final name = await _showNameDialog(
                                defaultName: snap.name,
                              );
                              if (name != null && name.isNotEmpty) {
                                await _snapshots.rename(i, name);
                                setSheetState(() {});
                              }
                            }
                          }

                          return ListTile(
                            title: Text(snap.name),
                            subtitle: Text(
                              snap.values.isEmpty
                                  ? l.snapshotNoData
                                  : l.snapshotChannels(snap.values.length),
                              style: TextStyle(
                                color: snap.values.isEmpty
                                    ? Colors.orange
                                    : null,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _restoreSnapshot(snap);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.more_vert),
                              tooltip: l.layoutActionsTooltip,
                              onPressed: showActions,
                            ),
                            onLongPress: showActions,
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _connectionBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final l = AppLocalizations.of(context)!;
        final busTitle = busFaderTitle(
          bus: _ctrl.bus,
          busLinked: _ctrl.busLinked,
          busNames: _ctrl.busNames,
          l: l,
        );
        final busFaderColorKey = busColorKey(
          bus: _ctrl.bus,
          busLinked: _ctrl.busLinked,
        );
        final busFaderColorIndex =
            _layout.busColors[busFaderColorKey] ??
            _ctrl.consoleBusColors[busFaderColorKey] ??
            0;
        final channels = _layout.channels.toList()..sort();
        final visibleFxReturns = _layout.fxReturns.toList()..sort();
        final visibleGroups = _layout.groups
            .asMap()
            .entries
            .where((e) => e.value.visible)
            .toList();
        final busPinned = _layout.busFaderVisible && _layout.busFaderPinned;
        final busInline = _layout.busFaderVisible && !busPinned;
        _pruneFaderControllers([
          ...channels,
          if (_layout.lineInVisible) 'line_in',
          ...visibleFxReturns.map((r) => 'fxrtn_$r'),
          ...visibleGroups.map((e) => 'group_${e.key}'),
          if (busInline) 'bus',
        ]);
        // Derived from the same lists that build the Row below, so the pinch
        // handler's extent math can't drift out of step with what is actually
        // on screen.
        _stripScalableColumns =
            channels.length +
            (_layout.lineInVisible ? 1 : 0) +
            visibleFxReturns.length +
            visibleGroups.length;
        _stripFixedWidth =
            (busInline ? _kBusColumnWidth : 0) +
            MediaQuery.viewPaddingOf(context).left +
            (busPinned ? 0 : MediaQuery.viewPaddingOf(context).right);
        final busFader = Container(
          key: const ValueKey('bus_container'),
          width: _kBusColumnWidth,
          color: const Color.fromARGB(255, 14, 23, 43),
          child: Column(
            children: [
              const SizedBox(height: kPanKnobHeight),
              Expanded(
                child: CustomFader(
                  key: const ValueKey('bus'),
                  label: 'MASTER',
                  oscAddress: _ctrl.busFaderAddress(),
                  service: widget.service,
                  accentColor: Colors.amber,
                  nameColorIndex: busFaderColorIndex,
                  isMain: true,
                  meterLevel: _ctrl.busMeterLevel,
                  meterLevelRight: _ctrl.busPaired
                      ? _ctrl.busMeterLevelRight
                      : null,
                  controller: busPinned
                      ? null
                      : _faderControllers.putIfAbsent(
                          'bus',
                          FaderDragController.new,
                        ),
                ),
              ),
              MetaData(
                metaData: _kForeignGestureArea,
                behavior: HitTestBehavior.opaque,
                child: MuteButton(
                  key: const ValueKey('mute_bus'),
                  isMuted: _ctrl.busMuted == true,
                  label: 'Bus',
                  onToggle: _ctrl.setBusMuted,
                ),
              ),
            ],
          ),
        );
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmDisconnect();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      busTitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ctrl.busMuted == true ? Colors.red : null,
                      ),
                    ),
                  ),
                  if (_ctrl.busMuted == true) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.volume_off, color: Colors.red, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      l.mutedBadge,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (widget.simulator != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.smart_toy_outlined,
                      color: Colors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.simulatorBadge,
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.settings),
                tooltip: l.settingsTooltip,
                onPressed: _openSettings,
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    _snapshots.snapshots.isEmpty
                        ? Icons.bookmark_border
                        : Icons.bookmark,
                  ),
                  tooltip: l.snapshotsTitle,
                  onPressed: _openSnapshotsSheet,
                ),
              ],
            ),
            body: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: AndroidNetworkBinder.wifiAvailable,
                    builder: (_, wifiUp, _) {
                      if (!wifiUp) {
                        // Takes priority over the generic "no data" banner
                        // below: it's more specific (the phone's wifi is
                        // actually down, not just quiet) and fires
                        // immediately instead of waiting for the OSC
                        // heartbeat timeout.
                        return _connectionBanner(
                          icon: Icons.wifi_off,
                          color: Colors.red,
                          text: l.wifiConnectionLost,
                        );
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: widget.service.isReceiving,
                        builder: (_, receiving, _) {
                          if (receiving) return const SizedBox.shrink();
                          return _connectionBanner(
                            icon: Icons
                                .signal_wifi_statusbar_connected_no_internet_4,
                            color: Colors.amber,
                            text: l.noConnection,
                          );
                        },
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUpOrCancel,
                          onPointerCancel: _onPointerUpOrCancel,
                          child: SingleChildScrollView(
                            controller: _faderScrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.only(
                              left: MediaQuery.viewPaddingOf(context).left,
                              right: busPinned
                                  ? 0
                                  : MediaQuery.viewPaddingOf(context).right,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...channels.map(
                                  (ch) => SizedBox(
                                    key: ValueKey(ch),
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          MetaData(
                                            metaData: _kForeignGestureArea,
                                            behavior: HitTestBehavior.opaque,
                                            child: PanKnob(
                                              key: ValueKey('pan_$ch'),
                                              oscAddress: _ctrl.panAddress(ch),
                                              service: widget.service,
                                            ),
                                          )
                                        else
                                          const SizedBox(
                                            height: kPanKnobHeight,
                                          ),
                                        Expanded(
                                          child: CustomFader(
                                            key: ValueKey(ch),
                                            label: _ctrl.channelLabel(ch),
                                            oscAddress: _ctrl.busAddress(ch),
                                            service: widget.service,
                                            meterLevel:
                                                _ctrl.meterLevels[ch - 1],
                                            nameColorIndex:
                                                _layout.channelColors[ch] ??
                                                _ctrl
                                                    .consoleChannelColors[ch] ??
                                                0,
                                            controller: _faderControllers
                                                .putIfAbsent(
                                                  ch,
                                                  FaderDragController.new,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_layout.lineInVisible) ...[
                                  SizedBox(
                                    key: const ValueKey('line_in'),
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          MetaData(
                                            metaData: _kForeignGestureArea,
                                            behavior: HitTestBehavior.opaque,
                                            child: PanKnob(
                                              key: const ValueKey(
                                                'line_in_pan',
                                              ),
                                              oscAddress: _ctrl
                                                  .lineInPanAddress(),
                                              service: widget.service,
                                            ),
                                          )
                                        else
                                          const SizedBox(
                                            height: kPanKnobHeight,
                                          ),
                                        Expanded(
                                          child: CustomFader(
                                            key: const ValueKey('line_in'),
                                            label: 'LINE',
                                            oscAddress: _ctrl.lineInAddress(),
                                            service: widget.service,
                                            meterLevel: _ctrl.lineInMeterL,
                                            meterLevelRight: _ctrl.lineInMeterR,
                                            nameColorIndex:
                                                _layout.lineInColor ??
                                                _ctrl.consoleLineInColor ??
                                                0,
                                            controller: _faderControllers
                                                .putIfAbsent(
                                                  'line_in',
                                                  FaderDragController.new,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                ...visibleFxReturns.map(
                                  (rtn) => SizedBox(
                                    key: ValueKey('fxrtn_$rtn'),
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          MetaData(
                                            metaData: _kForeignGestureArea,
                                            behavior: HitTestBehavior.opaque,
                                            child: PanKnob(
                                              key: ValueKey('fxrtn_pan_$rtn'),
                                              oscAddress: _ctrl
                                                  .fxReturnPanAddress(rtn),
                                              service: widget.service,
                                            ),
                                          )
                                        else
                                          const SizedBox(
                                            height: kPanKnobHeight,
                                          ),
                                        Expanded(
                                          child: CustomFader(
                                            key: ValueKey('fxrtn_$rtn'),
                                            label: 'FX $rtn',
                                            oscAddress: _ctrl.fxReturnAddress(
                                              rtn,
                                            ),
                                            service: widget.service,
                                            accentColor: Colors.teal,
                                            meterLevel:
                                                _ctrl.fxReturnMeterL[rtn - 1],
                                            meterLevelRight:
                                                _ctrl.fxReturnMeterR[rtn - 1],
                                            nameColorIndex:
                                                _layout.fxReturnColors[rtn] ??
                                                _ctrl
                                                    .consoleFxReturnColors[rtn] ??
                                                0,
                                            controller: _faderControllers
                                                .putIfAbsent(
                                                  'fxrtn_$rtn',
                                                  FaderDragController.new,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ...visibleGroups.map(
                                  (e) => Container(
                                    key: ValueKey('group_${e.key}'),
                                    width: _faderWidth,
                                    color: const Color(
                                      0xFF00C853,
                                    ).withValues(alpha: 0.04),
                                    child: Column(
                                      children: [
                                        MetaData(
                                          metaData: _kForeignGestureArea,
                                          behavior: HitTestBehavior.opaque,
                                          child: SizedBox(
                                            height: kPanKnobHeight,
                                            child: Center(
                                              child: IconButton(
                                                icon: Transform.rotate(
                                                  angle: -1.5708,
                                                  child: const Icon(
                                                    Icons.tune,
                                                    size: 30,
                                                  ),
                                                ),
                                                color: const Color(
                                                  0xFF00C853,
                                                ).withValues(alpha: 0.7),
                                                tooltip: l.configureGroup(
                                                  e.value.name,
                                                ),
                                                onPressed: () =>
                                                    _openGroupDetail(e.key),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GroupFader(
                                            key: ValueKey('group_${e.key}'),
                                            label: e.value.name,
                                            channels: e.value.channels.toList(),
                                            fxReturns: e.value.fxReturns
                                                .toList(),
                                            lineIn: e.value.lineIn,
                                            busNum: _ctrl.effectiveBus,
                                            service: widget.service,
                                            nameColorIndex: e.value.colorIndex,
                                            controller: _faderControllers
                                                .putIfAbsent(
                                                  'group_${e.key}',
                                                  FaderDragController.new,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (busInline) busFader,
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (busPinned)
                        Padding(
                          padding: EdgeInsets.only(
                            right: MediaQuery.viewPaddingOf(context).right,
                          ),
                          child: busFader,
                        ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String defaultName;
  const _NameDialog({required this.defaultName});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.snapshotNameTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isNotEmpty) Navigator.pop(context, t);
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                  TextButton(
                    onPressed: () {
                      final t = _controller.text.trim();
                      if (t.isNotEmpty) Navigator.pop(context, t);
                    },
                    child: Text(l.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
