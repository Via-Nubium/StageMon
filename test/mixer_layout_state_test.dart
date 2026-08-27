import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stagemon/models/group_fader_config.dart';
import 'package:stagemon/models/mixer_layout_state.dart';

// MixerLayoutState is the single codec shared by SharedPreferences and the
// SavedLayout file format (see the refactor spec). These tests exist to
// freeze that shape: a golden toJson() comparison, a full round trip, and
// per-field corruption tolerance so a bad `bus_colors_v1`-equivalent chunk
// can never take the other ten fields down with it.

MixerLayoutState buildState() => MixerLayoutState(
  bus: 3,
  channels: {1, 2, 9},
  channelColors: {1: 4, 2: null},
  fxReturns: {2, 4},
  fxReturnColors: {2: 8},
  lineInVisible: true,
  lineInColor: 5,
  busFaderVisible: false,
  busFaderPinned: true,
  busColors: {3: 11},
  groups: [
    const GroupFaderConfig(
      name: 'Batería',
      visible: true,
      channels: {5, 6},
      fxReturns: {1},
      lineIn: true,
      colorIndex: 7,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toJson matches the v2 golden shape exactly', () {
    final json = buildState().toJson();
    expect(json, {
      'bus': 3,
      'channels': {
        'visible': [1, 2, 9],
        'colors': {'1': 4, '2': null},
      },
      'fxReturns': {
        'visible': [2, 4],
        'colors': {'2': 8},
      },
      'lineIn': {'visible': true, 'color': 5},
      'busFader': {
        'visible': false,
        'pinned': true,
        'colors': {'3': 11},
      },
      'groups': [
        {
          'name': 'Batería',
          'visible': true,
          'channels': [5, 6],
          'fxReturns': [1],
          'lineIn': true,
          'color': 7,
        },
      ],
    });
  });

  test('round trips through toJson/fromJson field by field', () {
    final original = buildState();
    final back = MixerLayoutState.fromJson(
      original.toJson(),
      fallbackBus: 1,
    );

    expect(back.bus, original.bus);
    expect(back.channels, original.channels);
    expect(back.channelColors, original.channelColors);
    expect(back.fxReturns, original.fxReturns);
    expect(back.fxReturnColors, original.fxReturnColors);
    expect(back.lineInVisible, original.lineInVisible);
    expect(back.lineInColor, original.lineInColor);
    expect(back.busFaderVisible, original.busFaderVisible);
    expect(back.busFaderPinned, original.busFaderPinned);
    expect(back.busColors, original.busColors);
    expect(back.groups.length, 1);
    expect(back.groups.first.channels, {5, 6});
    expect(back.groups.first.fxReturns, {1});
    expect(back.groups.first.lineIn, isTrue);
    expect(back.groups.first.colorIndex, 7);
  });

  test('a missing bus falls back to fallbackBus, not to 1', () {
    final json = buildState().toJson()..remove('bus');
    final back = MixerLayoutState.fromJson(json, fallbackBus: 4);
    expect(back.bus, 4);
  });

  test('an explicit null bus also falls back to fallbackBus', () {
    final json = buildState().toJson();
    json['bus'] = null;
    final back = MixerLayoutState.fromJson(json, fallbackBus: 4);
    expect(back.bus, 4);
  });

  test('an empty store loads as defaults()', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await MixerLayoutState.loadFromPrefs();
    final defaults = MixerLayoutState.defaults();

    expect(state.bus, defaults.bus);
    expect(state.channels, isEmpty);
    expect(state.fxReturns, isEmpty);
    expect(state.lineInVisible, isFalse);
    expect(state.busFaderVisible, isTrue);
    expect(state.busFaderPinned, isFalse);
    expect(state.groups.length, 4);
    for (final g in state.groups) {
      expect(g.visible, isFalse);
      expect(g.memberCount, 0);
    }
  });

  test('saveToPrefs then loadFromPrefs round trips through real prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final original = buildState();
    await original.saveToPrefs();

    final back = await MixerLayoutState.loadFromPrefs();
    expect(back.bus, original.bus);
    expect(back.channels, original.channels);
    expect(back.channelColors, original.channelColors);
    expect(back.busColors, original.busColors);
    expect(back.groups.first.colorIndex, 7);
  });

  test(
    'an explicit null color override survives and stays distinct from an absent key',
    () {
      final back = MixerLayoutState.fromJson(
        buildState().toJson(),
        fallbackBus: 1,
      );
      // Channel 2 was saved as an explicit null (falls back to console
      // color); channel 9 is visible but was never given a color at all.
      expect(back.channelColors.containsKey(2), isTrue);
      expect(back.channelColors[2], isNull);
      expect(back.channelColors.containsKey(9), isFalse);
    },
  );

  group('per-field corruption tolerance', () {
    // Corrupting any single field must not disturb the other ten — mirrors
    // the per-key try/catch the old SharedPreferences-based loader had.
    final good = buildState().toJson();

    Map<String, dynamic> corrupt(String key, dynamic badValue) {
      final json = Map<String, dynamic>.of(good);
      json[key] = badValue;
      return json;
    }

    // `except` lists the Dart fields that share a JSON sub-object with the
    // one being corrupted — corrupting `channels` as a whole necessarily
    // resets both `channels` and `channelColors`, since both read from the
    // same (now-garbage) json['channels']. The finer-grained case below
    // (corrupting only channels.colors) is what proves those two are read
    // independently rather than sharing a single try/catch.
    void expectRestSurvive(MixerLayoutState back, {required Set<String> except}) {
      final original = buildState();
      if (!except.contains('bus')) expect(back.bus, original.bus);
      if (!except.contains('channels')) {
        expect(back.channels, original.channels);
      }
      if (!except.contains('channelColors')) {
        expect(back.channelColors, original.channelColors);
      }
      if (!except.contains('fxReturns')) {
        expect(back.fxReturns, original.fxReturns);
      }
      if (!except.contains('fxReturnColors')) {
        expect(back.fxReturnColors, original.fxReturnColors);
      }
      if (!except.contains('lineInVisible')) {
        expect(back.lineInVisible, original.lineInVisible);
      }
      if (!except.contains('lineInColor')) {
        expect(back.lineInColor, original.lineInColor);
      }
      if (!except.contains('busFaderVisible')) {
        expect(back.busFaderVisible, original.busFaderVisible);
      }
      if (!except.contains('busFaderPinned')) {
        expect(back.busFaderPinned, original.busFaderPinned);
      }
      if (!except.contains('busColors')) {
        expect(back.busColors, original.busColors);
      }
      if (!except.contains('groups')) expect(back.groups.length, 1);
    }

    test('bus corrupted', () {
      final back = MixerLayoutState.fromJson(
        corrupt('bus', 'not a number'),
        fallbackBus: 9,
      );
      expect(back.bus, 9);
      expectRestSurvive(back, except: {'bus'});
    });

    test('channels sub-object corrupted resets channels and their colors, nothing else', () {
      final back = MixerLayoutState.fromJson(
        corrupt('channels', 'garbage'),
        fallbackBus: 1,
      );
      expect(back.channels, isEmpty);
      expect(back.channelColors, isEmpty);
      expectRestSurvive(back, except: {'channels', 'channelColors'});
    });

    test('fxReturns sub-object corrupted resets fx returns and their colors, nothing else', () {
      final back = MixerLayoutState.fromJson(
        corrupt('fxReturns', 42),
        fallbackBus: 1,
      );
      expect(back.fxReturns, isEmpty);
      expect(back.fxReturnColors, isEmpty);
      expectRestSurvive(back, except: {'fxReturns', 'fxReturnColors'});
    });

    test('lineIn sub-object corrupted resets visibility and color, nothing else', () {
      final back = MixerLayoutState.fromJson(
        corrupt('lineIn', [1, 2, 3]),
        fallbackBus: 1,
      );
      expect(back.lineInVisible, isFalse);
      expect(back.lineInColor, isNull);
      expectRestSurvive(back, except: {'lineInVisible', 'lineInColor'});
    });

    test('busFader sub-object corrupted resets visible/pinned/colors, nothing else', () {
      final back = MixerLayoutState.fromJson(
        corrupt('busFader', 'nope'),
        fallbackBus: 1,
      );
      expect(back.busFaderVisible, isTrue);
      expect(back.busFaderPinned, isFalse);
      expect(back.busColors, isEmpty);
      expectRestSurvive(
        back,
        except: {'busFaderVisible', 'busFaderPinned', 'busColors'},
      );
    });

    test('groups corrupted falls back to defaultConfigs(), nothing else', () {
      final back = MixerLayoutState.fromJson(
        corrupt('groups', {'not': 'a list'}),
        fallbackBus: 1,
      );
      expect(back.groups.length, 4); // falls back to defaultConfigs()
      expectRestSurvive(back, except: {'groups'});
    });

    test('one bad entry inside groups falls the whole field back to defaults', () {
      final json = Map<String, dynamic>.of(good);
      json['groups'] = [
        'not a map',
      ];
      final back = MixerLayoutState.fromJson(json, fallbackBus: 1);
      expect(back.groups.length, 4);
      expectRestSurvive(back, except: {'groups'});
    });

    test('channels.colors corrupted independently of channels.visible', () {
      final json = Map<String, dynamic>.of(good);
      json['channels'] = {'visible': good['channels']['visible'], 'colors': 'bad'};
      final back = MixerLayoutState.fromJson(json, fallbackBus: 1);
      expect(back.channels, buildState().channels);
      expect(back.channelColors, isEmpty);
    });
  });
}
