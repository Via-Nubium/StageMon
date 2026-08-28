import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:stagemon/models/channel_color.dart';

// A color's protocol value is now its position in kChannelColors — the
// entries carry no index of their own, so the two can no longer disagree.
// What's left to guard is what is still written by hand: isInverted, and
// the per-slot labels.

void main() {
  test('the palette covers exactly the 16 slots the console defines', () {
    expect(kChannelColors.length, 16);
    expect(ConsoleColor.off, 0);
    expect(ConsoleColor.wh, 7);
    expect(ConsoleColor.offi, 8);
    expect(ConsoleColor.whi, 15);
    expect(ConsoleColor.gni, 10); // the group faders' default
  });

  test('the 8 inverted slots are exactly the second half', () {
    for (var i = 0; i < kChannelColors.length; i++) {
      expect(kChannelColors[i].isInverted, i >= 8, reason: 'slot $i');
    }
  });

  group('localizedColorLabel', () {
    late AppLocalizations es;
    late AppLocalizations en;

    setUpAll(() async {
      es = await AppLocalizations.delegate.load(const Locale('es'));
      en = await AppLocalizations.delegate.load(const Locale('en'));
    });

    // Guards the unreachable `_ => ''` fallback: a color added to
    // kChannelColors without a matching case would silently render a blank
    // caption in the picker. This turns that into a failing test.
    test('every slot has a non-empty label in both languages', () {
      for (var i = 0; i < kChannelColors.length; i++) {
        expect(
          localizedColorLabel(es, i),
          isNotEmpty,
          reason: 'missing Spanish label for slot $i',
        );
        expect(
          localizedColorLabel(en, i),
          isNotEmpty,
          reason: 'missing English label for slot $i',
        );
      }
    });

    test('labels are distinct, so no two slots read the same', () {
      final labels = {
        for (var i = 0; i < kChannelColors.length; i++)
          localizedColorLabel(es, i),
      };
      expect(labels.length, kChannelColors.length);
    });

    test('an out-of-range slot falls back to an empty label, not a throw', () {
      expect(localizedColorLabel(es, 99), '');
    });
  });
}
