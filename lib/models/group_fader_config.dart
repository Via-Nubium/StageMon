import 'dart:convert';

class GroupFaderConfig {
  final String name;
  final bool visible;
  final Set<int> channels;   // 1-16
  final Set<int> fxReturns;  // 1-4
  final bool lineIn;

  const GroupFaderConfig({
    required this.name,
    this.visible = false,
    required this.channels,
    this.fxReturns = const {},
    this.lineIn = false,
  });

  int get memberCount => channels.length + fxReturns.length + (lineIn ? 1 : 0);

  GroupFaderConfig copyWith({
    String? name,
    bool? visible,
    Set<int>? channels,
    Set<int>? fxReturns,
    bool? lineIn,
  }) => GroupFaderConfig(
        name: name ?? this.name,
        visible: visible ?? this.visible,
        channels: channels ?? this.channels,
        fxReturns: fxReturns ?? this.fxReturns,
        lineIn: lineIn ?? this.lineIn,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'visible': visible,
        'channels': channels.toList(),
        'fxReturns': fxReturns.toList(),
        'lineIn': lineIn,
      };

  factory GroupFaderConfig.fromJson(Map<String, dynamic> json) => GroupFaderConfig(
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? false,
        channels: Set<int>.from((json['channels'] as List).map((e) => e as int)),
        fxReturns: json['fxReturns'] != null
            ? Set<int>.from((json['fxReturns'] as List).map((e) => e as int))
            : {},
        lineIn: json['lineIn'] as bool? ?? false,
      );

  static List<GroupFaderConfig> defaultConfigs() => [
        GroupFaderConfig(name: 'Grupo 1', channels: {}, fxReturns: {}),
        GroupFaderConfig(name: 'Grupo 2', channels: {}, fxReturns: {}),
        GroupFaderConfig(name: 'Grupo 3', channels: {}, fxReturns: {}),
        GroupFaderConfig(name: 'Grupo 4', channels: {}, fxReturns: {}),
      ];

  static List<GroupFaderConfig> fromJsonList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list.map((e) => GroupFaderConfig.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String toJsonList(List<GroupFaderConfig> configs) =>
      jsonEncode(configs.map((c) => c.toJson()).toList());
}
