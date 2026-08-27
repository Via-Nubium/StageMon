import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:stagemon/utils/bus_title.dart';

// A linked pair is one physical fader on the console, so it has to read as
// one title and key its color under one bus number. Getting either wrong
// makes MASTER show a stale name or lose its color when the user links
// buses on the console.

void main() {
  late AppLocalizations l;

  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('es'));
  });

  group('busFaderTitle, unlinked', () {
    const unlinked = {1: false, 3: false, 5: false};

    test('falls back to the bus number when unnamed', () {
      expect(busFaderTitle(bus: 3, busLinked: unlinked, busNames: {}, l: l),
          'Bus 3');
    });

    test('prefers the console name', () {
      expect(
        busFaderTitle(
            bus: 3, busLinked: unlinked, busNames: {3: 'Guitarra'}, l: l),
        'Guitarra',
      );
    });

    test('treats an empty console name as no name', () {
      expect(
        busFaderTitle(bus: 3, busLinked: unlinked, busNames: {3: ''}, l: l),
        'Bus 3',
      );
    });
  });

  group('busFaderTitle, linked pair', () {
    const linked = {1: true, 3: false, 5: false};

    test('joins the two numbers when neither is named', () {
      expect(busFaderTitle(bus: 1, busLinked: linked, busNames: {}, l: l),
          'Bus 1/2');
    });

    test('reads the same whether entered from the odd or the even bus', () {
      expect(
        busFaderTitle(bus: 2, busLinked: linked, busNames: {}, l: l),
        busFaderTitle(bus: 1, busLinked: linked, busNames: {}, l: l),
      );
    });

    test('collapses to one title when both halves share a name', () {
      expect(
        busFaderTitle(
            bus: 1, busLinked: linked, busNames: {1: 'IEM', 2: 'IEM'}, l: l),
        'IEM',
      );
    });

    test('joins both halves when the names differ', () {
      expect(
        busFaderTitle(
            bus: 1, busLinked: linked, busNames: {1: 'IEM L', 2: 'IEM R'}, l: l),
        'IEM L/IEM R',
      );
    });

    test('fills the unnamed half with its bus number', () {
      expect(
        busFaderTitle(bus: 1, busLinked: linked, busNames: {1: 'IEM'}, l: l),
        'IEM/Bus 2',
      );
      expect(
        busFaderTitle(bus: 1, busLinked: linked, busNames: {2: 'IEM'}, l: l),
        'Bus 1/IEM',
      );
    });
  });

  group('busColorKey', () {
    test('is the bus itself when unlinked', () {
      expect(busColorKey(bus: 4, busLinked: {3: false}), 4);
      expect(busColorKey(bus: 3, busLinked: {3: false}), 3);
    });

    test('collapses a linked pair onto its odd base', () {
      expect(busColorKey(bus: 4, busLinked: {3: true}), 3);
      expect(busColorKey(bus: 3, busLinked: {3: true}), 3);
    });

    test('treats an unknown pair as unlinked', () {
      expect(busColorKey(bus: 6, busLinked: const {}), 6);
    });
  });
}
