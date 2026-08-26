import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// Keeps the screen on (no lock, no timeout) while active, but dims it after
// a period of inactivity instead of leaving it at full brightness forever —
// mirroring, as closely as a normal app can, when Android's own screen
// timeout would have dimmed/locked. There's no OS signal for "about to dim"
// (ACTION_SCREEN_OFF fires only once the screen is already off), so this
// reads the user's configured Settings > Display > Screen timeout and dims
// shortly before that would have elapsed.
class ScreenAwakeService {
  ScreenAwakeService._();

  static const _displayChannel = MethodChannel(
    'com.vianubium.stagemon/display',
  );

  // Approximates the brief dim step Android does itself just before
  // locking: a fixed lead time doesn't hold up across the range of
  // timeouts users configure, so short timeouts dim proportionally
  // instead (matches what's observed both from a reference app and from
  // AOSP's own PowerManagerService behavior).
  static const _shortTimeoutThresholdMs = 60000;
  static const _shortTimeoutDimRatio = 2 / 3;
  static const _longTimeoutDimLeadMs = 20000;
  static const _minDimDelayMs = 3000;
  static const _fallbackTimeoutMs = 30000;
  static const _dimBrightness = 0.08;

  static bool _active = false;
  static bool _dimmed = false;
  static Timer? _dimTimer;
  static int _timeoutMs = _fallbackTimeoutMs;
  static _LifecycleWatcher? _lifecycleWatcher;

  static Future<void> start() async {
    if (_active) return;
    _active = true;
    _lifecycleWatcher = _LifecycleWatcher()..attach();
    await WakelockPlus.enable();
    _timeoutMs = await _readScreenOffTimeoutMs();
    _scheduleDim();
  }

  static Future<void> stop() async {
    if (!_active) return;
    _active = false;
    _lifecycleWatcher?.detach();
    _lifecycleWatcher = null;
    _dimTimer?.cancel();
    _dimTimer = null;
    await _restoreBrightness();
    await WakelockPlus.disable();
  }

  // Called on every user pointer interaction anywhere in the app; a cheap
  // no-op when the service isn't active (e.g. on the connect screen).
  static void registerInteraction() {
    if (!_active) return;
    if (_dimmed) _restoreBrightness();
    _scheduleDim();
  }

  static void _scheduleDim() {
    _dimTimer?.cancel();
    final rawDelayMs = _timeoutMs < _shortTimeoutThresholdMs
        ? (_timeoutMs * _shortTimeoutDimRatio).round()
        : _timeoutMs - _longTimeoutDimLeadMs;
    final delayMs = rawDelayMs.clamp(_minDimDelayMs, _timeoutMs);
    _dimTimer = Timer(Duration(milliseconds: delayMs), _dim);
  }

  static Future<void> _dim() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(_dimBrightness);
      _dimmed = true;
    } catch (_) {
      // Best-effort: worst case the screen just stays at full brightness.
    }
  }

  static Future<void> _restoreBrightness() async {
    _dimmed = false;
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }

  static Future<int> _readScreenOffTimeoutMs() async {
    if (!Platform.isAndroid) return _fallbackTimeoutMs;
    try {
      final ms = await _displayChannel.invokeMethod<int>(
        'getScreenOffTimeout',
      );
      return ms ?? _fallbackTimeoutMs;
    } catch (_) {
      return _fallbackTimeoutMs;
    }
  }
}

// On resume, treat it like an interaction: restore brightness and restart
// the inactivity timer. Without this, a dim triggered while backgrounded
// (the timer keeps running even though the screen was already off) would
// leave the mixer dim the instant the user unlocks the phone and looks at it.
class _LifecycleWatcher extends WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenAwakeService.registerInteraction();
    }
  }
}
