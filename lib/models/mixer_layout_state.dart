import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fader_width.dart';
import 'group_fader_config.dart';

// Sentinel default for MixerLayoutState.copyWith's lineInColor parameter —
// see the doc comment there.
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// Everything that makes up "what the mixer screen is showing": which
/// faders are visible, how wide they are drawn, their local color overrides,
/// and the selected bus.
/// This is the one place these 12 fields are declared — it used to be
/// copied across the mixer screen, SettingsScreen, LayoutsScreen, a
/// SharedPreferences codec and SavedLayout independently, which let those
/// copies drift out of sync with each other.
///
/// The same [toJson]/[fromJson] shape is used both for SharedPreferences
/// (the live layout, under [prefsKey]) and for the `layout` object inside
/// an exported [SavedLayout] file — there is exactly one codec.
class MixerLayoutState {
  static const String prefsKey = 'mixer_layout_v2';

  final int bus;
  final Set<int> channels;
  final Map<int, int?> channelColors;
  final Set<int> fxReturns;
  final Map<int, int?> fxReturnColors;
  final bool lineInVisible;
  final int? lineInColor;
  final bool busFaderVisible;
  final bool busFaderPinned;
  final Map<int, int?> busColors; // keyed by bus number, see busColorKey()
  final List<GroupFaderConfig> groups;

  /// Width of the mixer's resizable columns — the value a pinch produces.
  final double faderWidth;

  MixerLayoutState({
    required this.bus,
    required Set<int> channels,
    required Map<int, int?> channelColors,
    required Set<int> fxReturns,
    required Map<int, int?> fxReturnColors,
    required this.lineInVisible,
    required this.lineInColor,
    required this.busFaderVisible,
    required this.busFaderPinned,
    required Map<int, int?> busColors,
    required List<GroupFaderConfig> groups,
    required this.faderWidth,
  }) : channels = Set.of(channels),
       channelColors = Map.of(channelColors),
       fxReturns = Set.of(fxReturns),
       fxReturnColors = Map.of(fxReturnColors),
       busColors = Map.of(busColors),
       groups = List.of(groups);

  factory MixerLayoutState.defaults() => MixerLayoutState(
    bus: 1,
    // All 16 channels start visible — matches the field initializer a
    // fresh _MixerScreenState used before this class existed.
    channels: {for (var ch = 1; ch <= 16; ch++) ch},
    channelColors: {},
    fxReturns: {},
    fxReturnColors: {},
    lineInVisible: false,
    lineInColor: null,
    busFaderVisible: true,
    busFaderPinned: false,
    busColors: {},
    groups: GroupFaderConfig.defaultConfigs(),
    faderWidth: kDefaultFaderWidth,
  );

  // lineInColor needs to distinguish "leave it alone" from "clear the
  // override back to the console color" (a real, exercised action — the
  // "console color" swatch in channel_color_sheet.dart calls
  // onChanged(null)). A plain `int? lineInColor` parameter can't tell those
  // apart, since null would mean both. _unset is the sentinel default, so
  // an omitted argument leaves lineInColor untouched while an explicit
  // `copyWith(lineInColor: null)` clears it.
  MixerLayoutState copyWith({
    int? bus,
    Set<int>? channels,
    Map<int, int?>? channelColors,
    Set<int>? fxReturns,
    Map<int, int?>? fxReturnColors,
    bool? lineInVisible,
    Object? lineInColor = _unset,
    bool? busFaderVisible,
    bool? busFaderPinned,
    Map<int, int?>? busColors,
    List<GroupFaderConfig>? groups,
    double? faderWidth,
  }) => MixerLayoutState(
    bus: bus ?? this.bus,
    channels: channels ?? this.channels,
    channelColors: channelColors ?? this.channelColors,
    fxReturns: fxReturns ?? this.fxReturns,
    fxReturnColors: fxReturnColors ?? this.fxReturnColors,
    lineInVisible: lineInVisible ?? this.lineInVisible,
    lineInColor: identical(lineInColor, _unset)
        ? this.lineInColor
        : lineInColor as int?,
    busFaderVisible: busFaderVisible ?? this.busFaderVisible,
    busFaderPinned: busFaderPinned ?? this.busFaderPinned,
    busColors: busColors ?? this.busColors,
    groups: groups ?? this.groups,
    faderWidth: faderWidth ?? this.faderWidth,
  );

  Map<String, dynamic> toJson() => {
    'bus': bus,
    'channels': {
      'visible': (channels.toList()..sort()),
      'colors': channelColors.map((k, v) => MapEntry(k.toString(), v)),
    },
    'fxReturns': {
      'visible': (fxReturns.toList()..sort()),
      'colors': fxReturnColors.map((k, v) => MapEntry(k.toString(), v)),
    },
    'lineIn': {'visible': lineInVisible, 'color': lineInColor},
    'busFader': {
      'visible': busFaderVisible,
      'pinned': busFaderPinned,
      'colors': busColors.map((k, v) => MapEntry(k.toString(), v)),
    },
    'groups': groups.map(_groupToJson).toList(),
    'faderWidth': faderWidth,
  };

  /// [fallbackBus] is used when the JSON carries no bus at all — a
  /// SavedLayout file legitimately encodes `bus: null` to mean "load this
  /// layout but leave whichever bus is currently selected alone"; that
  /// null is resolved by the caller (against the current bus) before it
  /// ever reaches here, so this only covers a missing/corrupt field.
  ///
  /// Every field is read independently: a broken sub-object for one
  /// field (e.g. `channels` is a string instead of a map) falls back to
  /// its own default without disturbing the other eleven.
  factory MixerLayoutState.fromJson(
    Map<String, dynamic> json, {
    required int fallbackBus,
  }) {
    final d = MixerLayoutState.defaults();

    int bus = fallbackBus;
    try {
      final b = json['bus'];
      if (b != null) bus = b as int;
    } catch (_) {}

    Set<int> channels = d.channels;
    try {
      final visible = json['channels']['visible'] as List<dynamic>;
      channels = visible.map((e) => e as int).toSet();
    } catch (_) {}

    Map<int, int?> channelColors = d.channelColors;
    try {
      channelColors = _colorMapFromJson(json['channels']['colors']);
    } catch (_) {}

    Set<int> fxReturns = d.fxReturns;
    try {
      final visible = json['fxReturns']['visible'] as List<dynamic>;
      fxReturns = visible.map((e) => e as int).toSet();
    } catch (_) {}

    Map<int, int?> fxReturnColors = d.fxReturnColors;
    try {
      fxReturnColors = _colorMapFromJson(json['fxReturns']['colors']);
    } catch (_) {}

    bool lineInVisible = d.lineInVisible;
    try {
      lineInVisible = json['lineIn']['visible'] as bool;
    } catch (_) {}

    int? lineInColor = d.lineInColor;
    try {
      lineInColor = json['lineIn']['color'] as int?;
    } catch (_) {}

    bool busFaderVisible = d.busFaderVisible;
    try {
      busFaderVisible = json['busFader']['visible'] as bool;
    } catch (_) {}

    bool busFaderPinned = d.busFaderPinned;
    try {
      busFaderPinned = json['busFader']['pinned'] as bool;
    } catch (_) {}

    Map<int, int?> busColors = d.busColors;
    try {
      busColors = _colorMapFromJson(json['busFader']['colors']);
    } catch (_) {}

    List<GroupFaderConfig> groups = d.groups;
    try {
      final list = json['groups'] as List<dynamic>;
      groups = list
          .map((e) => _groupFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    // A layout written before widths were stored carries none, and loading
    // one puts the faders back at the default size — deliberately, rather
    // than keeping whatever width happened to be in use: only a handful of
    // layouts predate this, and re-saving them costs nothing.
    double faderWidth = d.faderWidth;
    try {
      faderWidth = clampFaderWidth(json['faderWidth'] as num);
    } catch (_) {}

    return MixerLayoutState(
      bus: bus,
      channels: channels,
      channelColors: channelColors,
      fxReturns: fxReturns,
      fxReturnColors: fxReturnColors,
      lineInVisible: lineInVisible,
      lineInColor: lineInColor,
      busFaderVisible: busFaderVisible,
      busFaderPinned: busFaderPinned,
      busColors: busColors,
      groups: groups,
      faderWidth: faderWidth,
    );
  }

  static Future<MixerLayoutState> loadFromPrefs({int fallbackBus = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return MixerLayoutState.defaults();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MixerLayoutState.fromJson(json, fallbackBus: fallbackBus);
    } catch (_) {
      return MixerLayoutState.defaults();
    }
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(toJson()));
  }
}

// Clamped on the way in, mirroring what MixerController already does with
// colors arriving over OSC. A stored file is the one color source the app
// doesn't produce itself — a hand-edited or damaged layout carrying, say,
// 99 would otherwise reach channelColorByIndex and throw a RangeError mid
// build. Since the active layout lives in prefs, that would crash the
// mixer screen on every launch, with no way out but clearing app data.
Map<int, int?> _colorMapFromJson(dynamic raw) {
  final map = raw as Map<String, dynamic>;
  return map.map(
    (k, v) => MapEntry(int.parse(k), (v as int?)?.clamp(0, 15)),
  );
}

// GroupFaderConfig's own JSON codec still uses the field name `colorIndex`
// (out of scope to rename here — see the refactor spec); the v2 layout
// format calls it `color`, so the rename happens at this boundary only.
Map<String, dynamic> _groupToJson(GroupFaderConfig g) {
  final json = g.toJson();
  final colorIndex = json.remove('colorIndex');
  json['color'] = colorIndex;
  return json;
}

GroupFaderConfig _groupFromJson(Map<String, dynamic> json) {
  final copy = Map<String, dynamic>.of(json);
  if (copy.containsKey('color')) {
    copy['colorIndex'] = copy.remove('color');
  }
  return GroupFaderConfig.fromJson(copy);
}
