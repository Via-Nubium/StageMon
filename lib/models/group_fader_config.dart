import 'fader_width.dart';

class GroupFaderConfig {
  final String name;
  final bool visible;
  final Set<int> channels;   // 1-16
  final Set<int> fxReturns;  // 1-4
  final bool lineIn;
  // A group is a local combo of channels, not a real console fader, so
  // there's no console color to sync from — just a manually picked one.
  // Defaults to Green Inv, the color the fixed group-fader green used to be.
  final int colorIndex;
  /// Width of the faders inside this group's detail screen. A group of three
  /// is usually wanted spread wide even when the mixer is packed with sixteen.
  ///
  /// Width of the faders inside this group's detail screen. A group of three
  /// is usually wanted spread wide even when the mixer is packed with sixteen.
  final double faderWidth;

  static const int defaultColorIndex = 10; // GNi — Verde Inv

  const GroupFaderConfig({
    required this.name,
    this.visible = false,
    required this.channels,
    this.fxReturns = const {},
    this.lineIn = false,
    this.colorIndex = defaultColorIndex,
    this.faderWidth = kDefaultFaderWidth,
  });

  int get memberCount => channels.length + fxReturns.length + (lineIn ? 1 : 0);

  GroupFaderConfig copyWith({
    String? name,
    bool? visible,
    Set<int>? channels,
    Set<int>? fxReturns,
    bool? lineIn,
    int? colorIndex,
    double? faderWidth,
  }) => GroupFaderConfig(
        name: name ?? this.name,
        visible: visible ?? this.visible,
        channels: channels ?? this.channels,
        fxReturns: fxReturns ?? this.fxReturns,
        lineIn: lineIn ?? this.lineIn,
        colorIndex: colorIndex ?? this.colorIndex,
        faderWidth: faderWidth ?? this.faderWidth,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'visible': visible,
        'channels': channels.toList(),
        'fxReturns': fxReturns.toList(),
        'lineIn': lineIn,
        'colorIndex': colorIndex,
        'faderWidth': faderWidth,
      };

  factory GroupFaderConfig.fromJson(Map<String, dynamic> json) => GroupFaderConfig(
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? false,
        channels: Set<int>.from((json['channels'] as List).map((e) => e as int)),
        fxReturns: json['fxReturns'] != null
            ? Set<int>.from((json['fxReturns'] as List).map((e) => e as int))
            : {},
        lineIn: json['lineIn'] as bool? ?? false,
        // Clamped like every other stored color — see _colorMapFromJson in
        // mixer_layout_state.dart.
        colorIndex:
            (json['colorIndex'] as int?)?.clamp(0, 15) ?? defaultColorIndex,
        // Clamped for the same reason as the color above: this arrives from a
        // file anyone can edit.
        faderWidth: json['faderWidth'] is num
            ? clampFaderWidth(json['faderWidth'] as num)
            : kDefaultFaderWidth,
      );

  /// The four groups a layout starts with.
  ///
  /// [names] are the localized defaults ("Group 1"...) the caller resolved
  /// from AppLocalizations — a group's name is stored, not resolved at paint
  /// time, so it can only be localized where there's a context to read. The
  /// English fallback covers the paths that have none: the placeholder layout
  /// a screen holds before its stored one loads, and a corrupt `groups` field.
  static List<GroupFaderConfig> defaultConfigs({List<String>? names}) => [
        for (var i = 0; i < 4; i++)
          GroupFaderConfig(
            name: (names != null && i < names.length)
                ? names[i]
                : 'Group ${i + 1}',
            channels: {},
            fxReturns: {},
          ),
      ];
}
