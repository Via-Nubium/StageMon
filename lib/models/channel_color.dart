import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';

/// One of the 16 fixed scribble-strip colors the XR18 understands via
/// `/ch/*/config/color` and `/bus/*/config/color` (values 0-15: 8 base
/// colors, then the same 8 "inverted" — dark background, colored text).
class ChannelColorOption {
  final int index;
  final String oscName;
  final Color background;
  final Color foreground;
  final bool isInverted;

  const ChannelColorOption({
    required this.index,
    required this.oscName,
    required this.background,
    required this.foreground,
    required this.isInverted,
  });
}

const List<ChannelColorOption> kChannelColors = [
  ChannelColorOption(
    index: 0,
    oscName: 'OFF',
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 1,
    oscName: 'RD',
    background: Color(0xFFC0392B),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 2,
    oscName: 'GN',
    background: Color(0xFF29C428),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 3,
    oscName: 'YE',
    background: Color(0xFFE8DE1E),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 4,
    oscName: 'BL',
    background: Color(0xFF2F6FE4),
    foreground: Color(0xFFFFFFFF),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 5,
    oscName: 'MG',
    background: Color(0xFFE765DF),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 6,
    oscName: 'CY',
    background: Color(0xFF1DD3D0),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 7,
    oscName: 'WH',
    background: Color(0xFFEDEDED),
    foreground: Color(0xFF000000),
    isInverted: false,
  ),
  ChannelColorOption(
    index: 8,
    oscName: 'OFFi',
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 9,
    oscName: 'RDi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFFF5245),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 10,
    oscName: 'GNi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF29C428),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 11,
    oscName: 'YEi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFE8DE1E),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 12,
    oscName: 'BLi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF4D8FFF),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 13,
    oscName: 'MGi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFFE765DF),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 14,
    oscName: 'CYi',
    background: Color(0xFF0D0D0D),
    foreground: Color(0xFF1DD3D0),
    isInverted: true,
  ),
  ChannelColorOption(
    index: 15,
    oscName: 'WHi',
    background: Color(0xFF2C2C2E),
    foreground: Color(0xFFFFFFFF),
    isInverted: true,
  ),
];

ChannelColorOption channelColorByIndex(int index) => kChannelColors[index];

/// The color's name in the app's current language.
String localizedColorLabel(AppLocalizations l, ChannelColorOption color) {
  switch (color.oscName) {
    case 'OFF':
      return l.colorOff;
    case 'RD':
      return l.colorRd;
    case 'GN':
      return l.colorGn;
    case 'YE':
      return l.colorYe;
    case 'BL':
      return l.colorBl;
    case 'MG':
      return l.colorMg;
    case 'CY':
      return l.colorCy;
    case 'WH':
      return l.colorWh;
    case 'OFFi':
      return l.colorOffi;
    case 'RDi':
      return l.colorRdi;
    case 'GNi':
      return l.colorGni;
    case 'YEi':
      return l.colorYei;
    case 'BLi':
      return l.colorBli;
    case 'MGi':
      return l.colorMgi;
    case 'CYi':
      return l.colorCyi;
    case 'WHi':
      return l.colorWhi;
    default:
      return color.oscName;
  }
}

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
  index: -1,
  oscName: 'CONSOLE',
  background: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  isInverted: false,
);
