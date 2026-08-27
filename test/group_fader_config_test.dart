import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/models/group_fader_config.dart';

// Group configs are persisted both in SharedPreferences and inside every
// exported layout file, so fromJson has to keep reading JSON written by
// older builds that didn't have these fields yet.

void main() {
  const full = GroupFaderConfig(
    name: 'Batería',
    visible: true,
    channels: {1, 2, 5},
    fxReturns: {2, 4},
    lineIn: true,
    colorIndex: 3,
  );

  test('survives a JSON round trip intact', () {
    final back = GroupFaderConfig.fromJson(full.toJson());
    expect(back.name, full.name);
    expect(back.visible, full.visible);
    expect(back.channels, full.channels);
    expect(back.fxReturns, full.fxReturns);
    expect(back.lineIn, full.lineIn);
    expect(back.colorIndex, full.colorIndex);
  });

  test('survives a round trip through the list encoding', () {
    final configs = [full, ...GroupFaderConfig.defaultConfigs()];
    final back = GroupFaderConfig.fromJsonList(
      GroupFaderConfig.toJsonList(configs),
    );
    expect(back.length, configs.length);
    expect(back.first.channels, full.channels);
    expect(back.first.colorIndex, full.colorIndex);
    expect(back.last.name, configs.last.name);
  });

  test('reads legacy JSON that predates fxReturns/lineIn/colorIndex', () {
    final back = GroupFaderConfig.fromJson({
      'name': 'Grupo 1',
      'channels': [3, 4],
    });
    expect(back.name, 'Grupo 1');
    expect(back.channels, {3, 4});
    expect(back.visible, isFalse);
    expect(back.fxReturns, isEmpty);
    expect(back.lineIn, isFalse);
    expect(back.colorIndex, GroupFaderConfig.defaultColorIndex);
  });

  test('memberCount counts channels, fx returns and LINE together', () {
    expect(full.memberCount, 6); // 3 channels + 2 returns + LINE
    expect(const GroupFaderConfig(name: 'x', channels: {}).memberCount, 0);
  });

  test('copyWith replaces only what it is given', () {
    final renamed = full.copyWith(name: 'Voces');
    expect(renamed.name, 'Voces');
    expect(renamed.channels, full.channels);
    expect(renamed.colorIndex, full.colorIndex);
    expect(renamed.lineIn, full.lineIn);
  });

  test('the four default groups start empty, hidden and green', () {
    final defaults = GroupFaderConfig.defaultConfigs();
    expect(defaults.length, 4);
    for (final c in defaults) {
      expect(c.visible, isFalse);
      expect(c.memberCount, 0);
      expect(c.colorIndex, GroupFaderConfig.defaultColorIndex);
    }
  });
}
