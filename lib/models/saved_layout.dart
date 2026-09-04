import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mixer_layout_state.dart';

/// A named, exportable snapshot of the mixer's layout — everything
/// [MixerLayoutState] tracks, plus a name and which console it was saved
/// from. Format v2: no backward compatibility with the v1 shape (flat
/// fields, no formatVersion) — pre-refactor saved layouts and exported
/// .stagemonlayout files simply won't parse anymore, by agreement.
class SavedLayout {
  static const int formatVersion = 2;

  String name;
  // Not read anywhere yet — recorded so that if console models with
  // conflicting addressing are ever supported, existing saved layouts
  // already carry enough information to tell them apart.
  final String console;
  // null means this layout doesn't carry a bus — loading it leaves whatever
  // bus is currently selected untouched, since a layout's channel/group
  // arrangement is commonly reused across different monitor mixes (buses).
  // This is the one place bus-nullability exists in the whole app.
  final int? bus;

  // Private on purpose. The bus inside it is *not* resolved — when [bus] is
  // null this holds a throwaway value nobody chose — so the only way out is
  // [resolvedLayout], which can't be called without saying what to fall back
  // to. Reading a bus that was never picked is then not something a caller
  // can do by accident.
  final MixerLayoutState _layout;

  SavedLayout({
    required this.name,
    required this.console,
    required this.bus,
    required MixerLayoutState layout,
  }) : _layout = layout;

  /// This layout ready to apply: the bus it carries, or [currentBus] when it
  /// carries none.
  MixerLayoutState resolvedLayout(int currentBus) =>
      _layout.copyWith(bus: bus ?? currentBus);

  // What the layout holds, for the one-line summary in the layouts list —
  // so listing a layout doesn't mean reaching through it to the state.
  int get channelCount => _layout.channels.length;
  bool get hasLineIn => _layout.lineInVisible;
  int get fxReturnCount => _layout.fxReturns.length;
  int get visibleGroupCount => _layout.groups.where((g) => g.visible).length;

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'name': name,
    'console': console,
    'layout': {..._layout.toJson(), 'bus': bus},
  };

  /// Throws [FormatException] if [json] isn't a StageMon layout.
  ///
  /// Deliberately strict, and the one place in the app that is: this is the
  /// only gate between an arbitrary file the user picked (or that Android
  /// handed us via "Open with") and the saved-layout list. Every field
  /// inside `layout` has a default, so a tolerant parse here would accept
  /// *any* JSON at all — a package.json would import as a layout named
  /// "my-node-project" — and LayoutsScreen would then offer to load it,
  /// replacing the user's real arrangement with blanks.
  ///
  /// The per-field tolerance inside [MixerLayoutState.fromJson] still
  /// applies once we know this really is a layout: a file that identifies
  /// itself correctly but has one damaged field loads with that field
  /// defaulted, rather than being rejected wholesale.
  factory SavedLayout.fromJson(Map<String, dynamic> json) {
    final version = json['formatVersion'];
    if (version != formatVersion) {
      throw FormatException(
        'Not a StageMon layout: expected formatVersion $formatVersion, '
        'got ${version ?? 'none'}',
      );
    }
    final layoutJson = json['layout'];
    if (layoutJson is! Map<String, dynamic>) {
      throw const FormatException(
        'Not a StageMon layout: missing "layout" object',
      );
    }
    final name = json['name'];
    if (name is! String) {
      throw const FormatException('Not a StageMon layout: missing "name"');
    }
    final rawBus = layoutJson['bus'];
    return SavedLayout(
      name: name,
      console: json['console'] as String? ?? 'Unknown',
      bus: rawBus is int ? rawBus : null,
      // A placeholder, and an unreachable one: parsing a file can't know
      // which bus is selected, and resolvedLayout overwrites this before
      // anyone can see it.
      layout: MixerLayoutState.fromJson(layoutJson, fallbackBus: 1),
    );
  }
}

class LayoutManager {
  static const _key = 'saved_layouts_v2';
  final List<SavedLayout> layouts = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    // Parsed into a scratch list, entry by entry, before touching `layouts`:
    // SavedLayout.fromJson throws on anything that isn't a layout, and one
    // damaged entry shouldn't cost the user every other layout they saved.
    // (Building in place would also leave the list half-filled on a throw,
    // since clear() would already have run.)
    final parsed = <SavedLayout>[];
    for (final entry in list) {
      try {
        parsed.add(SavedLayout.fromJson(entry as Map<String, dynamic>));
      } catch (_) {}
    }
    layouts
      ..clear()
      ..addAll(parsed);
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
