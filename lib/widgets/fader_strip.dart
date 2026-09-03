import 'package:flutter/widgets.dart';

import '../controllers/fader_strip_controller.dart';

/// A horizontal strip of faders that scrolls, flings and pinch-resizes as one.
///
/// The strip never scrolls itself: [NeverScrollableScrollPhysics] refuses the
/// usual drag, and every touch instead goes to [controller] through the single
/// [Listener] below, which decides per finger whether it is dragging one fader
/// or moving the whole strip. See FaderStripController for why the gestures
/// are owned rather than left to recognizers.
///
/// [columns] each lay out at the controller's current fader width. [trailing]
/// is a column of fixed [trailingWidth] that rides along at the end of the
/// scrolling content — the mixer's MASTER, when it isn't pinned outside.
class FaderStrip extends StatelessWidget {
  const FaderStrip({
    super.key,
    required this.controller,
    required this.columns,
    this.trailing,
    this.trailingWidth = 0,
    this.padding = EdgeInsets.zero,
  });

  final FaderStripController controller;
  final List<Widget> columns;
  final Widget? trailing;
  final double trailingWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Told here rather than by the caller, so what the pinch's extent math
    // believes is on screen is the list actually being laid out.
    controller.setContentMetrics(
      scalableColumns: columns.length,
      fixedWidth: trailingWidth + padding.horizontal,
    );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: controller.onPointerDown,
      onPointerMove: controller.onPointerMove,
      onPointerUp: controller.onPointerUpOrCancel,
      onPointerCancel: controller.onPointerUpOrCancel,
      child: SingleChildScrollView(
        controller: controller.scrollController,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...columns, ?trailing],
        ),
      ),
    );
  }
}
