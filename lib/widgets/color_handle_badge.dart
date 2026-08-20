import 'package:flutter/material.dart';

/// Small handle-shaped bar centered along a widget's bottom edge — the
/// same shape as the drag handle on the color sheet it opens, so it reads
/// as "there's a menu here" by its form alone, regardless of how much
/// contrast its own color has against the widget behind it.
class ColorHandleBadge extends StatelessWidget {
  final Color? background;
  final Color? foreground;
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
        color: background ?? const Color(0xFF454C5A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: (foreground ?? const Color(0xFF5C6470)).withValues(
            alpha: 0.55,
          ),
          width: 1,
        ),
      ),
    );
  }
}
