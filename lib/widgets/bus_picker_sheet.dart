import 'package:flutter/material.dart';
import '../models/channel_color.dart';
import 'color_handle_badge.dart';

/// One entry in the bus picker — a single bus, or a linked pair collapsed
/// into one row. [matches] lists every bus number this row represents, so
/// a linked pair still highlights as selected regardless of which of its
/// two bus numbers is the one currently stored. [colorIndex] is always the
/// console-reported color — unlike the rest of the app's colorable items,
/// the picker deliberately ignores any local override, so callers resolve
/// a missing console value to 0 (OFF) before constructing this.
class BusOption {
  final int value;
  final String label;
  final List<int> matches;
  final int colorIndex;

  const BusOption({
    required this.value,
    required this.label,
    required this.matches,
    required this.colorIndex,
  });
}

/// Picker for the aux bus shown on the mixer screen. Deliberately one tap
/// deeper than a chip row — this is a "set once, rarely revisit" choice,
/// not something that benefits from being one tap away.
Future<void> showBusPickerSheet({
  required BuildContext context,
  required List<BusOption> options,
  required int selected,
  required ValueChanged<int> onSelected,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF17181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _BusPickerSheet(
      options: options,
      selected: selected,
      onSelected: onSelected,
    ),
  );
}

class _BusPickerSheet extends StatelessWidget {
  final List<BusOption> options;
  final int selected;
  final ValueChanged<int> onSelected;

  const _BusPickerSheet({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF454C5A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          for (final o in options)
            _BusRow(
              label: o.label,
              selected: o.matches.contains(selected),
              colorIndex: o.colorIndex,
              onTap: () {
                onSelected(o.value);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BusRow extends StatelessWidget {
  final String label;
  final bool selected;
  final int colorIndex;
  final VoidCallback onTap;

  const _BusRow({
    required this.label,
    required this.selected,
    required this.colorIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = channelColorByIndex(colorIndex);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            ColorDot(background: color.background, foreground: color.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15.5, color: Colors.white),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected
                  ? const Color(0xFF9EC2FF)
                  : const Color(0xFF5C6470),
            ),
          ],
        ),
      ),
    );
  }
}
