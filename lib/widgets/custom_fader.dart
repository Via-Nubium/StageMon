import 'dart:async';
import 'package:flutter/material.dart';
import '../models/channel_color.dart';
import '../services/osc_service.dart';

double faderToDbValue(double f) {
  if (f < 0.0005) return -90.0;
  if (f < 0.0625) return f * 480.0 - 90.0;
  if (f < 0.25) return f * 160.0 - 70.0;
  if (f < 0.5) return f * 80.0 - 50.0;
  return f * 40.0 - 30.0;
}

double dbToFader(double db) {
  if (db <= -90.0) return 0.0;
  double f;
  if (db < -60.0) {
    f = (db + 90.0) / 480.0;
  } else if (db < -30.0) {
    f = (db + 70.0) / 160.0;
  } else if (db < -10.0) {
    f = (db + 50.0) / 80.0;
  } else {
    f = (db + 30.0) / 40.0;
  }
  return f.clamp(0.0, 1.0);
}

String faderToDb(double f) {
  final db = faderToDbValue(f);
  if (db <= -90.0) return '-∞';
  if (db >= 0) return '+${db.toStringAsFixed(1)} dB';
  return '${db.toStringAsFixed(1)} dB';
}

const double _kKnobH = 26.0;
const double _kKnobW = 40.0;
const double _kMainKnobH = 52.0;
const double _kMainKnobW = 40.0;
const double _kTrackW = 6.0;
const double _kPad = 2.0;
// On content that doesn't overflow its scroll view, there's no competing
// horizontal-scroll recognizer to make Flutter wait for real movement
// before granting this drag the gesture arena — it can "win" the instant a
// finger touches down, with zero actual displacement. That's indistinguishable
// from a genuine drag at onDragStart time, so onDragActiveStart is deferred
// until the finger has actually moved vertically past this threshold —
// mirroring the touch slop Flutter would have enforced had there been a
// competitor. A pinch's fingers move mostly horizontally and never cross it.
const double _kDragIntentThreshold = 6.0;

/// Drives a fader's value from pointer events owned by an ancestor widget
/// instead of by this fader's own GestureDetector.
///
/// Nesting a per-fader drag recognizer inside a screen-wide pinch/scroll one
/// makes every two-finger gesture a race between their independent slop
/// thresholds — whichever self-declares first wins *all* the pointers it
/// tracks, not just the one that moved. mixer_screen sidesteps that race by
/// owning the raw pointers itself and deciding, and this is how it reaches
/// into a fader once it has decided.
///
/// Deliberately dumb: no slop, no axis logic. The parent owns those and only
/// calls [startDrag] at the moment it commits, passing the position *at that
/// moment* — so the fader starts moving from zero right there rather than
/// jumping by however far the finger travelled while the parent made up its
/// mind.
class FaderDragController {
  void Function()? _onStart;
  void Function(double dy)? _onUpdate;
  void Function()? _onEnd;
  double? _startY;

  bool get isDragging => _startY != null;

  void bind({
    required void Function() onStart,
    required void Function(double dy) onUpdate,
    required void Function() onEnd,
  }) {
    _onStart = onStart;
    _onUpdate = onUpdate;
    _onEnd = onEnd;
  }

  void unbind() {
    endDrag();
    _onStart = null;
    _onUpdate = null;
    _onEnd = null;
  }

  void startDrag(double localY) {
    _startY = localY;
    _onStart?.call();
  }

  void updateDrag(double localY) {
    if (_startY != null) _onUpdate?.call(localY - _startY!);
  }

  void endDrag() {
    if (_startY == null) return;
    _startY = null;
    _onEnd?.call();
  }
}

class CustomFader extends StatefulWidget {
  final String label;
  final String oscAddress;
  final OscService service;
  final Color accentColor;
  final ValueNotifier<double>? meterLevel;
  final ValueNotifier<double>? meterLevelRight;
  final bool isMain;
  // Index into kChannelColors for this channel's name background/text —
  // null means no override (name renders plain, as before).
  final int? nameColorIndex;
  // When set, this fader is driven externally (mixer_screen's unified
  // pointer owner) instead of by its own GestureDetector — see
  // FaderDragController. Null (the default) keeps the fully self-contained
  // behavior used by group_detail_screen.dart and the pinned bus fader.
  final FaderDragController? controller;

  const CustomFader({
    super.key,
    required this.label,
    required this.oscAddress,
    required this.service,
    this.accentColor = const Color(0xFF2979FF),
    this.meterLevel,
    this.meterLevelRight,
    this.isMain = false,
    this.nameColorIndex,
    this.controller,
  });

  @override
  State<CustomFader> createState() => _CustomFaderState();
}

class _CustomFaderState extends State<CustomFader> {
  double _value = 0.0;
  bool _isDragging = false;
  Timer? _throttleTimer;
  double? _pendingValue;
  double? _dragStartValue;
  double? _dragStartY;
  bool _signaledDragActive = false;
  double _dragActivationDy = 0;
  // Latest LayoutBuilder height, kept around for the controller-driven
  // callbacks below, which run outside that builder's own closure.
  double _paintHeight = 0;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(widget.oscAddress, _onConsoleValue);
    widget.service.request(widget.oscAddress);
    widget.controller?.bind(
      onStart: _onControllerDragStart,
      onUpdate: _onControllerDragUpdate,
      onEnd: _onControllerDragEnd,
    );
  }

  @override
  void didUpdateWidget(CustomFader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oscAddress != widget.oscAddress) {
      oldWidget.service.removeListener(oldWidget.oscAddress, _onConsoleValue);
      widget.service.addListener(widget.oscAddress, _onConsoleValue);
      widget.service.request(widget.oscAddress);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.unbind();
      widget.controller?.bind(
        onStart: _onControllerDragStart,
        onUpdate: _onControllerDragUpdate,
        onEnd: _onControllerDragEnd,
      );
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(widget.oscAddress, _onConsoleValue);
    widget.controller?.unbind();
    _throttleTimer?.cancel();
    super.dispose();
  }

  void _onConsoleValue(dynamic value) {
    if (value is double && mounted && !_isDragging) {
      setState(() => _value = value.clamp(0.0, 1.0));
    }
  }

  void _sendValue(double v) {
    _pendingValue = v;
    // Timer.periodic sends at most every 50ms while the user is dragging.
    _throttleTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_pendingValue != null) {
        widget.service.send(widget.oscAddress, _pendingValue!);
        _pendingValue = null;
      } else {
        _throttleTimer?.cancel();
        _throttleTimer = null;
      }
    });
  }

  void _onDragStart(DragStartDetails d) {
    _isDragging = true;
    _signaledDragActive = false;
    _dragStartValue = _value;
    _dragStartY = d.localPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails d, double height) {
    if (!_isDragging) return;
    final dy = d.localPosition.dy - _dragStartY!;
    if (!_signaledDragActive) {
      if (dy.abs() < _kDragIntentThreshold) return;
      _signaledDragActive = true;
      // Lock in the offset at the exact moment of crossing, so the fader
      // starts moving from zero right here instead of jumping by however
      // far the finger already traveled through the dead zone.
      _dragActivationDy = dy;
    }
    final knobH = widget.isMain ? _kMainKnobH : _kKnobH;
    final travel = height - knobH - _kPad * 2;
    if (travel <= 0) return;
    final effectiveDy = dy - _dragActivationDy;
    final newValue = (_dragStartValue! - effectiveDy / travel).clamp(0.0, 1.0);
    setState(() => _value = newValue);
    _sendValue(newValue);
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_isDragging) return;
    _isDragging = false;
    // Flush any pending value immediately when the user lifts their finger.
    _throttleTimer?.cancel();
    _throttleTimer = null;
    if (_pendingValue != null) {
      widget.service.send(widget.oscAddress, _pendingValue!);
      _pendingValue = null;
    }
  }

  // ── Controller-driven path (mixer_screen's unified pointer owner) ────────
  // Same value math as above, but the axis-lock/dead-zone decision already
  // happened in the parent before FaderDragController.startDrag was called,
  // so there's nothing to re-check here.

  void _onControllerDragStart() {
    _isDragging = true;
    _dragStartValue = _value;
  }

  void _onControllerDragUpdate(double effectiveDy) {
    final knobH = widget.isMain ? _kMainKnobH : _kKnobH;
    final travel = _paintHeight - knobH - _kPad * 2;
    if (travel <= 0) return;
    final newValue = (_dragStartValue! - effectiveDy / travel).clamp(0.0, 1.0);
    setState(() => _value = newValue);
    _sendValue(newValue);
  }

  void _onControllerDragEnd() {
    _isDragging = false;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    if (_pendingValue != null) {
      widget.service.send(widget.oscAddress, _pendingValue!);
      _pendingValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Builder(
            builder: (context) {
              final nameColor = widget.nameColorIndex != null
                  ? channelColorByIndex(widget.nameColorIndex!)
                  : null;
              final text = Text(
                widget.label,
                style: TextStyle(
                  color: nameColor != null
                      ? nameColor.foreground
                      : (widget.isMain ? widget.accentColor : Colors.white),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              if (nameColor == null) return text;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: channelColorFill(
                  nameColor,
                  radius: 4,
                  borderWidth: 1.4,
                ),
                child: text,
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              _paintHeight = h;
              final paint = RepaintBoundary(
                child: CustomPaint(
                  painter: FaderPainter(
                    _value,
                    widget.accentColor,
                    widget.isMain,
                    widget.meterLevel,
                    widget.meterLevelRight,
                  ),
                  size: Size(constraints.maxWidth, h),
                ),
              );
              if (widget.controller != null) {
                // Hit-tested by mixer_screen's unified pointer owner via
                // this MetaData, not by a GestureDetector of our own — see
                // FaderDragController's doc comment for why.
                return MetaData(
                  metaData: widget.controller,
                  behavior: HitTestBehavior.opaque,
                  child: paint,
                );
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
                onVerticalDragEnd: _onDragEnd,
                child: paint,
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          faderToDb(_value),
          style: TextStyle(color: widget.accentColor, fontSize: 13),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class FaderPainter extends CustomPainter {
  final double value;
  final Color accentColor;
  final bool isMain;
  final ValueNotifier<double>? _meterNotifier;
  final ValueNotifier<double>? _meterNotifierRight;

  FaderPainter(
    this.value,
    this.accentColor,
    this.isMain, [
    ValueNotifier<double>? meterLevel,
    ValueNotifier<double>? meterLevelRight,
  ]) : _meterNotifier = meterLevel,
       _meterNotifierRight = meterLevelRight,
       super(
         repaint: meterLevel != null && meterLevelRight != null
             ? Listenable.merge([meterLevel, meterLevelRight])
             : meterLevel ?? meterLevelRight,
       );

  double get _effectiveKnobH => isMain ? _kMainKnobH : _kKnobH;
  double get _effectiveKnobW => isMain ? _kMainKnobW : _kKnobW;

  double _knobTopY(double height) {
    final travel = height - _effectiveKnobH - _kPad * 2;
    return _kPad + (1.0 - value) * travel;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    if (_meterNotifier != null) {
      const gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xCCF44336),
          Color(0xCCFFEB3B),
          Color(0xCC4CAF50),
          Color(0xCC4CAF50),
        ],
        stops: [0.0, 0.2, 0.45, 1.0],
      );
      final maxVuH = size.height * 0.50;
      final vuLeft = cx + _kTrackW / 2 + 4;
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x99888888);

      void drawFill(double left, double level) {
        if (level > 0.01) {
          final fullRect = Rect.fromLTWH(left, size.height - maxVuH, 6, maxVuH);
          final vuH = maxVuH * level;
          canvas.drawRect(
            Rect.fromLTWH(left, size.height - vuH, 6, vuH),
            Paint()..shader = gradient.createShader(fullRect),
          );
        }
      }

      drawFill(vuLeft, _meterNotifier.value);
      if (_meterNotifierRight != null) {
        drawFill(vuLeft + 8, _meterNotifierRight.value);
        // Stereo: 3 outer sides per bar + single center divider (avoids double inner edge)
        const pad = 0.75;
        final top = size.height - maxVuH - pad;
        final bot = size.height + pad;
        final divX = vuLeft + 7.0; // center of 2px gap between bars
        final path = Path()
          ..moveTo(divX, top)
          ..lineTo(vuLeft - pad, top)
          ..lineTo(vuLeft - pad, bot)
          ..lineTo(divX, bot)
          ..moveTo(divX, top)
          ..lineTo(vuLeft + 14 + pad, top)
          ..lineTo(vuLeft + 14 + pad, bot)
          ..lineTo(divX, bot);
        canvas.drawPath(path, borderPaint);
      } else {
        final fullRect = Rect.fromLTWH(vuLeft, size.height - maxVuH, 6, maxVuH);
        canvas.drawRect(fullRect.inflate(0.75), borderPaint);
      }
    }

    final hsl = HSLColor.fromColor(accentColor);
    final knobLight = hsl
        .withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0))
        .toColor();
    final knobDark = hsl
        .withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0))
        .toColor();

    // Track
    final trackRect = Rect.fromLTWH(
      cx - _kTrackW / 2,
      0,
      _kTrackW,
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(3)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3E64), Color(0xFF0D2040)],
        ).createShader(trackRect),
    );

    // Reference marks: 0 dB prominent, -10 dB and -30 dB at scale breakpoints
    final travel = size.height - _effectiveKnobH - _kPad * 2;
    const tickFaders = [(0.75, true), (0.5, false), (0.25, false)];
    for (final (f, prominent) in tickFaders) {
      final y = _kPad + (1.0 - f) * travel + _effectiveKnobH / 2;
      canvas.drawLine(
        Offset(cx - _kTrackW / 2 - (prominent ? 7.0 : 5.5), y),
        Offset(cx + _kTrackW / 2 + (prominent ? 7.0 : 5.5), y),
        Paint()
          ..color = const Color(
            0xFF2979FF,
          ).withValues(alpha: prominent ? 0.7 : 0.5)
          ..strokeWidth = prominent ? 2.0 : 1.5,
      );
    }

    // Knob
    final ky = _knobTopY(size.height);
    final kw = _effectiveKnobW;
    final kh = _effectiveKnobH;
    final knobBounds = Rect.fromLTWH(cx - kw / 2, ky, kw, kh);

    final Path knobPath;
    if (isMain) {
      // Concave (hourglass) shape: wide top/bottom, curved waist in the middle
      const cr = 5.0; // corner radius
      const wi = 3.0; // waist control-point inset → ~3 px visual indentation
      final hh = ky + kh / 2;
      final l = cx - kw / 2;
      final r = cx + kw / 2;
      knobPath = Path()
        ..moveTo(l + cr, ky)
        ..lineTo(r - cr, ky)
        ..quadraticBezierTo(r, ky, r, ky + cr)
        ..quadraticBezierTo(r - wi, hh, r, ky + kh - cr)
        ..quadraticBezierTo(r, ky + kh, r - cr, ky + kh)
        ..lineTo(l + cr, ky + kh)
        ..quadraticBezierTo(l, ky + kh, l, ky + kh - cr)
        ..quadraticBezierTo(l + wi, hh, l, ky + cr)
        ..quadraticBezierTo(l, ky, l + cr, ky)
        ..close();
    } else {
      knobPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(knobBounds, const Radius.circular(7)),
        );
    }

    // Glow
    canvas.drawPath(
      knobPath,
      Paint()
        ..color = accentColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Fill
    canvas.drawPath(
      knobPath,
      Paint()
        ..shader =
            (isMain
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [knobDark, knobLight],
                      )
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [knobLight, knobDark],
                      ))
                .createShader(knobBounds),
    );

    // Top rim highlight + bottom shadow (main knob only)
    if (isMain) {
      canvas.drawLine(
        Offset(cx - kw / 2 + 3, ky + 2.0),
        Offset(cx + kw / 2 - 3, ky + 2.0),
        Paint()
          ..color = knobLight.withValues(alpha: 0.9)
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(cx - kw / 2 + 3, ky + kh - 2.0),
        Offset(cx + kw / 2 - 3, ky + kh - 2.0),
        Paint()
          ..color = knobDark.withValues(alpha: 0.9)
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Border
    canvas.drawPath(
      knobPath,
      Paint()
        ..color = accentColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Center stripe
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - kw / 2 + 7,
          ky + kh / 2 - 1.25,
          kw - 14,
          isMain ? 3.5 : 2.5,
        ),
        const Radius.circular(1.75),
      ),
      Paint()..color = Colors.white.withValues(alpha: isMain ? 0.55 : 0.4),
    );
  }

  @override
  bool shouldRepaint(FaderPainter old) =>
      old.value != value ||
      old.accentColor != accentColor ||
      old.isMain != isMain ||
      old._meterNotifier != _meterNotifier ||
      old._meterNotifierRight != _meterNotifierRight;
}
