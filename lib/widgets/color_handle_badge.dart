import 'package:flutter/material.dart';

/// Small handle-shaped bar centered along a widget's bottom edge — the
/// same shape as the drag handle on the color sheet it opens, so it reads
/// as "there's a menu here" by its form alone, regardless of how much
/// contrast its own color has against the widget behind it.
class ColorHandleBadge extends StatelessWidget {
  final Color background;
  final Color foreground;
  final double width;
  final double height;

  const ColorHandleBadge({
    super.key,
    required this.background,
    required this.foreground,
    this.width = 30,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: foreground.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
    );
  }
}

/// Small filled circle for a color's background, with a thin outline in
/// its foreground — a literal swatch (unlike [ColorHandleBadge], which is
/// just an affordance hint) for wherever a full nameplate would be too
/// heavy, e.g. leading a bus name in a list.
class ColorDot extends StatelessWidget {
  final Color background;
  final Color foreground;
  final double size;

  const ColorDot({
    super.key,
    required this.background,
    required this.foreground,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(color: foreground, width: 1),
      ),
    );
  }
}
