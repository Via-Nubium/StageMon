import 'package:flutter/widgets.dart';

/// One column of the mixer's fader strip.
///
/// Pure layout: a [head] of fixed height (a pan knob, a button, or an empty
/// gap — the columns line up because they all reserve the same height), the
/// fader filling everything left, and an optional [footer] under it. What goes
/// in each slot, and every difference between one kind of column and the next,
/// stays at the call site.
class FaderColumn extends StatelessWidget {
  const FaderColumn({
    super.key,
    required this.width,
    required this.head,
    required this.child,
    this.footer,
    this.background,
  });

  final double width;
  final Widget head;
  final Widget child;
  final Widget? footer;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: background,
      child: Column(
        children: [
          head,
          Expanded(child: child),
          ?footer,
        ],
      ),
    );
  }
}
