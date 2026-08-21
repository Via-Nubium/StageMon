import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/channel_color.dart';
import '../services/osc_service.dart';
import 'custom_fader.dart';

const Color _kGroupColor = Color(0xFF00C853);

class GroupFader extends StatefulWidget {
  final String label;
  final List<int> channels; // channel numbers 1-16
  final List<int> fxReturns; // FX return numbers 1-4
  final bool lineIn;
  final int busNum;
  final OscService service;
  // Index into kChannelColors for this group's name background/text.
  final int nameColorIndex;
  // Lets a parent screen (e.g. a pinch-to-resize gesture) veto starting a
  // vertical drag, and be told when one starts/ends so it can do the same
  // in reverse.
  final bool Function()? isPinchActive;
  final VoidCallback? onDragActiveStart;
  final VoidCallback? onDragActiveEnd;

  const GroupFader({
    super.key,
    required this.label,
    required this.channels,
    this.fxReturns = const [],
    this.lineIn = false,
    required this.busNum,
    required this.service,
    required this.nameColorIndex,
    this.isPinchActive,
    this.onDragActiveStart,
    this.onDragActiveEnd,
  });

  @override
  State<GroupFader> createState() => _GroupFaderState();
}

class _GroupFaderState extends State<GroupFader> {
  // Keys: channels 1-16, FX returns 101-104, Line In 200
  final Map<int, double> _memberValues = {};
  final Map<int, void Function(dynamic)> _listeners = {};
  final Map<int, Timer?> _throttleTimers = {};
  final Map<int, double?> _pendingValues = {};

  bool _isDragging = false;
  Map<int, double>? _dragStartValues;
  double? _dragStartDisplayValue;
  double? _dragStartY;
  bool _signaledDragActive = false;
  double _dragActivationDy = 0;
  // See custom_fader.dart's _kDragIntentThreshold: on non-overflowing
  // content, this drag can win the gesture arena the instant a finger
  // touches down, with zero real movement — so onDragActiveStart is
  // deferred until genuine vertical intent is shown.
  static const double _kDragIntentThreshold = 6.0;

  Set<int> _subscribedKeys = {};
  int _subscribedBus = -1;

  List<int> _allMemberKeys() => [
    ...widget.channels,
    ...widget.fxReturns.map((r) => 100 + r),
    if (widget.lineIn) 200,
  ];

  String _oscAddressForKey(int key, int bus) {
    final b = bus.toString().padLeft(2, '0');
    if (key <= 16) {
      return '/ch/${key.toString().padLeft(2, '0')}/mix/$b/level';
    } else if (key < 200) {
      return '/rtn/${key - 100}/mix/$b/level';
    } else {
      return '/rtn/aux/mix/$b/level';
    }
  }

  double get _displayValue {
    final keys = _allMemberKeys();
    if (keys.isEmpty) return 0.0;
    final vals = keys.map((k) => _memberValues[k] ?? 0.0);
    final minVal = vals.reduce(min);
    final maxVal = vals.reduce(max);
    return (minVal + maxVal) / 2.0;
  }

  @override
  void initState() {
    super.initState();
    _refreshSubscriptions();
  }

  @override
  void didUpdateWidget(GroupFader old) {
    super.didUpdateWidget(old);
    final newKeys = _allMemberKeys().toSet();
    if (widget.busNum != _subscribedBus ||
        !setEquals(newKeys, _subscribedKeys)) {
      _refreshSubscriptions();
    }
  }

  void _refreshSubscriptions() {
    _unsubscribeAll();
    _memberValues.clear();
    final keys = _allMemberKeys();
    _subscribedKeys = keys.toSet();
    _subscribedBus = widget.busNum;
    for (final key in keys) {
      void listener(dynamic value) {
        if (value is double && mounted && !_isDragging) {
          setState(() => _memberValues[key] = value.clamp(0.0, 1.0));
        }
      }

      _listeners[key] = listener;
      widget.service.addListener(
        _oscAddressForKey(key, widget.busNum),
        listener,
      );
      widget.service.request(_oscAddressForKey(key, widget.busNum));
    }
  }

  void _unsubscribeAll() {
    for (final key in _subscribedKeys) {
      final l = _listeners[key];
      if (l != null) {
        widget.service.removeListener(
          _oscAddressForKey(key, _subscribedBus),
          l,
        );
      }
      _listeners.remove(key);
      _throttleTimers[key]?.cancel();
      _throttleTimers.remove(key);
    }
  }

  @override
  void dispose() {
    _unsubscribeAll();
    super.dispose();
  }

  void _sendMember(int key, double value) {
    _pendingValues[key] = value;
    _throttleTimers[key] ??= Timer.periodic(const Duration(milliseconds: 50), (
      _,
    ) {
      final v = _pendingValues[key];
      if (v != null) {
        widget.service.send(_oscAddressForKey(key, widget.busNum), v);
        _pendingValues[key] = null;
      } else {
        _throttleTimers[key]?.cancel();
        _throttleTimers[key] = null;
      }
    });
  }

  void _onDragStart(DragStartDetails d) {
    if (widget.isPinchActive?.call() == true) return;
    _isDragging = true;
    _signaledDragActive = false;
    _dragStartValues = Map.of(_memberValues);
    _dragStartDisplayValue = _displayValue;
    _dragStartY = d.localPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails d, double height) {
    if (!_isDragging) return;
    final dy = d.localPosition.dy - _dragStartY!;
    if (!_signaledDragActive) {
      if (widget.isPinchActive?.call() == true) {
        _isDragging = false;
        return;
      }
      if (dy.abs() < _kDragIntentThreshold) return;
      _signaledDragActive = true;
      // Lock in the offset at the exact moment of crossing, so the fader
      // starts moving from zero right here instead of jumping by however
      // far the finger already traveled through the dead zone.
      _dragActivationDy = dy;
      widget.onDragActiveStart?.call();
    }
    const kKnobH = 26.0;
    const kPad = 2.0;
    final travel = height - kKnobH - kPad * 2;
    if (travel <= 0) return;

    final effectiveDy = dy - _dragActivationDy;
    final rawDisplayFloat = (_dragStartDisplayValue! - effectiveDy / travel)
        .clamp(0.0, 1.0);

    double dbDelta =
        faderToDbValue(rawDisplayFloat) -
        faderToDbValue(_dragStartDisplayValue!);

    final keys = _allMemberKeys();
    double minDbDelta = double.negativeInfinity;
    double maxDbDelta = double.infinity;
    for (final key in keys) {
      final chDb = faderToDbValue(_dragStartValues![key] ?? 0.5);
      minDbDelta = max(minDbDelta, -90.0 - chDb);
      maxDbDelta = min(maxDbDelta, 10.0 - chDb);
    }
    if (minDbDelta > maxDbDelta) return;
    dbDelta = dbDelta.clamp(minDbDelta, maxDbDelta);

    final newVals = <int, double>{};
    for (final key in keys) {
      final chDb = faderToDbValue(_dragStartValues![key] ?? 0.5);
      newVals[key] = dbToFader(chDb + dbDelta);
    }

    setState(() => _memberValues.addAll(newVals));
    for (final entry in newVals.entries) {
      _sendMember(entry.key, entry.value);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_isDragging) return;
    _isDragging = false;
    if (_signaledDragActive) widget.onDragActiveEnd?.call();
    for (final key in _allMemberKeys()) {
      final v = _pendingValues[key];
      if (v != null) {
        widget.service.send(_oscAddressForKey(key, widget.busNum), v);
        _pendingValues[key] = null;
      }
      _throttleTimers[key]?.cancel();
      _throttleTimers[key] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayValue;
    final interactive = _allMemberKeys().isNotEmpty;
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Builder(
            builder: (context) {
              final nameColor = channelColorByIndex(widget.nameColorIndex);
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
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: nameColor.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              return IgnorePointer(
                ignoring: !interactive,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
                  onVerticalDragEnd: _onDragEnd,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: FaderPainter(
                        display,
                        interactive ? _kGroupColor : Colors.grey,
                        false,
                      ),
                      size: Size(constraints.maxWidth, h),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          interactive ? faderToDb(display) : '—',
          style: TextStyle(
            color: interactive ? _kGroupColor : Colors.grey,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
