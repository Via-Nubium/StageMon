import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/group_fader_config.dart';
import '../models/channel_color.dart';
import '../models/mixer_layout_state.dart';
import '../utils/bus_title.dart';
import '../widgets/bus_picker_sheet.dart';
import '../widgets/channel_color_sheet.dart';
import '../widgets/color_handle_badge.dart';
import '../models/saved_layout.dart';
import 'about_screen.dart';
import 'group_config_screen.dart';
import 'layouts_screen.dart';

class SettingsScreen extends StatefulWidget {
  final MixerLayoutState layout;
  final Map<int, String> channelNames;
  final Map<int, String> fxReturnNames;
  final Map<int, String> busNames;
  final Map<int, bool> busLinked;
  final Map<int, int> consoleChannelColors;
  final int? consoleLineInColor;
  final Map<int, int> consoleFxReturnColors;
  final Map<int, int> consoleBusColors;
  final String consoleModel;
  // See LayoutsScreen.initialImportContent — forwarded straight through so
  // Settings opens directly on Layouts when arriving this way.
  final String? pendingImportContent;

  const SettingsScreen({
    super.key,
    required this.layout,
    required this.channelNames,
    required this.fxReturnNames,
    required this.busNames,
    required this.busLinked,
    required this.consoleChannelColors,
    required this.consoleLineInColor,
    required this.consoleFxReturnColors,
    required this.consoleBusColors,
    required this.consoleModel,
    this.pendingImportContent,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MixerLayoutState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.layout;
    final pending = widget.pendingImportContent;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openLayouts(initialImportContent: pending);
      });
    }
  }

  // The bus number a color is stored under: the pair's base when the
  // current bus is linked, otherwise the bus itself.
  int get _busColorKey =>
      busColorKey(bus: _state.bus, busLinked: widget.busLinked);

  // Console color only — no override — to stay consistent with what the
  // bus picker sheet shows for every bus.
  Widget _busColorDot() {
    final color = channelColorByIndex(
      widget.consoleBusColors[_busColorKey] ?? 0,
    );
    return ColorDot(background: color.background, foreground: color.foreground);
  }

  void _pop() => Navigator.pop(context, _state);

  // Channels, then LINE, then FX returns, then group faders, then the aux
  // bus — the order the </> arrows in the color sheet step through,
  // independent of which of them are visible. Group faders have no console
  // counterpart (allowConsoleSync: false) since they're a local combo, not
  // a real console channel.
  List<ColorableFader> _colorableFaders() => [
    for (var ch = 1; ch <= 16; ch++)
      ColorableFader(
        label: widget.channelNames[ch] ?? 'Ch ${ch.toString().padLeft(2, '0')}',
        colorIndex: _state.channelColors[ch],
        onChanged: (index) => setState(() {
          _state = _state.copyWith(
            channelColors: {..._state.channelColors, ch: index},
          );
        }),
        consoleColorIndex: widget.consoleChannelColors[ch],
      ),
    ColorableFader(
      label: 'LINE',
      colorIndex: _state.lineInColor,
      onChanged: (index) =>
          setState(() => _state = _state.copyWith(lineInColor: index)),
      consoleColorIndex: widget.consoleLineInColor,
    ),
    for (var rtn = 1; rtn <= 4; rtn++)
      ColorableFader(
        label: widget.fxReturnNames[rtn] ?? 'FX $rtn',
        colorIndex: _state.fxReturnColors[rtn],
        onChanged: (index) => setState(() {
          _state = _state.copyWith(
            fxReturnColors: {..._state.fxReturnColors, rtn: index},
          );
        }),
        consoleColorIndex: widget.consoleFxReturnColors[rtn],
      ),
    for (var i = 0; i < _state.groups.length; i++)
      ColorableFader(
        label: _state.groups[i].name,
        colorIndex: _state.groups[i].colorIndex,
        onChanged: (index) => setState(() {
          final groups = List<GroupFaderConfig>.of(_state.groups);
          groups[i] = groups[i].copyWith(colorIndex: index);
          _state = _state.copyWith(groups: groups);
        }),
        consoleColorIndex: null,
        allowConsoleSync: false,
      ),
    ColorableFader(
      label: _busFaderChipLabel(),
      colorIndex: _state.busColors[_busColorKey],
      onChanged: (index) => setState(() {
        _state = _state.copyWith(
          busColors: {..._state.busColors, _busColorKey: index},
        );
      }),
      consoleColorIndex: widget.consoleBusColors[_busColorKey],
    ),
  ];

  // Position of group i within _colorableFaders(): 16 channels + LINE + 4
  // FX returns come first.
  int _groupColorPosition(int i) => 21 + i;

  void _openColorSheet(int position) {
    showChannelColorSheet(
      context: context,
      items: _colorableFaders(),
      initialPosition: position,
    );
  }

  Widget _cardSubLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: Colors.white54,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _hairline() => Container(
    height: 1,
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    color: Colors.white.withValues(alpha: 0.08),
  );

  Widget _colorableChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required int? colorIndex,
    required int? consoleColorIndex,
    VoidCallback? onLongPress,
  }) {
    final color = channelColorByIndex(colorIndex ?? consoleColorIndex ?? 0);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Theme(
            data: Theme.of(
              context,
            ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: FilterChip(
              label: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
              selected: selected,
              onSelected: onSelected,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: IgnorePointer(
              child: Center(
                child: ColorHandleBadge(
                  background: color.background,
                  foreground: color.foreground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _disconnect() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  List<BusOption> _busOptions() => [
    for (final odd in [1, 3, 5])
      if (widget.busLinked[odd] ?? false)
        BusOption(
          value: odd,
          label: _pairLabel(odd, odd + 1),
          matches: [odd, odd + 1],
          colorIndex: widget.consoleBusColors[odd] ?? 0,
        )
      else ...[
        BusOption(
          value: odd,
          label: _busLabel(odd),
          matches: [odd],
          colorIndex: widget.consoleBusColors[odd] ?? 0,
        ),
        BusOption(
          value: odd + 1,
          label: _busLabel(odd + 1),
          matches: [odd + 1],
          colorIndex: widget.consoleBusColors[odd + 1] ?? 0,
        ),
      ],
  ];

  String _currentBusLabel() {
    for (final o in _busOptions()) {
      if (o.matches.contains(_state.bus)) return o.label;
    }
    return _busLabel(_state.bus);
  }

  Future<void> _openLayouts({String? initialImportContent}) async {
    final result = await Navigator.push<SavedLayout>(
      context,
      MaterialPageRoute(
        builder: (_) => LayoutsScreen(
          layout: _state,
          consoleModel: widget.consoleModel,
          initialImportContent: initialImportContent,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        // result.bus null means "leave the current bus alone" — see
        // SavedLayout.bus.
        _state = result.resolvedLayout(_state.bus);
      });
    }
  }

  void _openBusPicker() {
    showBusPickerSheet(
      context: context,
      options: _busOptions(),
      selected: _state.bus,
      onSelected: (v) => setState(() => _state = _state.copyWith(bus: v)),
    );
  }

  // Deliberately not a FilterChip: this pins the bus fader in place, it
  // doesn't show/hide it, so it needs to read as a different kind of
  // control from the visibility chips (different shape, different accent
  // color that isn't one of the 16 console colors).
  Widget _pinChip() {
    final l = AppLocalizations.of(context)!;
    const accent = Color(0xFFE3A73B);
    final enabled = _state.busFaderVisible;
    final active = _state.busFaderPinned && enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () => setState(
                  () => _state = _state.copyWith(
                    busFaderPinned: !_state.busFaderPinned,
                  ),
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? accent : const Color(0xFF3A3E47),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 15,
                  color: active ? accent : const Color(0xFF9AA3AE),
                ),
                const SizedBox(width: 6),
                Text(
                  l.busAlwaysVisible,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active ? accent : const Color(0xFF9AA3AE),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _busFaderChipLabel() => busFaderTitle(
    bus: _state.bus,
    busLinked: widget.busLinked,
    busNames: widget.busNames,
    l: AppLocalizations.of(context)!,
  );

  String _busLabel(int busNum) {
    final name = widget.busNames[busNum];
    if (name == null || name.isEmpty) {
      return AppLocalizations.of(context)!.busTitleMono(busNum);
    }
    return '$busNum · $name';
  }

  String _pairLabel(int odd, int even) {
    final nameOdd = widget.busNames[odd];
    final nameEven = widget.busNames[even];
    final hasOdd = nameOdd != null && nameOdd.isNotEmpty;
    final hasEven = nameEven != null && nameEven.isNotEmpty;
    if (!hasOdd && !hasEven) {
      return busPairTitle(odd, even, AppLocalizations.of(context)!);
    }
    final base = '$odd/$even';
    if (hasOdd && hasEven) {
      return nameOdd == nameEven
          ? '$base · $nameOdd'
          : '$base · $nameOdd/$nameEven';
    }
    return '$base · ${hasOdd ? nameOdd : nameEven}';
  }

  Future<void> _openGroupConfig(int index) async {
    final result = await Navigator.push<List<GroupFaderConfig>>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupConfigScreen(
          configs: _state.groups,
          groupIndex: index,
          channelNames: widget.channelNames,
          fxReturnNames: widget.fxReturnNames,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _state = _state.copyWith(groups: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.settings),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _pop,
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: MediaQuery.viewPaddingOf(context).left,
            right: MediaQuery.viewPaddingOf(context).right,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Text(
                  l.auxBus,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListTile(
                  onTap: _openBusPicker,
                  tileColor: const Color(0xFF16181D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFF2C3038)),
                  ),
                  leading: _busColorDot(),
                  title: Text(_currentBusLabel()),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
              const Divider(height: 32),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF16181D),
                  border: Border.all(color: const Color(0xFF2C3038)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          const RotatedBox(
                            quarterTurns: 1,
                            child: Icon(
                              Icons.tune,
                              size: 17,
                              color: Color(0xFF3A6EA8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.faderVisibilityTitle,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        l.colorHintCaption,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    _cardSubLabel(l.visibleChannels),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...List.generate(16, (i) {
                            final ch = i + 1;
                            final label =
                                widget.channelNames[ch] ??
                                'Ch ${ch.toString().padLeft(2, '0')}';
                            return _colorableChip(
                              label: label,
                              selected: _state.channels.contains(ch),
                              onSelected: (on) => setState(() {
                                final channels = Set<int>.of(_state.channels);
                                on ? channels.add(ch) : channels.remove(ch);
                                _state = _state.copyWith(channels: channels);
                              }),
                              colorIndex: _state.channelColors[ch],
                              consoleColorIndex:
                                  widget.consoleChannelColors[ch],
                              onLongPress: () => _openColorSheet(ch - 1),
                            );
                          }),
                          _colorableChip(
                            label: 'LINE',
                            selected: _state.lineInVisible,
                            onSelected: (on) => setState(
                              () => _state = _state.copyWith(
                                lineInVisible: on,
                              ),
                            ),
                            colorIndex: _state.lineInColor,
                            consoleColorIndex: widget.consoleLineInColor,
                            onLongPress: () => _openColorSheet(16),
                          ),
                        ],
                      ),
                    ),
                    _hairline(),
                    _cardSubLabel(l.fxReturns),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(4, (i) {
                          final rtn = i + 1;
                          return _colorableChip(
                            label: widget.fxReturnNames[rtn] ?? 'FX $rtn',
                            selected: _state.fxReturns.contains(rtn),
                            onSelected: (on) => setState(() {
                              final fxReturns = Set<int>.of(_state.fxReturns);
                              on
                                  ? fxReturns.add(rtn)
                                  : fxReturns.remove(rtn);
                              _state = _state.copyWith(fxReturns: fxReturns);
                            }),
                            colorIndex: _state.fxReturnColors[rtn],
                            consoleColorIndex:
                                widget.consoleFxReturnColors[rtn],
                            onLongPress: () => _openColorSheet(16 + rtn),
                          );
                        }),
                      ),
                    ),
                    _hairline(),
                    _cardSubLabel(l.groupFaders),
                    ...List.generate(_state.groups.length, (i) {
                      final cfg = _state.groups[i];
                      final subtitle = cfg.memberCount == 0
                          ? l.noChannelsAssigned
                          : l.channelCount(cfg.memberCount);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ConstrainedBox(
                          // Caps the row so it doesn't stretch edge-to-edge
                          // on landscape/tablet, which otherwise strands the
                          // gear icon far from the chip and legend.
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.5,
                                  ),
                                  child: _colorableChip(
                                    label: cfg.name,
                                    selected: cfg.visible,
                                    onSelected: (on) => setState(() {
                                      final groups = List<GroupFaderConfig>.of(
                                        _state.groups,
                                      );
                                      groups[i] = cfg.copyWith(visible: on);
                                      _state = _state.copyWith(
                                        groups: groups,
                                      );
                                    }),
                                    colorIndex: cfg.colorIndex,
                                    consoleColorIndex: null,
                                    onLongPress: () =>
                                        _openColorSheet(_groupColorPosition(i)),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      subtitle,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings),
                                  tooltip: l.configureChannels,
                                  onPressed: () => _openGroupConfig(i),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    _hairline(),
                    _cardSubLabel(l.busFaderVisibility),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Flexible(
                            child: _colorableChip(
                              label: 'MASTER',
                              selected: _state.busFaderVisible,
                              onSelected: (on) => setState(
                                () => _state = _state.copyWith(
                                  busFaderVisible: on,
                                ),
                              ),
                              colorIndex: _state.busColors[_busColorKey],
                              consoleColorIndex:
                                  widget.consoleBusColors[_busColorKey],
                              onLongPress: () => _openColorSheet(
                                _colorableFaders().length - 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _pinChip(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(l.layoutsTitle),
                subtitle: Text(l.layoutsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLayouts,
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.about),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(
                      Icons.power_settings_new,
                      color: Colors.red,
                    ),
                    label: Text(
                      l.disconnect,
                      style: const TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}
