import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/models/group_fader_config.dart';
import 'package:stagemon/models/saved_layout.dart';

// SavedLayout is the on-disk format of shared .json layouts: a user can
// import a file exported by an older build, or by someone else's phone.
// Every field added since v1.0.0 needs a defaulted read path.

SavedLayout buildLayout() => SavedLayout(
  name: 'Monitor Guitarra',
  selectedChannels: {1, 2, 3, 9},
  showBusFader: false,
  bus: 3,
  groupConfigs: [
    const GroupFaderConfig(
      name: 'Batería',
      visible: true,
      channels: {5, 6},
      fxReturns: {1},
      lineIn: true,
      colorIndex: 7,
    ),
  ],
  selectedFxReturns: {2, 4},
  showLineIn: true,
  busAlwaysVisible: true,
  channelColors: {1: 4, 2: null, 9: 12},
  lineInColor: 5,
  fxReturnColors: {2: 8},
  busColors: {3: 11},
  consoleModel: 'XR18',
);

void main() {
  test('survives a JSON round trip intact', () {
    final original = buildLayout();
    // Through a real encode/decode, the way an imported file arrives.
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(back.name, original.name);
    expect(back.selectedChannels, original.selectedChannels);
    expect(back.showBusFader, original.showBusFader);
    expect(back.bus, original.bus);
    expect(back.selectedFxReturns, original.selectedFxReturns);
    expect(back.showLineIn, original.showLineIn);
    expect(back.busAlwaysVisible, original.busAlwaysVisible);
    expect(back.channelColors, original.channelColors);
    expect(back.lineInColor, original.lineInColor);
    expect(back.fxReturnColors, original.fxReturnColors);
    expect(back.busColors, original.busColors);
    expect(back.consoleModel, original.consoleModel);

    expect(back.groupConfigs.length, 1);
    expect(back.groupConfigs.first.channels, {5, 6});
    expect(back.groupConfigs.first.fxReturns, {1});
    expect(back.groupConfigs.first.colorIndex, 7);
  });

  test('keeps an explicit "no color" entry distinct from an absent one', () {
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(buildLayout().toJson())) as Map<String, dynamic>,
    );
    // Channel 2 was saved as an explicit null (console color wins);
    // channel 3 was never given one at all.
    expect(back.channelColors.containsKey(2), isTrue);
    expect(back.channelColors[2], isNull);
    expect(back.channelColors.containsKey(3), isFalse);
  });

  test('preserves a null bus, meaning "leave the current bus alone"', () {
    final layout = SavedLayout(
      name: 'Sin bus',
      selectedChannels: {1},
      showBusFader: true,
      bus: null,
      groupConfigs: const [],
      selectedFxReturns: const {},
      showLineIn: false,
      busAlwaysVisible: false,
      channelColors: const {},
      lineInColor: null,
      fxReturnColors: const {},
      busColors: const {},
      consoleModel: 'XR18',
    );
    final back = SavedLayout.fromJson(
      jsonDecode(jsonEncode(layout.toJson())) as Map<String, dynamic>,
    );
    expect(back.bus, isNull);
    expect(back.lineInColor, isNull);
  });

  test('reads a legacy layout that only carries the v1.0.0 fields', () {
    final back = SavedLayout.fromJson({
      'name': 'Viejo',
      'selectedChannels': [1, 2],
      'bus': 1,
      'groupConfigs': [
        {'name': 'Grupo 1', 'channels': [3]},
      ],
    });

    expect(back.name, 'Viejo');
    expect(back.selectedChannels, {1, 2});
    expect(back.showBusFader, isTrue); // defaults on
    expect(back.selectedFxReturns, isEmpty);
    expect(back.showLineIn, isFalse);
    expect(back.busAlwaysVisible, isFalse);
    expect(back.channelColors, isEmpty);
    expect(back.lineInColor, isNull);
    expect(back.fxReturnColors, isEmpty);
    expect(back.busColors, isEmpty);
    expect(back.consoleModel, 'Unknown');
    expect(back.groupConfigs.single.channels, {3});
  });
}
