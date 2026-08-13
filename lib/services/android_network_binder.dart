import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Binds the process to the wifi network so OSC/UDP traffic to the console
// keeps going out over wifi even if Android moves the system default
// network to mobile data (e.g. wifi has no internet route). No-op on any
// platform other than Android.
class AndroidNetworkBinder {
  static const _channel = MethodChannel('com.vianubium.stagemon/network');
  static bool _handlerSet = false;

  // True unless the native side just reported the bound wifi network was
  // lost (onLost) and hasn't come back yet (onAvailable). Starts optimistic
  // so no banner flashes before the first bind resolves.
  static final ValueNotifier<bool> wifiAvailable = ValueNotifier(true);

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      debugPrint('AndroidNetworkBinder: received ${call.method} from native');
      switch (call.method) {
        case 'networkLost':
          wifiAvailable.value = false;
          break;
        case 'networkAvailable':
          wifiAvailable.value = true;
          break;
      }
    });
  }

  static Future<void> bindToWifi() async {
    if (!Platform.isAndroid) return;
    _ensureHandler();
    debugPrint('AndroidNetworkBinder: invoking bindWifi');
    try {
      await _channel.invokeMethod('bindWifi');
    } catch (e) {
      // Best-effort: if this fails the app just falls back to the
      // system's default routing, same as before this feature existed.
      debugPrint('AndroidNetworkBinder: bindWifi failed: $e');
    }
  }

  static Future<void> unbind() async {
    if (!Platform.isAndroid) return;
    wifiAvailable.value = true;
    debugPrint('AndroidNetworkBinder: invoking unbind');
    try {
      await _channel.invokeMethod('unbind');
    } catch (e) {
      debugPrint('AndroidNetworkBinder: unbind failed: $e');
    }
  }
}
