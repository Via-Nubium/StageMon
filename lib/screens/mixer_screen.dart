import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
import '../widgets/custom_fader.dart';
import '../widgets/mute_button.dart';
import '../widgets/pan_knob.dart';
import '../widgets/group_fader.dart';
import '../models/snapshot_manager.dart';
import '../models/group_fader_config.dart';
import '../controllers/mixer_controller.dart';
import 'settings_screen.dart';
import 'group_detail_screen.dart';

class MixerScreen extends StatefulWidget {
  final OscService service;

  const MixerScreen({super.key, required this.service});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  late final MixerController _ctrl;
  Set<int> _selectedChannels = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
  Set<int> _selectedFxReturns = {};
  bool _showAuxFader = true;
  bool _showLineIn = false;
  List<GroupFaderConfig> _groupConfigs = GroupFaderConfig.defaultConfigs();
  final SnapshotManager _snapshots = SnapshotManager();

  @override
  void initState() {
    super.initState();
    _ctrl = MixerController(service: widget.service);
    _snapshots.load().then((_) { if (mounted) setState(() {}); });
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedBus = prefs.getInt('selected_bus') ?? 1;
    final savedChannelsList = prefs.getStringList('selected_channels');
    final savedShowAux = prefs.getBool('show_aux_fader') ?? true;
    final savedGroups = prefs.getString('group_faders_v1');
    final savedFxReturnsList = prefs.getStringList('selected_fx_returns');
    final savedShowLineIn = prefs.getBool('show_line_in') ?? false;
    if (savedChannelsList != null) {
      setState(() => _selectedChannels = savedChannelsList.map(int.parse).toSet());
    }
    if (savedFxReturnsList != null) {
      setState(() => _selectedFxReturns = savedFxReturnsList.map(int.parse).toSet());
    }
    setState(() {
      _showAuxFader = savedShowAux;
      _showLineIn = savedShowLineIn;
    });
    if (savedGroups != null) {
      try {
        setState(() => _groupConfigs = GroupFaderConfig.fromJsonList(savedGroups));
      } catch (_) {}
    }
    if (savedBus != _ctrl.bus) _ctrl.changeBus(savedBus);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
          service: widget.service,
          meterLevels: _ctrl.meterLevels,
          fxReturnMeterL: _ctrl.fxReturnMeterL,
          fxReturnMeterR: _ctrl.fxReturnMeterR,
          lineInMeterL: _ctrl.lineInMeterL,
          lineInMeterR: _ctrl.lineInMeterR,
          onConfigsChanged: (newConfigs) {
            setState(() => _groupConfigs = newConfigs);
            SharedPreferences.getInstance().then(
              (p) => p.setString('group_faders_v1', GroupFaderConfig.toJsonList(newConfigs)),
            );
          },
        ),
      ),
    );
  }

  void _openSettings() async {
    final result = await Navigator.push<(Set<int>, bool, int, List<GroupFaderConfig>, Set<int>, bool)>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          selectedChannels: _selectedChannels,
          channelNames: _ctrl.channelNames,
          showAuxFader: _showAuxFader,
          bus: _ctrl.bus,
          groupConfigs: _groupConfigs,
          selectedFxReturns: _selectedFxReturns,
          showLineIn: _showLineIn,
        ),
      ),
    );
    if (result != null && mounted) {
      _ctrl.changeBus(result.$3);
      setState(() {
        _selectedChannels = result.$1;
        _showAuxFader = result.$2;
        _groupConfigs = result.$4;
        _selectedFxReturns = result.$5;
        _showLineIn = result.$6;
      });
      SharedPreferences.getInstance().then((p) {
        p.setStringList('selected_channels', result.$1.map((e) => e.toString()).toList());
        p.setBool('show_aux_fader', result.$2);
        p.setString('group_faders_v1', GroupFaderConfig.toJsonList(result.$4));
        p.setStringList('selected_fx_returns', result.$5.map((e) => e.toString()).toList());
        p.setBool('show_line_in', result.$6);
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
    if (_showAuxFader) {
      if (snapshot.auxLevel != null) {
        _ctrl.service.send(_ctrl.auxAddress(), snapshot.auxLevel!);
      }
      if (snapshot.auxMuted != null) {
        _ctrl.setAuxMuted(snapshot.auxMuted!);
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
          final maxSheetHeight =
              MediaQuery.of(sheetCtx).size.height * 0.85;
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
                            defaultName: l.snapshotDefaultName(_snapshots.snapshots.length + 1),
                          );
                          if (name == null || name.isEmpty) return;
                          await _snapshots.add(
                            name,
                            Map.of(_ctrl.faderValues),
                            panValues: Map.of(_ctrl.panValues),
                            auxLevel: _ctrl.auxFaderValue,
                            auxMuted: _ctrl.auxMuted,
                            fxReturnValues: Map.of(_ctrl.fxReturnValues),
                            fxReturnPanValues: Map.of(_ctrl.fxReturnPanValues),
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _snapshots.snapshots.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
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
                              color: snap.values.isEmpty ? Colors.orange : null,
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
                                    onPressed: () => Navigator.pop(d, 'overwrite'),
                                    child: Text(l.saveSnapshot),
                                  ),
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d, 'rename'),
                                    child: Text(l.rename),
                                  ),
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d, 'delete'),
                                    child: Text(
                                      l.delete,
                                      style: const TextStyle(color: Colors.red),
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
                                  content: Text(l.overwriteSnapshotConfirm(snap.name)),
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
                                  auxLevel: _ctrl.auxFaderValue,
                                  auxMuted: _ctrl.auxMuted,
                                  fxReturnValues: Map.of(_ctrl.fxReturnValues),
                                  fxReturnPanValues: Map.of(_ctrl.fxReturnPanValues),
                                  lineInLevel: _ctrl.lineInFaderValue,
                                  lineInPan: _ctrl.lineInPanValue,
                                );
                                setSheetState(() {});
                              }
                            } else if (action == 'delete') {
                              await _snapshots.remove(i);
                              setSheetState(() {});
                            } else if (action == 'rename') {
                              final name =
                                  await _showNameDialog(defaultName: snap.name);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final l = AppLocalizations.of(context)!;
        final busTitle = _ctrl.busPaired
            ? l.busTitleStereo(_ctrl.effectiveBus, _ctrl.effectiveBus + 1)
            : l.busTitleMono(_ctrl.bus);
        final channels = _selectedChannels.toList()..sort();
        final visibleFxReturns = _selectedFxReturns.toList()..sort();
        final visibleGroups = _groupConfigs.asMap().entries
            .where((e) => e.value.visible)
            .toList();
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmDisconnect();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.appTitle(busTitle)),
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
                ValueListenableBuilder<bool>(
                  valueListenable: widget.service.isReceiving,
                  builder: (_, receiving, _) {
                    final showNoConn = !receiving;
                    final showMuted = _ctrl.auxMuted == true;
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: (showNoConn || showMuted)
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                              child: Row(
                                children: [
                                  if (showNoConn) ...[
                                    const Icon(Icons.signal_wifi_statusbar_connected_no_internet_4,
                                        color: Colors.amber, size: 16),
                                    const SizedBox(width: 6),
                                    Text(l.noConnection,
                                        style: const TextStyle(color: Colors.amber, fontSize: 13)),
                                  ],
                                  if (showNoConn && showMuted)
                                    const SizedBox(width: 16),
                                  if (showMuted) ...[
                                    const Icon(Icons.volume_off, color: Colors.red, size: 16),
                                    const SizedBox(width: 6),
                                    Text(l.auxBusMuted(busTitle),
                                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                                  ],
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(
                      left: MediaQuery.viewPaddingOf(context).left,
                      right: MediaQuery.viewPaddingOf(context).right,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...channels.map((ch) => SizedBox(
                              width: 90,
                              child: Column(
                                children: [
                                  if (_ctrl.busPaired)
                                    PanKnob(
                                      key: ValueKey('pan_$ch'),
                                      oscAddress: _ctrl.panAddress(ch),
                                      service: widget.service,
                                    )
                                  else
                                    const SizedBox(height: kPanKnobHeight),
                                  Expanded(
                                    child: CustomFader(
                                      key: ValueKey(ch),
                                      label: _ctrl.channelLabel(ch),
                                      oscAddress: _ctrl.busAddress(ch),
                                      service: widget.service,
                                      meterLevel: _ctrl.meterLevels[ch - 1],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (_showLineIn) ...[
                          Container(
                            width: 90,
                            color: Colors.deepOrange.withValues(alpha: 0.04),
                            child: Column(
                              children: [
                                if (_ctrl.busPaired)
                                  PanKnob(
                                    key: const ValueKey('line_in_pan'),
                                    oscAddress: _ctrl.lineInPanAddress(),
                                    service: widget.service,
                                  )
                                else
                                  const SizedBox(height: kPanKnobHeight),
                                Expanded(
                                  child: CustomFader(
                                    key: const ValueKey('line_in'),
                                    label: 'LINE',
                                    oscAddress: _ctrl.lineInAddress(),
                                    service: widget.service,
                                    meterLevel: _ctrl.lineInMeterL,
                                    meterLevelRight: _ctrl.lineInMeterR,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        ...visibleFxReturns.map((rtn) => SizedBox(
                              width: 90,
                              child: Column(
                                children: [
                                  if (_ctrl.busPaired)
                                    PanKnob(
                                      key: ValueKey('fxrtn_pan_$rtn'),
                                      oscAddress: _ctrl.fxReturnPanAddress(rtn),
                                      service: widget.service,
                                    )
                                  else
                                    const SizedBox(height: kPanKnobHeight),
                                  Expanded(
                                    child: CustomFader(
                                      key: ValueKey('fxrtn_$rtn'),
                                      label: 'FX $rtn',
                                      oscAddress: _ctrl.fxReturnAddress(rtn),
                                      service: widget.service,
                                      accentColor: Colors.teal,
                                      meterLevel: _ctrl.fxReturnMeterL[rtn - 1],
                                      meterLevelRight: _ctrl.fxReturnMeterR[rtn - 1],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        ...visibleGroups.map((e) => Container(
                              width: 90,
                              color: const Color(0xFF00C853).withValues(alpha: 0.04),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: kPanKnobHeight,
                                    child: Center(
                                      child: IconButton(
                                        icon: const Icon(Icons.tune, size: 30),
                                        color: const Color(0xFF00C853).withValues(alpha: 0.7),
                                        tooltip: l.configureGroup(e.value.name),
                                        onPressed: () => _openGroupDetail(e.key),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GroupFader(
                                      key: ValueKey('group_${e.key}'),
                                      label: e.value.name,
                                      channels: e.value.channels.toList(),
                                      fxReturns: e.value.fxReturns.toList(),
                                      lineIn: e.value.lineIn,
                                      busNum: _ctrl.effectiveBus,
                                      service: widget.service,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (_showAuxFader) ...[
                          SizedBox(
                            width: 90,
                            child: Column(
                              children: [
                                const SizedBox(height: kPanKnobHeight),
                                Expanded(
                                  child: CustomFader(
                                    key: const ValueKey('aux'),
                                    label: l.auxFaderChannelLabel(busTitle),
                                    oscAddress: _ctrl.auxAddress(),
                                    service: widget.service,
                                    accentColor: Colors.amber,
                                    isMain: true,
                                    meterLevel: _ctrl.auxMeterLevel,
                                    meterLevelRight: _ctrl.busPaired ? _ctrl.auxMeterLevelRight : null,
                                  ),
                                ),
                                MuteButton(
                                  key: const ValueKey('mute_aux'),
                                  isMuted: _ctrl.auxMuted == true,
                                  label: l.auxFaderChannelLabel(busTitle),
                                  onToggle: _ctrl.setAuxMuted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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
              Text(l.snapshotNameTitle, style: Theme.of(context).textTheme.titleLarge),
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
