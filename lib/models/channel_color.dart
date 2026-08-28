import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';

/// The 16 color slots the console exposes via `/ch/*/config/color` and
/// `/bus/*/config/color`: 0-7 the base colors, 8-15 the same 8 "inverted"
/// (dark background, colored text). These names are the console's own.
///
/// This is the single place each color's protocol value is written down —
/// [kChannelColors] references these rather than repeating the numbers, so
/// code that picks a color can say `ConsoleColor.gni` instead of `10`.
abstract final class ConsoleColor {
  static const off = 0;
  static const rd = 1;
  static const gn = 2;
  static const ye = 3;
  static const bl = 4;
  static const mg = 5;
  static const cy = 6;
  static const wh = 7;
  static const offi = 8;
  static const rdi = 9;
  static const gni = 10;
  static const yei = 11;
  static const bli = 12;
  static const mgi = 13;
  static const cyi = 14;
  static const whi = 15;
}

/// How one of [ConsoleColor]'s 16 slots looks on screen. Deliberately does
/// *not* carry its own index: a slot's protocol value is its position in
/// [kChannelColors], so the two can't drift apart.
class ChannelColorOption {
  final Color background;
  final Color foreground;
  final bool isInverted;

  const ChannelColorOption({
    required this.background,
    required this.foreground,
    required this.isInverted,
  });
}

/// The palette, indexed by protocol value — entry N is [ConsoleColor]'s
/// slot N. The order is the console's, not a display order; the picker
/// grid iterates indices, so it can present them in any order it likes
/// without touching this list.
const List<ChannelColorOption> kChannelColors = [
  // ConsoleColor.off
  ChannelColorOption(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  // ConsoleColor.rd
  ChannelColorOption(
    background: Color(0xFFC0392B),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  // ConsoleColor.gn
  ChannelColorOption(
    background: Color(0xFF29C428),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  // ConsoleColor.ye
  ChannelColorOption(
    background: Color(0xFFE8DE1E),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  // ConsoleColor.bl
  ChannelColorOption(
    background: Color(0xFF2F6FE4),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  // ConsoleColor.mg
  ChannelColorOption(
    background: Color(0xFFE765DF),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  // ConsoleColor.cy
  ChannelColorOption(
    background: Color(0xFF1DD3D0),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  // ConsoleColor.wh
  ChannelColorOption(
    background: Color(0xFFEDEDED),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  // ConsoleColor.offi
  ChannelColorOption(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    isInverted: true,
  ),
  // ConsoleColor.rdi
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFFF5245),
    isInverted: true,
  ),
  // ConsoleColor.gni
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF29C428),
    isInverted: true,
  ),
  // ConsoleColor.yei
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFE8DE1E),
    isInverted: true,
  ),
  // ConsoleColor.bli
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF4D8FFF),
    isInverted: true,
  ),
  // ConsoleColor.mgi
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFE765DF),
    isInverted: true,
  ),
  // ConsoleColor.cyi
  ChannelColorOption(
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF1DD3D0),
    isInverted: true,
  ),
  // ConsoleColor.whi
  ChannelColorOption(
    background: Color(0xFF2C2C2E),
    foreground: Color(0xFFFFFFFF),
    isInverted: true,
  ),
];

ChannelColorOption channelColorByIndex(int index) => kChannelColors[index];

/// The name of colour slot [index] in the app's current language.
///
/// The fallback is unreachable for the 16 real slots, and returns an empty
/// label rather than throwing — a blank swatch caption is a far milder
/// failure than crashing the color sheet. A color added to
/// [kChannelColors] without a case here is caught by
/// test/channel_color_test.dart instead.
String localizedColorLabel(AppLocalizations l, int index) => switch (index) {
  ConsoleColor.off => l.colorOff,
  ConsoleColor.rd => l.colorRd,
  ConsoleColor.gn => l.colorGn,
  ConsoleColor.ye => l.colorYe,
  ConsoleColor.bl => l.colorBl,
  ConsoleColor.mg => l.colorMg,
  ConsoleColor.cy => l.colorCy,
  ConsoleColor.wh => l.colorWh,
  ConsoleColor.offi => l.colorOffi,
  ConsoleColor.rdi => l.colorRdi,
  ConsoleColor.gni => l.colorGni,
  ConsoleColor.yei => l.colorYei,
  ConsoleColor.bli => l.colorBli,
  ConsoleColor.mgi => l.colorMgi,
  ConsoleColor.cyi => l.colorCyi,
  ConsoleColor.whi => l.colorWhi,
  _ => '',
};

/// How a color renders as a filled shape — glossy for the 8 base colors
/// (matches the console's solid scribble-strip look), a colored outline on
/// near-black for the 8 inverted ones (a glossy near-black fill would just
/// look flat). Shared by the picker swatches and the fader nameplate so
/// both read as the same color.
BoxDecoration channelColorFill(
  ChannelColorOption color, {
  double radius = 8,
  double borderWidth = 2,
}) {
  if (color.isInverted) {
    return BoxDecoration(
      color: color.background,
      border: Border.all(color: color.foreground, width: borderWidth),
      borderRadius: BorderRadius.circular(radius),
    );
  }
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(color.background, Colors.white, 0.2)!,
        color.background,
        Color.lerp(color.background, Colors.black, 0.12)!,
      ],
    ),
  );
}

/// Placeholder shown for "follow the console" until OSC sync reads the real
/// value — see ChannelColorSheet.
const ChannelColorOption kConsoleColorPlaceholder = ChannelColorOption(
  background: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  isInverted: false,
);
