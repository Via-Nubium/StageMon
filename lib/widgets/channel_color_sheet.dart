import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/channel_color.dart';

/// One fader that can be colored from the sheet — a channel, LINE, or an
/// FX return. The sheet doesn't know which; it just walks this list.
class ColorableFader {
  final String label;
  final int? colorIndex;
  final ValueChanged<int?> onChanged;
  // What the console itself currently reports for this fader — null if it
  // hasn't answered yet. Drives the console-sync swatch's own color.
  final int? consoleColorIndex;
  // False for faders with no console counterpart (e.g. group faders): the
  // console-sync swatch stays visible but disabled, so the sheet's height
  // doesn't jump as the </> arrows step across faders that do and don't
  // support it.
  final bool allowConsoleSync;

  const ColorableFader({
    required this.label,
    required this.colorIndex,
    required this.onChanged,
    required this.consoleColorIndex,
    this.allowConsoleSync = true,
  });
}

/// Long-press menu for a fader's Settings chip: 16 fixed console colors
/// plus a console-sync option that means "no override, follow the console".
/// The </> arrows step through [items] without closing the sheet. Each tap
/// applies immediately — there's nothing to confirm, so tapping outside
/// just closes it.
Future<void> showChannelColorSheet({
  required BuildContext context,
  required List<ColorableFader> items,
  required int initialPosition,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF17181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _ChannelColorSheet(
      items: items,
      initialPosition: initialPosition,
    ),
  );
}

class _ChannelColorSheet extends StatefulWidget {
  final List<ColorableFader> items;
  final int initialPosition;

  const _ChannelColorSheet({
    required this.items,
    required this.initialPosition,
  });

  @override
  State<_ChannelColorSheet> createState() => _ChannelColorSheetState();
}

class _ChannelColorSheetState extends State<_ChannelColorSheet> {
  late int _position = widget.initialPosition;
  late final List<int?> _colors = widget.items
      .map((e) => e.colorIndex)
      .toList();

  void _select(int? index) {
    setState(() => _colors[_position] = index);
    widget.items[_position].onChanged(index);
  }

  void _go(int delta) {
    final next = (_position + delta).clamp(0, widget.items.length - 1);
    if (next != _position) setState(() => _position = next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final item = widget.items[_position];
    final selected = _colors[_position];
    final consolePreview = item.consoleColorIndex != null
        ? channelColorByIndex(item.consoleColorIndex!)
        : kConsoleColorPlaceholder;
    final preview = selected != null
        ? channelColorByIndex(selected)
        : consolePreview;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF454C5A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                _StepArrow(
                  icon: Icons.chevron_left,
                  onTap: _position > 0 ? () => _go(-1) : null,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: _NamePlate(
                        text: item.label.toUpperCase(),
                        color: preview,
                        height: 34,
                      ),
                    ),
                  ),
                ),
                _StepArrow(
                  icon: Icons.chevron_right,
                  onTap: _position < widget.items.length - 1
                      ? () => _go(1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 84,
                  child: _Swatch(
                    text: l.consoleColorOption,
                    color: consolePreview,
                    selected: selected == null,
                    enabled: item.allowConsoleSync,
                    onTap: () => _select(null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.syncColorFromMixer,
                    style: TextStyle(
                      color: item.allowConsoleSync
                          ? const Color(0xFF8B93A1)
                          : const Color(0xFF4A4F58),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              l.chooseColorManually.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF8B93A1),
                fontSize: 10.5,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.85,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Iterates indices rather than the list itself: the position
              // in kChannelColors *is* the console's value for that color.
              children: [
                for (var i = 0; i < kChannelColors.length; i++)
                  _Swatch(
                    text: localizedColorLabel(l, i),
                    color: kChannelColors[i],
                    selected: selected == i,
                    onTap: () => _select(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 34,
      color: const Color(0xFFE7E9ED),
      disabledColor: const Color(0xFF3A3E47),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: onTap,
    );
  }
}

class _NamePlate extends StatelessWidget {
  final String text;
  final ChannelColorOption color;
  final double? height;

  const _NamePlate({required this.text, required this.color, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.background,
              border: Border.all(color: color.foreground, width: 1.5),
            ),
          ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFECEDEF),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String text;
  final ChannelColorOption color;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const _Swatch({
    required this.text,
    required this.color,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final fill = channelColorFill(color);
    final content = Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: selected
            ? const [
                BoxShadow(color: Colors.white, spreadRadius: 5),
                BoxShadow(color: Color(0xFF17181C), spreadRadius: 2.5),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: fill,
              alignment: Alignment.center,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: 3,
              right: 3,
              child: Icon(
                Icons.check_circle,
                size: 16,
                color: color.foreground,
              ),
            ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: selected
              ? Transform.translate(
                  offset: const Offset(0, -1),
                  child: Transform.scale(scale: 1.04, child: content),
                )
              : content,
        ),
      ),
    );
  }
}
