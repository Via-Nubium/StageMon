import 'package:flutter/services.dart';

/// Bridges the `.stagemonlayout` file received via Android's "Open with"
/// (see MainActivity.kt's ACTION_VIEW handling) into Dart.
///
/// Pull-based: [takePending] asks the native side for whatever it's holding
/// (and clears it there), rather than relying solely on the push
/// notification arriving while something happens to be listening.
class LayoutImportService {
  static const _channel = MethodChannel('com.vianubium.stagemon/layout_import');

  /// Calls [onAvailable] when a new file arrives while the app is already
  /// running. Does not itself carry the content — call [takePending] to
  /// fetch it.
  static void listen(void Function() onAvailable) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'layoutImportAvailable') onAvailable();
    });
  }

  /// Returns the pending file's raw content, or null if there isn't one.
  /// Consumes it — a second call returns null until another file arrives.
  static Future<String?> takePending() {
    return _channel.invokeMethod<String>('getPendingLayoutImport');
  }
}
