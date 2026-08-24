import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'group_fader_config.dart';

class SavedLayout {
  String name;
  final Set<int> selectedChannels;
  final bool showBusFader;
  // null means this layout doesn't carry a bus — loading it leaves whatever
  // bus is currently selected untouched, since a layout's channel/group
  // arrangement is commonly reused across different monitor mixes (buses).
  final int? bus;
  final List<GroupFaderConfig> groupConfigs;
  final Set<int> selectedFxReturns;
  final bool showLineIn;
  final bool busAlwaysVisible;
  final Map<int, int?> channelColors;
  final int? lineInColor;
  final Map<int, int?> fxReturnColors;
  final Map<int, int?> busColors;
  // Not read anywhere yet — recorded so that if console models with
  // conflicting addressing are ever supported, existing saved layouts
  // already carry enough information to tell them apart.
  final String consoleModel;

  SavedLayout({
    required this.name,
    required this.selectedChannels,
    required this.showBusFader,
    required this.bus,
    required this.groupConfigs,
    required this.selectedFxReturns,
    required this.showLineIn,
    required this.busAlwaysVisible,
    required this.channelColors,
    required this.lineInColor,
    required this.fxReturnColors,
    required this.busColors,
    required this.consoleModel,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'selectedChannels': selectedChannels.toList(),
    'showBusFader': showBusFader,
    'bus': bus,
    'groupConfigs': groupConfigs.map((c) => c.toJson()).toList(),
    'selectedFxReturns': selectedFxReturns.toList(),
    'showLineIn': showLineIn,
    'busAlwaysVisible': busAlwaysVisible,
    'channelColors': channelColors.map((k, v) => MapEntry(k.toString(), v)),
    'lineInColor': lineInColor,
    'fxReturnColors': fxReturnColors.map((k, v) => MapEntry(k.toString(), v)),
    'busColors': busColors.map((k, v) => MapEntry(k.toString(), v)),
    'consoleModel': consoleModel,
  };

  factory SavedLayout.fromJson(Map<String, dynamic> json) => SavedLayout(
    name: json['name'] as String,
    selectedChannels: Set<int>.from(
      (json['selectedChannels'] as List).map((e) => e as int),
    ),
    showBusFader: json['showBusFader'] as bool? ?? true,
    bus: json['bus'] as int?,
    groupConfigs: (json['groupConfigs'] as List)
        .map((e) => GroupFaderConfig.fromJson(e as Map<String, dynamic>))
        .toList(),
    selectedFxReturns: json['selectedFxReturns'] != null
        ? Set<int>.from(
            (json['selectedFxReturns'] as List).map((e) => e as int),
          )
        : {},
    showLineIn: json['showLineIn'] as bool? ?? false,
    busAlwaysVisible: json['busAlwaysVisible'] as bool? ?? false,
    channelColors: (json['channelColors'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(int.parse(k), v as int?),
    ),
    lineInColor: json['lineInColor'] as int?,
    fxReturnColors: (json['fxReturnColors'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(int.parse(k), v as int?),
    ),
    busColors: (json['busColors'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(int.parse(k), v as int?),
    ),
    consoleModel: json['consoleModel'] as String? ?? 'Unknown',
  );
}

class LayoutManager {
  static const _key = 'saved_layouts_v1';
  final List<SavedLayout> layouts = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      layouts.clear();
      layouts.addAll(
        list.map((e) => SavedLayout.fromJson(e as Map<String, dynamic>)),
      );
    } catch (_) {}
  }

  Future<void> add(SavedLayout layout) async {
    layouts.add(layout);
    await _persist();
  }

  Future<void> remove(int index) async {
    layouts.removeAt(index);
    await _persist();
  }

  Future<void> rename(int index, String newName) async {
    layouts[index].name = newName;
    await _persist();
  }

  Future<void> overwrite(int index, SavedLayout layout) async {
    layout.name = layouts[index].name;
    layouts[index] = layout;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(layouts.map((l) => l.toJson()).toList()),
    );
  }
}
