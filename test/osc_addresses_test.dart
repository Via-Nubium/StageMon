import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/utils/osc_addresses.dart';

// The mix addresses used to be spelled out four times — MixerController,
// GroupFader, GroupDetailScreen and the embedded simulator — and only the
// controller's copy was covered. These pin the strings themselves;
// mixer_controller_bus_test.dart pins which bus they get built for.

void main() {
  group('a source in a bus mix', () {
    test('pads channel and bus to two digits, but not FX returns', () {
      expect(channelLevelAddress(3, 1), '/ch/03/mix/01/level');
      expect(channelLevelAddress(16, 10), '/ch/16/mix/10/level');
      expect(channelPanAddress(3, 1), '/ch/03/mix/01/pan');
      expect(fxReturnLevelAddress(2, 1), '/rtn/2/mix/01/level');
      expect(fxReturnPanAddress(2, 1), '/rtn/2/mix/01/pan');
    });

    test('the LINE input is the aux return', () {
      expect(lineInLevelAddress(1), '/rtn/aux/mix/01/level');
      expect(lineInPanAddress(6), '/rtn/aux/mix/06/pan');
    });
  });

  group('the bus itself', () {
    test('is not padded in its own path', () {
      expect(busFaderAddress(1), '/bus/1/mix/fader');
      expect(busMuteAddress(6), '/bus/6/mix/on');
      expect(busNameAddress(3), '/bus/3/config/name');
      expect(busColorAddress(3), '/bus/3/config/color');
    });

    test('a stereo pair is keyed by its odd bus', () {
      expect(busLinkAddress(1), '/config/buslink/1-2');
      expect(busLinkAddress(3), '/config/buslink/3-4');
      expect(busLinkAddress(5), '/config/buslink/5-6');
    });
  });

  group('scribble strips', () {
    test('name and color per source', () {
      expect(channelNameAddress(1), '/ch/01/config/name');
      expect(channelColorAddress(16), '/ch/16/config/color');
      expect(fxReturnNameAddress(2), '/rtn/2/config/name');
      expect(fxReturnColorAddress(2), '/rtn/2/config/color');
      expect(kLineInColorAddress, '/rtn/aux/config/color');
    });
  });

  group('the session', () {
    test('discovery, subscription and meters', () {
      expect(kInfoAddress, '/xinfo');
      expect(kRemoteAddress, '/xremote');
      expect(kMetersAddress, '/meters');
      expect(kMeterBank1Address, '/meters/1');
    });
  });
}
