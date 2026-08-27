import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/widgets/custom_fader.dart';

// The XR18 fader taper is piecewise linear with knees at -60, -30 and -10 dB,
// spanning -90 dB (-inf) to +10 dB. faderToDbValue and dbToFader must stay
// exact inverses of each other: they're on opposite ends of every OSC round
// trip (console value in, user drag out), so a knee that drifts on one side
// only shows up as faders that creep after touching them.

void main() {
  group('faderToDbValue', () {
    test('maps the endpoints', () {
      expect(faderToDbValue(0.0), -90.0);
      expect(faderToDbValue(1.0), closeTo(10.0, 1e-9));
    });

    test('hits the documented knees', () {
      expect(faderToDbValue(0.0625), closeTo(-60.0, 1e-9));
      expect(faderToDbValue(0.25), closeTo(-30.0, 1e-9));
      expect(faderToDbValue(0.5), closeTo(-10.0, 1e-9));
      expect(faderToDbValue(0.75), closeTo(0.0, 1e-9));
    });

    test('is continuous across every knee', () {
      for (final knee in [0.0625, 0.25, 0.5]) {
        expect(
          faderToDbValue(knee - 1e-9),
          closeTo(faderToDbValue(knee), 1e-6),
          reason: 'discontinuity at f=$knee',
        );
      }
    });

    test('collapses the bottom of the travel to -inf', () {
      expect(faderToDbValue(0.0004), -90.0);
      // Just above the threshold the taper takes over again.
      expect(faderToDbValue(0.0005), closeTo(-89.76, 1e-9));
    });

    test('is monotonically increasing', () {
      var prev = faderToDbValue(0.0);
      for (var i = 1; i <= 1000; i++) {
        final db = faderToDbValue(i / 1000);
        expect(db, greaterThanOrEqualTo(prev), reason: 'dropped at f=${i / 1000}');
        prev = db;
      }
    });
  });

  group('dbToFader', () {
    test('maps the endpoints', () {
      expect(dbToFader(-90.0), 0.0);
      expect(dbToFader(10.0), closeTo(1.0, 1e-9));
    });

    test('hits the documented knees', () {
      expect(dbToFader(-60.0), closeTo(0.0625, 1e-9));
      expect(dbToFader(-30.0), closeTo(0.25, 1e-9));
      expect(dbToFader(-10.0), closeTo(0.5, 1e-9));
      expect(dbToFader(0.0), closeTo(0.75, 1e-9));
    });

    test('clamps beyond the console range', () {
      expect(dbToFader(20.0), 1.0);
      expect(dbToFader(-120.0), 0.0);
    });
  });

  test('dbToFader inverts faderToDbValue across the whole travel', () {
    // Below 0.0005 the -inf collapse is deliberately lossy, so start above it.
    for (var i = 1; i <= 1000; i++) {
      final f = 0.0005 + (1.0 - 0.0005) * i / 1000;
      expect(
        dbToFader(faderToDbValue(f)),
        closeTo(f, 1e-9),
        reason: 'round trip failed at f=$f',
      );
    }
  });

  group('faderToDb (label)', () {
    test('shows -inf at the bottom', () {
      expect(faderToDb(0.0), '-∞');
    });

    test('signs unity and above with a +', () {
      expect(faderToDb(0.75), '+0.0 dB');
      expect(faderToDb(1.0), '+10.0 dB');
    });

    test('leaves attenuation with its own minus sign', () {
      expect(faderToDb(0.5), '-10.0 dB');
      expect(faderToDb(0.25), '-30.0 dB');
    });
  });
}
