import 'package:stagemon/l10n/app_localizations.dart';

/// The bus fader's display title, shared by the mixer screen's fader label
/// and any other place that needs to name "the current bus fader" — so
/// they can't drift out of sync with each other. Linked pairs collapse to
/// one title: names win over the raw number, joined with "/" only when
/// they differ.
String busFaderTitle({
  required int bus,
  required Map<int, bool> busLinked,
  required Map<int, String> busNames,
  required AppLocalizations l,
}) {
  final odd = bus.isOdd ? bus : bus - 1;
  if (busLinked[odd] ?? false) {
    final even = odd + 1;
    final nameOdd = busNames[odd];
    final nameEven = busNames[even];
    final hasOdd = nameOdd != null && nameOdd.isNotEmpty;
    final hasEven = nameEven != null && nameEven.isNotEmpty;
    if (!hasOdd && !hasEven) return '${l.busTitleMono(odd)}/$even';
    final left = hasOdd ? nameOdd : l.busTitleMono(odd);
    final right = hasEven ? nameEven : l.busTitleMono(even);
    return left == right ? left : '$left/$right';
  }
  final name = busNames[bus];
  return (name == null || name.isEmpty) ? l.busTitleMono(bus) : name;
}

/// The bus number a color (or other per-bus override) should be keyed
/// under: the pair's base (odd) bus when linked, otherwise the bus itself.
/// Mirrors how the console treats a linked pair as one physical fader with
/// one scribble-strip color.
int busColorKey({required int bus, required Map<int, bool> busLinked}) {
  final odd = bus.isOdd ? bus : bus - 1;
  return (busLinked[odd] ?? false) ? odd : bus;
}
