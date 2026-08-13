import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:osc/osc.dart';
import 'android_network_binder.dart';

class ConsoleInfo {
  final String ip;
  final String name;
  final String model;

  const ConsoleInfo({required this.ip, required this.name, required this.model});
}

class OscService {
  String ip;
  final int port;

  RawDatagramSocket? _socket;
  Timer? _xremoteTimer;
  Timer? _heartbeatTimer;
  final Map<String, List<void Function(dynamic)>> _listeners = {};

  final ValueNotifier<List<double>> channelLevels = ValueNotifier(List.filled(16, 0.0));
  final ValueNotifier<List<double>> busLevels = ValueNotifier(List.filled(6, 0.0));
  final ValueNotifier<List<double>> lineInLevels = ValueNotifier([0.0, 0.0]);
  final ValueNotifier<List<double>> fxReturnLevels = ValueNotifier(List.filled(8, 0.0));
  final ValueNotifier<bool> isReceiving = ValueNotifier(false);

  // Tracks wifi recovery so the socket gets recreated *after* the process is
  // confirmed bound to the new network — a socket opened before that bind
  // resolves keeps following the old (possibly wrong) network.
  bool _wifiWasAvailable = true;

  OscService({required this.ip, this.port = 10024}) {
    AndroidNetworkBinder.wifiAvailable.addListener(_onWifiAvailabilityChanged);
  }

  void _onWifiAvailabilityChanged() {
    final nowAvailable = AndroidNetworkBinder.wifiAvailable.value;
    if (nowAvailable && !_wifiWasAvailable) {
      init();
    }
    _wifiWasAvailable = nowAvailable;
  }

  // Broadcasts /xinfo and collects all XR18/X18 responses until timeout.
  static ConsoleInfo _parseXinfo(String ip, List<dynamic> args) {
    final name = args.length > 1 ? args[1].toString() : ip;
    final model = args.length > 2 ? args[2].toString() : 'Unknown';
    return ConsoleInfo(ip: ip, name: name, model: model);
  }

  static Future<List<ConsoleInfo>> findAllConsoles({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final consoles = <ConsoleInfo>[];

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      try {
        final reply = OSCMessage.fromBytes(dg.data);
        if (reply.address == '/xinfo') {
          final ip = dg.address.address;
          if (consoles.any((c) => c.ip == ip)) return;
          consoles.add(_parseXinfo(ip, reply.arguments));
        }
      } catch (_) {}
    });

    try {
      final msg = OSCMessage('/xinfo', arguments: []);
      socket.send(msg.toBytes(), InternetAddress('255.255.255.255'), 10024);
    } catch (_) {}

    await Future.delayed(timeout);
    socket.close();
    return List.unmodifiable(consoles);
  }

  static Future<ConsoleInfo?> queryConsole(String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<ConsoleInfo?>();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      try {
        final reply = OSCMessage.fromBytes(dg.data);
        if (reply.address == '/xinfo' && !completer.isCompleted) {
          completer.complete(_parseXinfo(ip, reply.arguments));
        }
      } catch (_) {}
    });

    try {
      final msg = OSCMessage('/xinfo', arguments: []);
      socket.send(msg.toBytes(), InternetAddress(ip), 10024);
    } catch (_) {}

    final result = await completer.future
        .timeout(timeout, onTimeout: () => null);
    socket.close();
    return result;
  }

  Future<void> init() async {
    _xremoteTimer?.cancel();
    _xremoteTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    isReceiving.value = false;
    _socket?.close();
    _socket = null;
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onReceive);
    unawaited(AndroidNetworkBinder.bindToWifi());
    // Subscribe to push updates from the XR18. Must be renewed every <10s.
    _sendXremote();
    _xremoteTimer = Timer.periodic(
      const Duration(seconds: 9),
      (_) => _sendXremote(),
    );
  }

  void _onReceive(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket!.receive();
    if (dg == null) return;
    try {
      final msg = OSCMessage.fromBytes(dg.data);
      if (msg.address == '/meters/1') { _parseMeterBlob(msg); return; }
      final callbacks = _listeners[msg.address];
      if (callbacks != null && msg.arguments.isNotEmpty) {
        for (final cb in List.of(callbacks)) {
          cb(msg.arguments.first);
        }
      }
    } catch (_) {}
  }

  // /meters/1 layout (X AIR protocol): 40 × int16 values — all indices are 0-based.
  //   [0–15]  : channels 1–16 pre-fader levels
  //   [16–17] : RTN/AUX (Line In) L/R  ← positions 17–18 in 1-based docs
  //   [18–25] : FX returns 1–4 L/R
  //   [26–31] : 6 bus output levels (Bus1–Bus6)
  //   [32–39] : 4 fx send + 2 st (post) + 2 monitor
  void _parseMeterBlob(OSCMessage msg) {
    if (msg.arguments.isEmpty) return;
    final raw = msg.arguments.first;
    final Uint8List bytes;
    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is List) {
      bytes = Uint8List.fromList(raw.cast<int>());
    } else {
      return;
    }
    // Blob header: 4-byte LE int32 count, followed by count × 2-byte LE int16
    if (bytes.length < 4) return;
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    final count = data.getInt32(0, Endian.little);
    final available = min(count, (bytes.length - 4) ~/ 2);

    // XR18 meters: signed int16, -32768 = silence, 0 = 0 dBFS.
    // Remap [-24576, 0] → [0.0, 1.0]; below noise floor shows nothing.
    const noiseFloor = -16384;
    int16(int i) => i < available
        ? ((data.getInt16(4 + i * 2, Endian.little) - noiseFloor) / (-noiseFloor).toDouble()).clamp(0.0, 1.0)
        : 0.0;

    channelLevels.value = List.generate(16, int16);
    busLevels.value = List.generate(6, (i) => int16(26 + i));
    lineInLevels.value = [int16(16), int16(17)];
    fxReturnLevels.value = List.generate(8, (i) => int16(18 + i));
    _resetHeartbeat();
  }

  void _resetHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!isReceiving.value) isReceiving.value = true;
    _heartbeatTimer = Timer(const Duration(seconds: 15), () {
      isReceiving.value = false;
    });
  }

  void _sendXremote() {
    if (_socket == null) return;
    try {
      final msg = OSCMessage('/xremote', arguments: []);
      _socket!.send(msg.toBytes(), InternetAddress(ip.trim()), port);
    } catch (_) {}
    _subscribeMeter('/meters/1');
  }

  void _subscribeMeter(String bank) {
    if (_socket == null) return;
    try {
      final msg = OSCMessage('/meters', arguments: [bank]);
      _socket!.send(msg.toBytes(), InternetAddress(ip.trim()), port);
    } catch (_) {}
  }

  void addListener(String address, void Function(dynamic value) callback) {
    _listeners.putIfAbsent(address, () => []).add(callback);
  }

  void removeListener(String address, void Function(dynamic value) callback) {
    _listeners[address]?.remove(callback);
  }

  void send(String address, dynamic value) {
    if (_socket == null) return;
    try {
      final message = OSCMessage(address, arguments: [value]);
      _socket!.send(message.toBytes(), InternetAddress(ip.trim()), port);
      debugPrint("Sent to $address: $value");
    } catch (_) {}
  }

  // Requests the current value of an address from the console (no arguments).
  void request(String address) {
    if (_socket == null) return;
    try {
      final message = OSCMessage(address, arguments: []);
      _socket!.send(message.toBytes(), InternetAddress(ip.trim()), port);
    } catch (_) {}
  }

  void dispose() {
    _xremoteTimer?.cancel();
    _xremoteTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.close();
    _socket = null;
    AndroidNetworkBinder.wifiAvailable.removeListener(_onWifiAvailabilityChanged);
    unawaited(AndroidNetworkBinder.unbind());
    channelLevels.dispose();
    busLevels.dispose();
    isReceiving.dispose();
  }
}
