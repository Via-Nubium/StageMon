import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/group_fader_config.dart';
import '../models/channel_color.dart';
import '../widgets/channel_color_sheet.dart';
import '../widgets/color_handle_badge.dart';
import 'about_screen.dart';
import 'group_config_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Set<int> selectedChannels;
  final Map<int, String> channelNames;
  final Map<int, String> busNames;
  final Map<int, bool> busLinked;
  final bool showBusFader;
  final int bus;
  final List<GroupFaderConfig> groupConfigs;
  final Set<int> selectedFxReturns;
  final bool showLineIn;
  final bool busAlwaysVisible;
  final Map<int, int?> channelColors;
  final int? lineInColor;
  final Map<int, int?> fxReturnColors;
  final Map<int, int> consoleChannelColors;
  final int? consoleLineInColor;
  final Map<int, int> consoleFxReturnColors;

  const SettingsScreen({
    super.key,
    required this.selectedChannels,
    required this.channelNames,
    required this.busNames,
    required this.busLinked,
    required this.showBusFader,
    required this.bus,
    required this.groupConfigs,
    required this.selectedFxReturns,
    required this.showLineIn,
    required this.busAlwaysVisible,
    required this.channelColors,
    required this.lineInColor,
    required this.fxReturnColors,
    required this.consoleChannelColors,
    required this.consoleLineInColor,
    required this.consoleFxReturnColors,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Set<int> _selected;
  late bool _showBusFader;
  late int _bus;
  late List<GroupFaderConfig> _groupConfigs;
  late Set<int> _selectedFxReturns;
  late bool _showLineIn;
  late bool _busAlwaysVisible;
  late Map<int, int?> _channelColors;
  late int? _lineInColor;
  late Map<int, int?> _fxReturnColors;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.selectedChannels);
    _showBusFader = widget.showBusFader;
    _bus = widget.bus;
    _groupConfigs = List.of(widget.groupConfigs);
    _selectedFxReturns = Set.of(widget.selectedFxReturns);
    _showLineIn = widget.showLineIn;
    _busAlwaysVisible = widget.busAlwaysVisible;
    _channelColors = Map.of(widget.channelColors);
    _lineInColor = widget.lineInColor;
    _fxReturnColors = Map.of(widget.fxReturnColors);
  }

  void _pop() => Navigator.pop(context, (
    _selected,
    _showBusFader,
    _bus,
    _groupConfigs,
    _selectedFxReturns,
    _showLineIn,
    _busAlwaysVisible,
    _channelColors,
    _lineInColor,
    _fxReturnColors,
  ));

  // Channels, then LINE, then FX returns — the order the </> arrows in the
  // color sheet step through, independent of which of them are visible.
  List<ColorableFader> _colorableFaders() => [
    for (var ch = 1; ch <= 16; ch++)
      ColorableFader(
        label: widget.channelNames[ch] ?? 'Ch ${ch.toString().padLeft(2, '0')}',
        colorIndex: _channelColors[ch],
        onChanged: (index) => setState(() => _channelColors[ch] = index),
        consoleColorIndex: widget.consoleChannelColors[ch],
      ),
    ColorableFader(
      label: 'LINE',
      colorIndex: _lineInColor,
      onChanged: (index) => setState(() => _lineInColor = index),
      consoleColorIndex: widget.consoleLineInColor,
    ),
    for (var rtn = 1; rtn <= 4; rtn++)
      ColorableFader(
        label: 'FX $rtn',
        colorIndex: _fxReturnColors[rtn],
        onChanged: (index) => setState(() => _fxReturnColors[rtn] = index),
        consoleColorIndex: widget.consoleFxReturnColors[rtn],
      ),
  ];

  void _openColorSheet(int position) {
    showChannelColorSheet(
      context: context,
      items: _colorableFaders(),
      initialPosition: position,
    );
  }

  Widget _colorableChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required int? colorIndex,
    required int? consoleColorIndex,
    required VoidCallback onLongPress,
  }) {
    final color = channelColorByIndex(colorIndex ?? consoleColorIndex ?? 0);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: FilterChip(
              label: Text(label),
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

  Widget _busChip(int busNum, {int? pairedWith}) {
    final label = pairedWith == null
        ? _busLabel(busNum)
        : _pairLabel(busNum, pairedWith);
    final selected = _bus == busNum || (pairedWith != null && _bus == pairedWith);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (on) {
        if (on) setState(() => _bus = busNum);
      },
    );
  }

  String _busLabel(int busNum) {
    final name = widget.busNames[busNum];
    return (name == null || name.isEmpty) ? '$busNum' : '$busNum · $name';
  }

  String _pairLabel(int odd, int even) {
    final nameOdd = widget.busNames[odd];
    final nameEven = widget.busNames[even];
    final hasOdd = nameOdd != null && nameOdd.isNotEmpty;
    final hasEven = nameEven != null && nameEven.isNotEmpty;
    final base = '$odd/$even';
    if (!hasOdd && !hasEven) return base;
    if (hasOdd && hasEven) {
      return nameOdd == nameEven ? '$base · $nameOdd' : '$base · $nameOdd/$nameEven';
    }
    return '$base · ${hasOdd ? nameOdd : nameEven}';
  }

  Future<void> _openGroupConfig(int index) async {
    final result = await Navigator.push<List<GroupFaderConfig>>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupConfigScreen(
          configs: _groupConfigs,
          groupIndex: index,
          channelNames: widget.channelNames,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _groupConfigs = result);
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final odd in [1, 3, 5])
                      if (widget.busLinked[odd] ?? false)
                        _busChip(odd, pairedWith: odd + 1)
                      else ...[_busChip(odd), _busChip(odd + 1)],
                  ],
                ),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l.visibleChannels,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
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
                        selected: _selected.contains(ch),
                        onSelected: (on) => setState(() {
                          on ? _selected.add(ch) : _selected.remove(ch);
                        }),
                        colorIndex: _channelColors[ch],
                        consoleColorIndex: widget.consoleChannelColors[ch],
                        onLongPress: () => _openColorSheet(ch - 1),
                      );
                    }),
                    _colorableChip(
                      label: 'LINE',
                      selected: _showLineIn,
                      onSelected: (on) => setState(() => _showLineIn = on),
                      colorIndex: _lineInColor,
                      consoleColorIndex: widget.consoleLineInColor,
                      onLongPress: () => _openColorSheet(16),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l.fxReturns,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(4, (i) {
                    final rtn = i + 1;
                    return _colorableChip(
                      label: 'FX $rtn',
                      selected: _selectedFxReturns.contains(rtn),
                      onSelected: (on) => setState(() {
                        on
                            ? _selectedFxReturns.add(rtn)
                            : _selectedFxReturns.remove(rtn);
                      }),
                      colorIndex: _fxReturnColors[rtn],
                      consoleColorIndex: widget.consoleFxReturnColors[rtn],
                      onLongPress: () => _openColorSheet(16 + rtn),
                    );
                  }),
                ),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  l.groupFaders,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ...List.generate(_groupConfigs.length, (i) {
                final cfg = _groupConfigs[i];
                final subtitle = cfg.memberCount == 0
                    ? l.noChannelsAssigned
                    : l.channelCount(cfg.memberCount);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cfg.name),
                            Text(
                              subtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: cfg.visible,
                        onChanged: (on) => setState(() {
                          _groupConfigs[i] = cfg.copyWith(visible: on);
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        tooltip: l.configureChannels,
                        onPressed: () => _openGroupConfig(i),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  l.busFaderVisibility,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SwitchListTile(
                  value: _showBusFader,
                  onChanged: (on) => setState(() => _showBusFader = on),
                  title: Text(
                    widget.busNames[_bus] == null || widget.busNames[_bus]!.isEmpty
                        ? l.busFaderLabel(_bus)
                        : '${l.busFaderLabel(_bus)} · ${widget.busNames[_bus]}',
                  ),
                  subtitle: Text(
                    l.busFaderVolume,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 8),
                child: SwitchListTile(
                  value: _busAlwaysVisible,
                  onChanged: _showBusFader
                      ? (on) => setState(() => _busAlwaysVisible = on)
                      : null,
                  dense: true,
                  title: Text(l.busAlwaysVisible),
                ),
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
