import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/osc_service.dart';

// Knob height used by mixer_screen to lay out columns.
const double kPanKnobHeight = 52.0;

class PanKnob extends StatefulWidget {
  final String oscAddress;
  final OscService service;

  const PanKnob({
    super.key,
    required this.oscAddress,
    required this.service,
  });

  @override
  State<PanKnob> createState() => _PanKnobState();
}

class _PanKnobState extends State<PanKnob> {
  double _value = 0.5;
  bool _isDragging = false;
  double? _dragStartX;
  double? _dragStartValue;
  Timer? _throttleTimer;
  double? _pendingValue;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(widget.oscAddress, _onConsoleValue);
    widget.service.request(widget.oscAddress);
  }

  @override
  void didUpdateWidget(PanKnob oldWidget) {
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
    _dragStartX = d.localPosition.dx;
    _dragStartValue = _value;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dragStartX == null || _dragStartValue == null) return;
    const sensitivity = 0.004;
    final delta = (d.localPosition.dx - _dragStartX!) * sensitivity;
    final newVal = (_dragStartValue! + delta).clamp(0.0, 1.0);
    setState(() => _value = newVal);
    _sendValue(newVal);
  }

  void _onDragEnd(DragEndDetails _) {
    _isDragging = false;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    if (_pendingValue != null) {
      widget.service.send(widget.oscAddress, _pendingValue!);
      _pendingValue = null;
    }
    _dragStartX = null;
    _dragStartValue = null;
  }

  void _onDoubleTap() {
    setState(() => _value = 0.5);
    widget.service.send(widget.oscAddress, 0.5);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onDoubleTap: _onDoubleTap,
      child: SizedBox(
        width: double.infinity,
        height: kPanKnobHeight,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PanKnobPainter(_value),
          ),
        ),
      ),
    );
  }
}

class _PanKnobPainter extends CustomPainter {
  final double value; // 0.0 = full L, 0.5 = center, 1.0 = full R

  const _PanKnobPainter(this.value);

  // Arc spans from 7 o'clock (L) → 12 o'clock (C) → 5 o'clock (R), clockwise.
  // In Flutter canvas angles (0 = right, clockwise positive):
  //   7 o'clock = 120° = 2π/3
  //   12 o'clock = 270° = 3π/2  (center)
  //   5 o'clock = 60° = π/3  (= 7π/3 mod 2π after 300° sweep)
  static const _startAngle = 2 * math.pi / 3;
  static const _sweepAngle = 5 * math.pi / 3;
  static const _centerAngle = _startAngle + _sweepAngle / 2; // = 3π/2

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2 - 8, (size.height - 10) / 1.87);
    final cx = size.width / 2;
    final cy = 5.0 + r;
    final center = Offset(cx, cy);

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Active arc from center angle to value angle
    if ((value - 0.5).abs() > 0.005) {
      final valueAngle = _startAngle + _sweepAngle * value;
      final double arcStart;
      final double arcSweep;
      if (value < 0.5) {
        arcStart = valueAngle;
        arcSweep = _centerAngle - valueAngle;
      } else {
        arcStart = _centerAngle;
        arcSweep = valueAngle - _centerAngle;
      }
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        arcStart,
        arcSweep,
        false,
        Paint()
          ..color = const Color(0xFF2979FF).withValues(alpha: 0.9)
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center tick at 12 o'clock
    final tickDir = Offset(math.cos(_centerAngle), math.sin(_centerAngle));
    canvas.drawLine(
      center + tickDir * (r - 5),
      center + tickDir * (r + 5),
      Paint()..color = Colors.white30..strokeWidth = 1.5,
    );

    // Indicator line from mid-radius to outer circle
    final angle = _startAngle + _sweepAngle * value;
    final lineStart = center + Offset(r / 2 * math.cos(angle), r / 2 * math.sin(angle));
    final lineEnd = center + Offset(r * math.cos(angle), r * math.sin(angle));
    canvas.drawLine(
      lineStart,
      lineEnd,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // L / R labels beside arc endpoints
    const labelStyle = TextStyle(
      color: Color(0xFF666666),
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );
    final lEndX = cx + r * math.cos(_startAngle);
    final lEndY = cy + r * math.sin(_startAngle);
    final rEndX = cx + r * math.cos(_startAngle + _sweepAngle);
    final rEndY = cy + r * math.sin(_startAngle + _sweepAngle);

    _drawText(canvas, 'L', Offset(lEndX - 13, lEndY), labelStyle);
    _drawText(canvas, 'R', Offset(rEndX + 8, rEndY), labelStyle);
  }

  void _drawText(Canvas canvas, String text, Offset topLeft, TextStyle style) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, topLeft - Offset(0, p.height / 2));
  }

  @override
  bool shouldRepaint(_PanKnobPainter old) => old.value != value;
}
