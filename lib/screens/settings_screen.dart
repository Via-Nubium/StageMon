import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/group_fader_config.dart';
import 'about_screen.dart';
import 'group_config_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Set<int> selectedChannels;
  final Map<int, String> channelNames;
  final Map<int, String> busNames;
  final bool showBusFader;
  final int bus;
  final List<GroupFaderConfig> groupConfigs;
  final Set<int> selectedFxReturns;
  final bool showLineIn;
  final bool busAlwaysVisible;

  const SettingsScreen({
    super.key,
    required this.selectedChannels,
    required this.channelNames,
    required this.busNames,
    required this.showBusFader,
    required this.bus,
    required this.groupConfigs,
    required this.selectedFxReturns,
    required this.showLineIn,
    required this.busAlwaysVisible,
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
  }

  void _pop() => Navigator.pop(context, (
    _selected,
    _showBusFader,
    _bus,
    _groupConfigs,
    _selectedFxReturns,
    _showLineIn,
    _busAlwaysVisible,
  ));

  void _disconnect() {
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                  children: List.generate(6, (i) {
                    final busNum = i + 1;
                    final name = widget.busNames[busNum];
                    final label = (name == null || name.isEmpty)
                        ? '$busNum'
                        : '$busNum · $name';
                    return ChoiceChip(
                      label: Text(label),
                      selected: _bus == busNum,
                      onSelected: (on) {
                        if (on) setState(() => _bus = busNum);
                      },
                    );
                  }),
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
                      return FilterChip(
                        label: Text(label),
                        selected: _selected.contains(ch),
                        onSelected: (on) => setState(() {
                          on ? _selected.add(ch) : _selected.remove(ch);
                        }),
                      );
                    }),
                    FilterChip(
                      label: const Text('LINE'),
                      selected: _showLineIn,
                      onSelected: (on) => setState(() => _showLineIn = on),
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
                    return FilterChip(
                      label: Text('FX $rtn'),
                      selected: _selectedFxReturns.contains(rtn),
                      onSelected: (on) => setState(() {
                        on
                            ? _selectedFxReturns.add(rtn)
                            : _selectedFxReturns.remove(rtn);
                      }),
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
