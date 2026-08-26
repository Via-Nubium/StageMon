import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
import '../services/xr18_simulator.dart';
import '../services/android_network_binder.dart';
import '../services/layout_import_service.dart';
import '../widgets/custom_fader.dart';
import '../widgets/mute_button.dart';
import '../widgets/pan_knob.dart';
import '../widgets/group_fader.dart';
import '../models/snapshot_manager.dart';
import '../models/group_fader_config.dart';
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

class _MixerScreenState extends State<MixerScreen> {
  late final MixerController _ctrl;
  Set<int> _selectedChannels = {
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
  };
  Set<int> _selectedFxReturns = {};
  bool _showBusFader = true;
  bool _showLineIn = false;
  bool _busAlwaysVisible = false;
  Map<int, int?> _channelColors = {};
  int? _lineInColor;
  Map<int, int?> _fxReturnColors = {};
  Map<int, int?> _busColors = {};
  List<GroupFaderConfig> _groupConfigs = GroupFaderConfig.defaultConfigs();
  final SnapshotManager _snapshots = SnapshotManager();

  // ── Pinch-to-resize faders ──────────────────────────────────────────────
  static const double _minFaderWidth = 60;
  static const double _maxFaderWidth = 140;
  double _faderWidth = 90;
  final ScrollController _faderScrollController = ScrollController();
  // Fader width at the last onScaleStart — Flutter fires this not just once
  // but on every change in finger count, with its `scale` value reset
  // relative to that moment. See _onScaleUpdate for why this alone (rather
  // than also anchoring to a fixed content position) is what's needed.
  double _scaleStartWidth = 90;
  // Mutual exclusion with individual fader vertical drags: a pinch that
  // starts while a fader is already being dragged is suppressed, and once a
  // pinch *is* active it vetoes new fader drags (see isPinchActive below).
  bool _pinchActive = false;
  int _activeFaderDrags = 0;

  bool _isPinchActive() => _pinchActive;

  void _onFaderDragStart() => _activeFaderDrags++;

  void _onFaderDragEnd() {
    if (_activeFaderDrags > 0) _activeFaderDrags--;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = MixerController(
      service: widget.service,
      simulator: widget.simulator,
    );
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
    final savedBus = prefs.getInt('selected_bus') ?? 1;
    final savedChannelsList = prefs.getStringList('selected_channels');
    final savedShowBus = prefs.getBool('show_bus_fader') ?? true;
    final savedGroups = prefs.getString('group_faders_v1');
    final savedFxReturnsList = prefs.getStringList('selected_fx_returns');
    final savedShowLineIn = prefs.getBool('show_line_in') ?? false;
    final savedBusAlwaysVisible = prefs.getBool('bus_always_visible') ?? false;
    final savedFaderWidth = prefs.getDouble('fader_width');
    final savedChannelColors = prefs.getString('channel_colors_v1');
    final savedLineInColor = prefs.getString('line_in_color_v1');
    final savedFxReturnColors = prefs.getString('fx_return_colors_v1');
    final savedBusColors = prefs.getString('bus_colors_v1');
    if (savedFaderWidth != null) {
      setState(
        () =>
            _faderWidth = savedFaderWidth.clamp(_minFaderWidth, _maxFaderWidth),
      );
    }
    if (savedChannelsList != null) {
      setState(
        () => _selectedChannels = savedChannelsList.map(int.parse).toSet(),
      );
    }
    if (savedFxReturnsList != null) {
      setState(
        () => _selectedFxReturns = savedFxReturnsList.map(int.parse).toSet(),
      );
    }
    setState(() {
      _showBusFader = savedShowBus;
      _showLineIn = savedShowLineIn;
      _busAlwaysVisible = savedBusAlwaysVisible;
    });
    if (savedGroups != null) {
      try {
        setState(
          () => _groupConfigs = GroupFaderConfig.fromJsonList(savedGroups),
        );
      } catch (_) {}
    }
    if (savedChannelColors != null) {
      try {
        final decoded = jsonDecode(savedChannelColors) as Map<String, dynamic>;
        setState(
          () => _channelColors = decoded.map(
            (k, v) => MapEntry(int.parse(k), v as int?),
          ),
        );
      } catch (_) {}
    }
    if (savedLineInColor != null) {
      try {
        setState(() => _lineInColor = jsonDecode(savedLineInColor) as int?);
      } catch (_) {}
    }
    if (savedFxReturnColors != null) {
      try {
        final decoded = jsonDecode(savedFxReturnColors) as Map<String, dynamic>;
        setState(
          () => _fxReturnColors = decoded.map(
            (k, v) => MapEntry(int.parse(k), v as int?),
          ),
        );
      } catch (_) {}
    }
    if (savedBusColors != null) {
      try {
        final decoded = jsonDecode(savedBusColors) as Map<String, dynamic>;
        setState(
          () => _busColors = decoded.map(
            (k, v) => MapEntry(int.parse(k), v as int?),
          ),
        );
      } catch (_) {}
    }
    if (savedBus != _ctrl.bus) _ctrl.changeBus(savedBus);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    widget.simulator?.stop();
    _faderScrollController.dispose();
    super.dispose();
  }

  // ── Pinch-to-resize faders ──────────────────────────────────────────────
  //
  // Backed by Flutter's own ScaleGestureRecognizer (via GestureDetector's
  // onScale*) rather than a raw pointer listener: it's the same primitive
  // pan/pinch apps like Google Maps use, so a finger can be added or
  // removed mid-gesture and panning keeps going without a jump.
  //
  // Panning and the resize's anchor-compensation are both applied
  // incrementally (from the previous frame's offset/width), not recomputed
  // from a fixed gesture-start baseline. That matters specifically at the
  // instant the finger count changes: Flutter fires onScaleEnd + a fresh
  // onScaleStart right there, and that onStart's focal point is already the
  // *post-movement* position — any movement coinciding with that reconfigure
  // would be silently lost by a baseline-relative formula. focalPointDelta
  // stays correct across that boundary, so building on it (and on the
  // previous width, not a remembered starting width) avoids the gap.
  //
  // The SingleChildScrollView uses NeverScrollableScrollPhysics — all
  // scrolling here is driven manually via jumpTo, so its own drag
  // recognizer doesn't also compete for the same touches.
  void _onScaleStart(ScaleStartDetails d) {
    _scaleStartWidth = _faderWidth;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final previousWidth = _faderWidth;
    double newWidth = previousWidth;
    if (d.pointerCount >= 2 && _activeFaderDrags == 0) {
      _pinchActive = true;
      newWidth = (_scaleStartWidth * d.scale).clamp(
        _minFaderWidth,
        _maxFaderWidth,
      );
    } else {
      _pinchActive = false;
    }
    if (_faderScrollController.hasClients) {
      double offset = _faderScrollController.offset;
      if (newWidth != previousWidth) {
        final ratio = newWidth / previousWidth;
        offset = ratio * offset + (ratio - 1) * d.localFocalPoint.dx;
      }
      offset -= d.focalPointDelta.dx;
      final pos = _faderScrollController.position;
      _faderScrollController.jumpTo(
        offset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
    }
    if (newWidth != _faderWidth) setState(() => _faderWidth = newWidth);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _pinchActive = false;
    // Safety net: Flutter's drag recognizers can reassign themselves
    // between simultaneous pointers, so don't trust start/end pairing
    // alone to keep this honest — a true gesture end means nothing can
    // still be mid-drag.
    if (d.pointerCount == 0) _activeFaderDrags = 0;
    SharedPreferences.getInstance().then(
      (p) => p.setDouble('fader_width', _faderWidth),
    );
  }

  // ── Navigation / dialogs ──────────────────────────────────────────────────

  void _openGroupDetail(int groupIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          configs: _groupConfigs,
          groupIndex: groupIndex,
          busNum: _ctrl.effectiveBus,
          busPaired: _ctrl.busPaired,
          channelNames: _ctrl.channelNames,
          channelColors: _channelColors,
          lineInColor: _lineInColor,
          fxReturnColors: _fxReturnColors,
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
            setState(() => _groupConfigs = newConfigs);
            SharedPreferences.getInstance().then(
              (p) => p.setString(
                'group_faders_v1',
                GroupFaderConfig.toJsonList(newConfigs),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openSettings({String? pendingImportContent}) async {
    final result =
        await Navigator.push<
          (
            Set<int>,
            bool,
            int,
            List<GroupFaderConfig>,
            Set<int>,
            bool,
            bool,
            Map<int, int?>,
            int?,
            Map<int, int?>,
            Map<int, int?>,
          )
        >(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              selectedChannels: _selectedChannels,
              channelNames: _ctrl.channelNames,
              busNames: _ctrl.busNames,
              busLinked: _ctrl.busLinked,
              showBusFader: _showBusFader,
              bus: _ctrl.bus,
              groupConfigs: _groupConfigs,
              selectedFxReturns: _selectedFxReturns,
              showLineIn: _showLineIn,
              busAlwaysVisible: _busAlwaysVisible,
              channelColors: _channelColors,
              lineInColor: _lineInColor,
              fxReturnColors: _fxReturnColors,
              consoleChannelColors: _ctrl.consoleChannelColors,
              consoleLineInColor: _ctrl.consoleLineInColor,
              consoleFxReturnColors: _ctrl.consoleFxReturnColors,
              busColors: _busColors,
              consoleBusColors: _ctrl.consoleBusColors,
              consoleModel: widget.consoleModel,
              pendingImportContent: pendingImportContent,
            ),
          ),
        );
    if (result != null && mounted) {
      _ctrl.changeBus(result.$3);
      setState(() {
        _selectedChannels = result.$1;
        _showBusFader = result.$2;
        _groupConfigs = result.$4;
        _selectedFxReturns = result.$5;
        _showLineIn = result.$6;
        _busAlwaysVisible = result.$7;
        _channelColors = result.$8;
        _lineInColor = result.$9;
        _fxReturnColors = result.$10;
        _busColors = result.$11;
      });
      SharedPreferences.getInstance().then((p) {
        p.setStringList(
          'selected_channels',
          result.$1.map((e) => e.toString()).toList(),
        );
        p.setBool('show_bus_fader', result.$2);
        p.setString('group_faders_v1', GroupFaderConfig.toJsonList(result.$4));
        p.setStringList(
          'selected_fx_returns',
          result.$5.map((e) => e.toString()).toList(),
        );
        p.setBool('show_line_in', result.$6);
        p.setBool('bus_always_visible', result.$7);
        p.setString(
          'channel_colors_v1',
          jsonEncode(result.$8.map((k, v) => MapEntry(k.toString(), v))),
        );
        p.setString('line_in_color_v1', jsonEncode(result.$9));
        p.setString(
          'fx_return_colors_v1',
          jsonEncode(result.$10.map((k, v) => MapEntry(k.toString(), v))),
        );
        p.setString(
          'bus_colors_v1',
          jsonEncode(result.$11.map((k, v) => MapEntry(k.toString(), v))),
        );
      });
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
    final channelsToRestore = Set<int>.from(_selectedChannels);
    for (final group in _groupConfigs) {
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
      if (!_selectedFxReturns.contains(rtn)) continue;
      final value = snapshot.fxReturnValues[rtn];
      if (value != null) _ctrl.service.send(_ctrl.fxReturnAddress(rtn), value);
      if (_ctrl.busPaired) {
        final pan = snapshot.fxReturnPanValues[rtn];
        if (pan != null) _ctrl.service.send(_ctrl.fxReturnPanAddress(rtn), pan);
      }
    }
    if (_showLineIn) {
      if (snapshot.lineInLevel != null) {
        _ctrl.service.send(_ctrl.lineInAddress(), snapshot.lineInLevel!);
      }
      if (_ctrl.busPaired && snapshot.lineInPan != null) {
        _ctrl.service.send(_ctrl.lineInPanAddress(), snapshot.lineInPan!);
      }
    }
    if (_showBusFader) {
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
                          return ListTile(
                            title: Text(snap.name),
                            subtitle: Text(
                              snap.values.isEmpty
                                  ? l.snapshotNoData
                                  : snap.panValues.isNotEmpty
                                  ? l.snapshotWithPan(snap.values.length)
                                  : l.snapshotChannels(snap.values.length),
                              style: TextStyle(
                                color: snap.values.isEmpty
                                    ? Colors.orange
                                    : null,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.restore_rounded),
                              tooltip: l.restoreTooltip,
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _restoreSnapshot(snap);
                              },
                            ),
                            onLongPress: () async {
                              final action = await showDialog<String>(
                                context: context,
                                builder: (d) => SimpleDialog(
                                  title: Text(snap.name),
                                  children: [
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(d, 'overwrite'),
                                      child: Text(l.saveSnapshot),
                                    ),
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(d, 'rename'),
                                      child: Text(l.rename),
                                    ),
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(d, 'delete'),
                                      child: Text(
                                        l.delete,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                    SimpleDialogOption(
                                      onPressed: () => Navigator.pop(d),
                                      child: Text(l.cancel),
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
                                        onPressed: () =>
                                            Navigator.pop(d, false),
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
                                    fxReturnValues: Map.of(
                                      _ctrl.fxReturnValues,
                                    ),
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
                            },
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
            _busColors[busFaderColorKey] ??
            _ctrl.consoleBusColors[busFaderColorKey] ??
            0;
        final channels = _selectedChannels.toList()..sort();
        final visibleFxReturns = _selectedFxReturns.toList()..sort();
        final visibleGroups = _groupConfigs
            .asMap()
            .entries
            .where((e) => e.value.visible)
            .toList();
        final busPinned = _showBusFader && _busAlwaysVisible;
        final busFader = Container(
          width: 90,
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
                  isPinchActive: _isPinchActive,
                  onDragActiveStart: _onFaderDragStart,
                  onDragActiveEnd: _onFaderDragEnd,
                ),
              ),
              MuteButton(
                key: const ValueKey('mute_bus'),
                isMuted: _ctrl.busMuted == true,
                label: 'Bus',
                onToggle: _ctrl.setBusMuted,
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
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
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
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          PanKnob(
                                            key: ValueKey('pan_$ch'),
                                            oscAddress: _ctrl.panAddress(ch),
                                            service: widget.service,
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
                                                _channelColors[ch] ??
                                                _ctrl
                                                    .consoleChannelColors[ch] ??
                                                0,
                                            isPinchActive: _isPinchActive,
                                            onDragActiveStart:
                                                _onFaderDragStart,
                                            onDragActiveEnd: _onFaderDragEnd,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_showLineIn) ...[
                                  SizedBox(
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          PanKnob(
                                            key: const ValueKey('line_in_pan'),
                                            oscAddress: _ctrl
                                                .lineInPanAddress(),
                                            service: widget.service,
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
                                                _lineInColor ??
                                                _ctrl.consoleLineInColor ??
                                                0,
                                            isPinchActive: _isPinchActive,
                                            onDragActiveStart:
                                                _onFaderDragStart,
                                            onDragActiveEnd: _onFaderDragEnd,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                ...visibleFxReturns.map(
                                  (rtn) => SizedBox(
                                    width: _faderWidth,
                                    child: Column(
                                      children: [
                                        if (_ctrl.busPaired)
                                          PanKnob(
                                            key: ValueKey('fxrtn_pan_$rtn'),
                                            oscAddress: _ctrl
                                                .fxReturnPanAddress(rtn),
                                            service: widget.service,
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
                                                _fxReturnColors[rtn] ??
                                                _ctrl
                                                    .consoleFxReturnColors[rtn] ??
                                                0,
                                            isPinchActive: _isPinchActive,
                                            onDragActiveStart:
                                                _onFaderDragStart,
                                            onDragActiveEnd: _onFaderDragEnd,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ...visibleGroups.map(
                                  (e) => Container(
                                    width: _faderWidth,
                                    color: const Color(
                                      0xFF00C853,
                                    ).withValues(alpha: 0.04),
                                    child: Column(
                                      children: [
                                        SizedBox(
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
                                            isPinchActive: _isPinchActive,
                                            onDragActiveStart:
                                                _onFaderDragStart,
                                            onDragActiveEnd: _onFaderDragEnd,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_showBusFader && !busPinned) busFader,
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
