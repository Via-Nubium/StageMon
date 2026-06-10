import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../services/osc_service.dart';
import '../models/group_fader_config.dart';
import '../widgets/custom_fader.dart';
import '../widgets/pan_knob.dart';
import 'group_config_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final List<GroupFaderConfig> configs;
  final int groupIndex;
  final int busNum;
  final bool busPaired;
  final Map<int, String> channelNames;
  final OscService service;
  final List<ValueNotifier<double>> meterLevels;        // 16 channel meters
  final List<ValueNotifier<double>> fxReturnMeterL;     // 4 FX return left meters
  final List<ValueNotifier<double>> fxReturnMeterR;     // 4 FX return right meters
  final ValueNotifier<double> lineInMeterL;
  final ValueNotifier<double> lineInMeterR;
  final void Function(List<GroupFaderConfig>) onConfigsChanged;

  const GroupDetailScreen({
    super.key,
    required this.configs,
    required this.groupIndex,
    required this.busNum,
    required this.busPaired,
    required this.channelNames,
    required this.service,
    required this.meterLevels,
    required this.fxReturnMeterL,
    required this.fxReturnMeterR,
    required this.lineInMeterL,
    required this.lineInMeterR,
    required this.onConfigsChanged,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late List<GroupFaderConfig> _configs;

  GroupFaderConfig get _config => _configs[widget.groupIndex];

  @override
  void initState() {
    super.initState();
    _configs = widget.configs;
  }

  // Encoded keys: channels 1-16, FX returns 101-104, Line In 200
  List<int> get _allMembers {
    final channels = _config.channels.toList()..sort();
    final fxReturns = _config.fxReturns.map((r) => 100 + r).toList()..sort();
    return [
      ...channels,
      if (_config.lineIn) 200,
      ...fxReturns,
    ];
  }

  String _memberAddress(int key) {
    final b = widget.busNum.toString().padLeft(2, '0');
    if (key <= 16) return '/ch/${key.toString().padLeft(2, '0')}/mix/$b/level';
    if (key < 200) return '/rtn/${key - 100}/mix/$b/level';
    return '/rtn/aux/mix/$b/level';
  }

  String _memberPanAddress(int key) {
    final b = widget.busNum.toString().padLeft(2, '0');
    if (key <= 16) return '/ch/${key.toString().padLeft(2, '0')}/mix/$b/pan';
    if (key < 200) return '/rtn/${key - 100}/mix/$b/pan';
    return '/rtn/aux/mix/$b/pan';
  }

  String _memberLabel(int key) {
    if (key <= 16) return widget.channelNames[key] ?? 'Ch ${key.toString().padLeft(2, '0')}';
    if (key < 200) return 'FX ${key - 100}';
    return 'LINE';
  }

  Color? _memberColor(int key) {
    if (key <= 16) return null;
    if (key < 200) return Colors.teal;
    return Colors.deepOrange;
  }

  ValueNotifier<double> _memberMeterL(int key) {
    if (key <= 16) return widget.meterLevels[key - 1];
    if (key < 200) return widget.fxReturnMeterL[key - 101];
    return widget.lineInMeterL;
  }

  ValueNotifier<double>? _memberMeterR(int key) {
    if (key <= 16) return null;
    if (key < 200) return widget.fxReturnMeterR[key - 101];
    return widget.lineInMeterR;
  }

  void _openConfig() async {
    final result = await Navigator.push<List<GroupFaderConfig>>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupConfigScreen(
          configs: _configs,
          groupIndex: widget.groupIndex,
          channelNames: widget.channelNames,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _configs = result);
      widget.onConfigsChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final members = _allMembers;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.groupTitle(_config.name)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l.editGroupChannels,
            onPressed: _openConfig,
          ),
        ],
      ),
      body: members.isEmpty
          ? Center(child: Text(l.noChannelsInGroup))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(
                      left: MediaQuery.viewPaddingOf(context).left,
                      right: MediaQuery.viewPaddingOf(context).right,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: members.map((key) {
                        final color = _memberColor(key);
                        return SizedBox(
                          width: 90,
                          child: color != null
                              ? Container(
                                  color: color.withValues(alpha: 0.04),
                                  child: _buildMemberColumn(key, color),
                                )
                              : _buildMemberColumn(key, null),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
              ],
            ),
    );
  }

  Widget _buildMemberColumn(int key, Color? accentColor) {
    return Column(
      children: [
        if (widget.busPaired)
          PanKnob(
            key: ValueKey('pan_$key'),
            oscAddress: _memberPanAddress(key),
            service: widget.service,
          )
        else
          const SizedBox(height: kPanKnobHeight),
        Expanded(
          child: CustomFader(
            key: ValueKey(key),
            label: _memberLabel(key),
            oscAddress: _memberAddress(key),
            service: widget.service,
            accentColor: accentColor ?? const Color(0xFF2979FF),
            meterLevel: _memberMeterL(key),
            meterLevelRight: _memberMeterR(key),
          ),
        ),
      ],
    );
  }
}
