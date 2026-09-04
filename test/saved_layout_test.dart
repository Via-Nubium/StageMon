import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/models/group_fader_config.dart';
import 'package:stagemon/models/mixer_layout_state.dart';
import 'package:stagemon/models/saved_layout.dart';

// SavedLayout is the v2 envelope around MixerLayoutState, used both for
// exported .stagemonlayout files and the saved-layouts list in prefs. It
// owns exactly one thing MixerLayoutState doesn't: a bus that can be
// genuinely absent (null = "load this layout but leave the bus alone"),
// kept deliberately separate from layout.bus (which MixerLayoutState
// itself always gives a concrete value). There is no v1 compatibility —
// pre-refactor saved layouts and exported files simply don't parse
// meaningfully anymore, by agreement.

MixerLayoutState buildLayoutState() => MixerLayoutState(
  bus: 3,
  channels: {1, 2, 3, 9},
  channelColors: {1: 4, 2: null, 9: 12},
  fxReturns: {2, 4},
  fxReturnColors: {2: 8},
  lineInVisible: true,
  lineInColor: 5,
  busFaderVisible: false,
  busFaderPinned: true,
  busColors: {3: 11},
  faderWidth: 125.0,
  groups: [
    const GroupFaderConfig(
      name: 'Batería',
      visible: true,
      channels: {5, 6},
      fxReturns: {1},
      lineIn: true,
      colorIndex: 7,
      faderWidth: 70,
    ),
  ],
);

SavedLayout buildLayout() => SavedLayout(
  name: 'Monitor Guitarra',
  console: 'XR18',
  bus: 3,
  layout: buildLayoutState(),
);

void main() {
  test('toJson matches the v2 envelope shape', () {
    final json = buildLayout().toJson();
    expect(json['formatVersion'], 2);
    expect(json['name'], 'Monitor Guitarra');
    expect(json['console'], 'XR18');
    // bus lives inside `layout`, alongside the rest of MixerLayoutState's
    // own fields — see the golden shape in mixer_layout_state_test.dart.
    final layoutJson = json['layout'] as Map<String, dynamic>;
    expect(layoutJson['bus'], 3);
    expect(layoutJson['channels'], {
      'visible': [1, 2, 3, 9],
      'colors': {'1': 4, '2': null, '9': 12},
    });
  });

  test('survives a JSON round trip intact', () {
    final original = buildLayout();
    // Through a real encode/decode, the way an imported file arrives.
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(back.name, original.name);
    expect(back.console, original.console);
    expect(back.bus, original.bus);
    expect(back.layout.channels, original.layout.channels);
    expect(back.layout.channelColors, original.layout.channelColors);
    expect(back.layout.fxReturns, original.layout.fxReturns);
    expect(back.layout.fxReturnColors, original.layout.fxReturnColors);
    expect(back.layout.lineInVisible, original.layout.lineInVisible);
    expect(back.layout.lineInColor, original.layout.lineInColor);
    expect(back.layout.busFaderVisible, original.layout.busFaderVisible);
    expect(back.layout.busFaderPinned, original.layout.busFaderPinned);
    expect(back.layout.busColors, original.layout.busColors);

    expect(back.layout.groups.length, 1);
    expect(back.layout.groups.first.channels, {5, 6});
    expect(back.layout.groups.first.fxReturns, {1});
    expect(back.layout.groups.first.colorIndex, 7);
  });

  test('keeps an explicit "no color" entry distinct from an absent one', () {
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(buildLayout().toJson())) as Map<String, dynamic>,
    );
    // Channel 2 was saved as an explicit null (console color wins);
    // channel 3 is visible but was never given one at all.
    expect(back.layout.channelColors.containsKey(2), isTrue);
    expect(back.layout.channelColors[2], isNull);
    expect(back.layout.channelColors.containsKey(3), isFalse);
  });

  test('preserves a null bus, meaning "leave the current bus alone"', () {
    final layout = SavedLayout(
      name: 'Sin bus',
      console: 'XR18',
      bus: null,
      layout: MixerLayoutState.defaults(),
    );
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(layout.toJson())) as Map<String, dynamic>,
    );
    expect(back.bus, isNull);
  });

  test("a recorded bus overrides layout's own bus in the JSON", () {
    // layout.bus (3, from buildLayoutState) and the top-level bus (5)
    // deliberately differ here to pin that toJson's override actually
    // reaches the JSON, and fromJson reads the override back, not
    // whatever MixerLayoutState.toJson() would have written on its own.
    final layout = SavedLayout(
      name: 'Bus explícito',
      console: 'XR18',
      bus: 5,
      layout: buildLayoutState(),
    );
    final json = layout.toJson();
    expect((json['layout'] as Map<String, dynamic>)['bus'], 5);
    final back = SavedLayout.fromJson(json);
    expect(back.bus, 5);
  });

  // Import validation. fromJson is the only gate between an arbitrary file
  // the user picked (or that Android handed over via "Open with") and the
  // layout list — and LayoutsScreen offers to LOAD whatever gets through,
  // overwriting the user's real arrangement. Everything inside `layout`
  // has a default, so without these checks any JSON at all parses "fine".
  group('rejects anything that is not a StageMon layout', () {
    void expectRejected(Map<String, dynamic> json) {
      expect(
        () => SavedLayout.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    }

    test('an unrelated JSON file', () {
      // A package.json used to import as a layout named "my-node-project".
      expectRejected(
        jsonDecode('{"name":"my-node-project","version":"1.0.0"}')
            as Map<String, dynamic>,
      );
    });

    test('an empty object', () {
      expectRejected(<String, dynamic>{});
    });

    test('a v1-shaped layout, which has no formatVersion', () {
      expectRejected({
        'name': 'Viejo',
        'selectedChannels': [1, 2],
        'bus': 1,
        'groupConfigs': <dynamic>[],
      });
    });

    test('a future format version this build cannot read', () {
      final json = buildLayout().toJson();
      json['formatVersion'] = 3;
      expectRejected(json);
    });

    test('a missing layout object', () {
      expectRejected({'formatVersion': 2, 'name': 'Sin layout'});
    });

    test('a layout key that is not an object', () {
      expectRejected({
        'formatVersion': 2,
        'name': 'Layout roto',
        'layout': 'not an object',
      });
    });

    test('a missing name', () {
      expectRejected({
        'formatVersion': 2,
        'layout': buildLayoutState().toJson(),
      });
    });
  });

  test('a correctly identified layout still tolerates one damaged field', () {
    // Strictness is about the envelope only: once the file says it is a
    // layout, MixerLayoutState's per-field tolerance still applies rather
    // than rejecting the whole import.
    final json = buildLayout().toJson();
    (json['layout'] as Map<String, dynamic>)['channels'] = 'garbage';

    final back = SavedLayout.fromJson(json);
    expect(back.name, 'Monitor Guitarra');
    expect(back.layout.channels, MixerLayoutState.defaults().channels);
    // The undamaged fields came through untouched.
    expect(back.layout.fxReturns, {2, 4});
    expect(back.layout.busColors, {3: 11});
  });
}
