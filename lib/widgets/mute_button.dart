import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';

class MuteButton extends StatefulWidget {
  final bool isMuted;
  final String label;
  final void Function(bool newMuted) onToggle;

  const MuteButton({
    super.key,
    required this.isMuted,
    required this.label,
    required this.onToggle,
  });

  @override
  State<MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<MuteButton>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _controller?.dispose();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _startHold() {
    if (_controller != null) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _commit();
      });
    _controller!.forward();
    _insertOverlay();
  }

  void _cancel() {
    if (_controller == null) return;
    _controller!.stop();
    _controller!.dispose();
    _controller = null;
    _removeOverlay();
  }

  void _commit() {
    final c = _controller;
    _controller = null;
    c?.dispose();
    _removeOverlay();
    widget.onToggle(!widget.isMuted);
  }

  void _insertOverlay() {
    final overlay = Overlay.of(context);
    final animation = _controller!;
    final l = AppLocalizations.of(context)!;
    final actionLabel = widget.isMuted
        ? l.muteUnmuting(widget.label)
        : l.muteMuting(widget.label);
    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: _MuteProgressCard(
              animation: animation,
              actionLabel: actionLabel,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isMuted;
    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: Container(
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? Colors.red : Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? Colors.red : Colors.red.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: Text(
            'MUTE',
            style: TextStyle(
              color: active ? Colors.white : Colors.red.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _MuteProgressCard extends StatelessWidget {
  final Animation<double> animation;
  final String actionLabel;

  const _MuteProgressCard({
    required this.animation,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xEE1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              actionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 220,
              child: AnimatedBuilder(
                animation: animation,
                builder: (_, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: animation.value,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
