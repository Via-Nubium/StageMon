import 'dart:async';
import 'package:flutter/material.dart';
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
  }else if (db < -30.0) {
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

class CustomFader extends StatefulWidget {
  final String label;
  final String oscAddress;
  final OscService service;
  final Color accentColor;
  final ValueNotifier<double>? meterLevel;
  final ValueNotifier<double>? meterLevelRight;
  final bool isMain;

  const CustomFader({
    super.key,
    required this.label,
    required this.oscAddress,
    required this.service,
    this.accentColor = const Color(0xFF2979FF),
    this.meterLevel,
    this.meterLevelRight,
    this.isMain = false,
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

  @override
  void initState() {
    super.initState();
    widget.service.addListener(widget.oscAddress, _onConsoleValue);
    widget.service.request(widget.oscAddress);
  }

  @override
  void didUpdateWidget(CustomFader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oscAddress != widget.oscAddress) {
      oldWidget.service.removeListener(oldWidget.oscAddress, _onConsoleValue);
      widget.service.addListener(widget.oscAddress, _onConsoleValue);
      widget.service.request(widget.oscAddress);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(widget.oscAddress, _onConsoleValue);
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
    _dragStartValue = _value;
    _dragStartY = d.localPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails d, double height) {
    final knobH = widget.isMain ? _kMainKnobH : _kKnobH;
    final travel = height - knobH - _kPad * 2;
    if (travel <= 0) return;
    final dy = d.localPosition.dy - _dragStartY!;
    final newValue = (_dragStartValue! - dy / travel).clamp(0.0, 1.0);
    setState(() => _value = newValue);
    _sendValue(newValue);
  }

  void _onDragEnd(DragEndDetails _) {
    _isDragging = false;
    // Flush any pending value immediately when the user lifts their finger.
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
          child: Text(
            widget.label,
            style: TextStyle(color: widget.isMain ? widget.accentColor : Colors.white, fontSize: 13),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
                onVerticalDragEnd: _onDragEnd,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: FaderPainter(_value, widget.accentColor, widget.isMain, widget.meterLevel, widget.meterLevelRight),
                    size: Size(constraints.maxWidth, h),
                  ),
                ),
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

  FaderPainter(this.value, this.accentColor, this.isMain,
      [ValueNotifier<double>? meterLevel, ValueNotifier<double>? meterLevelRight])
      : _meterNotifier = meterLevel,
        _meterNotifierRight = meterLevelRight,
        super(
            repaint: meterLevel != null && meterLevelRight != null
                ? Listenable.merge([meterLevel, meterLevelRight])
                : meterLevel ?? meterLevelRight);

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
    final knobLight = hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
    final knobDark = hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();

    // Track
    final trackRect = Rect.fromLTWH(cx - _kTrackW / 2, 0, _kTrackW, size.height);
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
          ..color = const Color(0xFF2979FF).withValues(alpha: prominent ? 0.7 : 0.5)
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
      const cr = 5.0;   // corner radius
      const wi = 3.0;   // waist control-point inset → ~3 px visual indentation
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
        ..addRRect(RRect.fromRectAndRadius(knobBounds, const Radius.circular(7)));
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
        ..shader = (isMain
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
