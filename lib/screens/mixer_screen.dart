import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../services/osc_service.dart';
import '../services/xr18_simulator.dart';
import '../services/android_network_binder.dart';
import '../services/layout_import_service.dart';
import '../services/screen_awake_service.dart';
import '../widgets/custom_fader.dart';
import '../widgets/mute_button.dart';
import '../widgets/pan_knob.dart';
import '../widgets/fader_column.dart';
import '../widgets/fader_strip.dart';
import '../widgets/group_fader.dart';
import '../widgets/member_column.dart';
import '../widgets/snapshots_sheet.dart';
import '../models/snapshot_manager.dart';
import '../models/mixer_layout_state.dart';
import '../controllers/fader_strip_controller.dart';
import '../controllers/mixer_controller.dart';
import '../utils/bus_title.dart';
import '../utils/group_members.dart';
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
  MixerLayoutState _layout = MixerLayoutState.defaults();
  final SnapshotManager _snapshots = SnapshotManager();

  // Owns the strip's horizontal scroll, its pinch-to-resize width and the
  // routing of every touch that lands on it.
  final FaderStripController _strip = FaderStripController(
    widthPrefsKey: 'fader_width',
  );

  @override
  void initState() {
    super.initState();
    _ctrl = MixerController(
      service: widget.service,
      simulator: widget.simulator,
    );
    ScreenAwakeService.start();
    _strip.addListener(_onStripChanged);
    _strip.loadSavedWidth();
    _snapshots.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadLayout();
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

  void _loadLayout() async {
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
    _strip.dispose();
    super.dispose();
  }

  void _onStripChanged() {
    if (mounted) setState(() {});
  }

  // ── Navigation / dialogs ──────────────────────────────────────────────────

  void _openGroupDetail(int groupIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupIndex: groupIndex,
          ctrl: _ctrl,
          layout: _layout,
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
          fxReturnNames: _ctrl.fxReturnNames,
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

  FaderSnapshot _captureCurrentState(String name) => FaderSnapshot(
    name: name,
    values: Map.of(_ctrl.faderValues),
    panValues: Map.of(_ctrl.panValues),
    busLevel: _ctrl.busFaderValue,
    busMuted: _ctrl.busMuted,
    fxReturnValues: Map.of(_ctrl.fxReturnValues),
    fxReturnPanValues: Map.of(_ctrl.fxReturnPanValues),
    lineInLevel: _ctrl.lineInFaderValue,
    lineInPan: _ctrl.lineInPanValue,
  );

  void _openSnapshotsSheet() {
    showSnapshotsSheet(
      context: context,
      snapshots: _snapshots,
      captureCurrent: _captureCurrentState,
      onRestore: _restoreSnapshot,
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
        final members = groupMembers(
          channels: _layout.channels,
          fxReturns: _layout.fxReturns,
          lineIn: _layout.lineInVisible,
        );
        final visibleGroups = _layout.groups
            .asMap()
            .entries
            .where((e) => e.value.visible)
            .toList();
        final busPinned = _layout.busFaderVisible && _layout.busFaderPinned;
        final busInline = _layout.busFaderVisible && !busPinned;
        // Built from the same lists the columns below are, so a drag
        // controller can't be pruned out from under a column still using it.
        _strip.pruneControllers([
          ...members,
          ...visibleGroups.map((e) => 'group_${e.key}'),
          if (busInline) 'bus',
        ]);
        final busFader = FaderColumn(
          key: const ValueKey('bus_container'),
          width: kBusColumnWidth,
          background: const Color.fromARGB(255, 14, 23, 43),
          head: const SizedBox(height: kPanKnobHeight),
          footer: ForeignGestureArea(
            child: MuteButton(
              key: const ValueKey('mute_bus'),
              isMuted: _ctrl.busMuted == true,
              label: 'Bus',
              onToggle: _ctrl.setBusMuted,
            ),
          ),
          child: CustomFader(
            key: const ValueKey('bus'),
            label: 'MASTER',
            oscAddress: _ctrl.busFaderAddress(),
            service: widget.service,
            accentColor: Colors.amber,
            nameColorIndex: busFaderColorIndex,
            isMain: true,
            meterLevel: _ctrl.busMeterLevel,
            meterLevelRight: _ctrl.busPaired ? _ctrl.busMeterLevelRight : null,
            controller: busPinned ? null : _strip.controllerFor('bus'),
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
                        child: FaderStrip(
                          controller: _strip,
                          padding: EdgeInsets.only(
                            left: MediaQuery.viewPaddingOf(context).left,
                            right: busPinned
                                ? 0
                                : MediaQuery.viewPaddingOf(context).right,
                          ),
                          trailing: busInline ? busFader : null,
                          trailingWidth: busInline ? kBusColumnWidth : 0,
                          columns: [
                            ...members.map(
                              (m) => MemberColumn(
                                key: ValueKey(m),
                                member: m,
                                ctrl: _ctrl,
                                layout: _layout,
                                strip: _strip,
                              ),
                            ),
                            ...visibleGroups.map(
                              (e) => FaderColumn(
                                key: ValueKey('group_${e.key}'),
                                width: _strip.faderWidth,
                                head: ForeignGestureArea(
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
                                        tooltip: l.configureGroup(e.value.name),
                                        onPressed: () =>
                                            _openGroupDetail(e.key),
                                      ),
                                    ),
                                  ),
                                ),
                                child: GroupFader(
                                  key: ValueKey('group_${e.key}'),
                                  label: e.value.name,
                                  channels: e.value.channels.toList(),
                                  fxReturns: e.value.fxReturns.toList(),
                                  lineIn: e.value.lineIn,
                                  busNum: _ctrl.effectiveBus,
                                  service: widget.service,
                                  nameColorIndex: e.value.colorIndex,
                                  controller: _strip.controllerFor(
                                    'group_${e.key}',
                                  ),
                                ),
                              ),
                            ),
                          ],
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
