import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stagemon/controllers/mixer_controller.dart';
import 'package:stagemon/services/osc_service.dart';

// Every OSC address the mixer touches is derived from `effectiveBus`, not
// from the bus the user picked: linking 1-2 on the console makes bus 2 an
// alias of bus 1, and sending to /mix/02 there moves nothing. These tests
// pin the aliasing and the exact address shapes (zero padding included,
// which differs between /ch and /bus).
//
// The service is never init()ed, so send/request are no-ops on a null
// socket — nothing leaves the machine.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OscService service;
  late MixerController ctrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = OscService(ip: '127.0.0.1');
    ctrl = MixerController(service: service);
  });

  // The controller owns the service's lifetime: MixerController.dispose()
  // disposes it too, so disposing it here as well would double-dispose.
  tearDown(() => ctrl.dispose());

  group('address shapes on the default bus', () {
    test('channel sends are zero padded on both channel and bus', () {
      expect(ctrl.busAddress(3), '/ch/03/mix/01/level');
      expect(ctrl.busAddress(16), '/ch/16/mix/01/level');
      expect(ctrl.panAddress(3), '/ch/03/mix/01/pan');
    });

    test('fx returns pad the bus but not the return number', () {
      expect(ctrl.fxReturnAddress(2), '/rtn/2/mix/01/level');
      expect(ctrl.fxReturnPanAddress(2), '/rtn/2/mix/01/pan');
    });

    test('LINE in is the aux return', () {
      expect(ctrl.lineInAddress(), '/rtn/aux/mix/01/level');
      expect(ctrl.lineInPanAddress(), '/rtn/aux/mix/01/pan');
    });

    test('the bus fader itself is not padded', () {
      expect(ctrl.busFaderAddress(), '/bus/1/mix/fader');
      expect(ctrl.busMuteAddress(), '/bus/1/mix/on');
    });
  });

  group('changeBus', () {
    test('retargets every address', () {
      ctrl.changeBus(2);
      expect(ctrl.bus, 2);
      expect(ctrl.busAddress(3), '/ch/03/mix/02/level');
      expect(ctrl.fxReturnAddress(1), '/rtn/1/mix/02/level');
      expect(ctrl.lineInAddress(), '/rtn/aux/mix/02/level');
      expect(ctrl.busFaderAddress(), '/bus/2/mix/fader');
    });

    test('ignores a change to the bus already selected', () {
      ctrl.changeBus(1);
      expect(ctrl.bus, 1);
      expect(ctrl.busAddress(3), '/ch/03/mix/01/level');
    });

    test('reaches bus 6, the last one on the XR18', () {
      ctrl.changeBus(6);
      expect(ctrl.busAddress(1), '/ch/01/mix/06/level');
      expect(ctrl.busFaderAddress(), '/bus/6/mix/fader');
    });
  });

  group('linked pairs', () {
    test('an odd bus is unaffected by its own link', () {
      ctrl.busLinked[1] = true;
      expect(ctrl.busPaired, isTrue);
      expect(ctrl.effectiveBus, 1);
      expect(ctrl.busAddress(3), '/ch/03/mix/01/level');
    });

    test('an even bus is aliased onto its odd base', () {
      ctrl.busLinked[1] = true;
      ctrl.changeBus(2);
      expect(ctrl.bus, 2); // what the user picked
      expect(ctrl.effectiveBus, 1); // where the OSC actually goes
      expect(ctrl.busAddress(3), '/ch/03/mix/01/level');
      expect(ctrl.lineInAddress(), '/rtn/aux/mix/01/level');
      expect(ctrl.busFaderAddress(), '/bus/1/mix/fader');
    });

    test('aliasing follows the pair the bus belongs to, not pair 1-2', () {
      ctrl.busLinked[5] = true;
      ctrl.changeBus(6);
      expect(ctrl.busPaired, isTrue);
      expect(ctrl.effectiveBus, 5);
      expect(ctrl.busAddress(3), '/ch/03/mix/05/level');
    });

    test('an even bus whose pair is unlinked keeps its own number', () {
      ctrl.busLinked[3] = false;
      ctrl.changeBus(4);
      expect(ctrl.busPaired, isFalse);
      expect(ctrl.effectiveBus, 4);
      expect(ctrl.busAddress(3), '/ch/03/mix/04/level');
    });

    test('unlinking gives the even bus its own address back', () {
      ctrl.busLinked[1] = true;
      ctrl.changeBus(2);
      expect(ctrl.effectiveBus, 1);
      ctrl.busLinked[1] = false;
      expect(ctrl.effectiveBus, 2);
      expect(ctrl.busAddress(3), '/ch/03/mix/02/level');
    });
  });

  group('labels', () {
    test('channels fall back to a padded number', () {
      expect(ctrl.channelLabel(3), 'Ch 03');
      expect(ctrl.channelLabel(16), 'Ch 16');
    });

    test('a console channel name wins over the fallback', () {
      ctrl.channelNames[3] = 'Guitarra';
      expect(ctrl.channelLabel(3), 'Guitarra');
    });

    test('buses show their number alone until named', () {
      expect(ctrl.busLabel(2), '2');
      ctrl.busNames[2] = 'IEM';
      expect(ctrl.busLabel(2), '2 · IEM');
    });

    test('an empty console bus name falls back to the number', () {
      ctrl.busNames[2] = '';
      expect(ctrl.busLabel(2), '2');
    });
  });

  // changeBus itself no longer persists the bus — that moved to
  // MixerLayoutState, which the screen saves as part of the unified layout
  // blob (see test/mixer_layout_state_test.dart's saveToPrefs/loadFromPrefs
  // round trip, and the MixerLayoutState refactor spec's "trampa 1").
}
