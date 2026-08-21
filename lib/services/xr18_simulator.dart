import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:osc/osc.dart';

/// Embedded fake XR18 console for the "simulador mode" onboarding flow.
///
/// Listens on loopback (127.0.0.1) on an OS-assigned port — not the XR18's
/// well-known 10024 — and answers the exact subset of the XR18 OSC protocol
/// that [MixerController] reads/writes, so `OscService` can point at it
/// unmodified. State is fully hardcoded — no external control, no snapshots,
/// no dynamic renaming (that's `tools/xr18_simulator.py`'s job).
///
/// Using a random port instead of 10024 isn't a real security boundary
/// (loopback is shared by every app on the device), but it does close off
/// the trivial case of another app that knows the XR18's standard OSC port
/// connecting on purpose.
class XR18Simulator {
  static const int _meterNoiseFloor = -16384;

  static const _channelLevels = [
    0.65, 0.55, 0.60, 0.62, 0.58, 0.70, 0.68, 0.50,
    0.66, 0.45, 0.40, 0.35, 0.42, 0.20, 0.20, 0.0,
  ];

  // XR18 /config/color values: 0-7 base colors, 8-15 the same 8 inverted.
  static const _channelColorValue = 0; // OFF, all 16 channels
  static const _rtnColorValue = 2; // GN, all 4 FX returns
  static const _lineInColor = 3; // YE
  static const _busColorValue = 3; // YE, all 6 buses

  RawDatagramSocket? _socket;
  Timer? _meterTimer;
  DateTime? _startTime;
  final Map<String, dynamic> _state = {};
  InternetAddress? _meterSubAddr;
  int? _meterSubPort;

  /// Port the OS assigned once [start] completes.
  int get port => _socket!.port;

  Future<void> start() async {
    _startTime = DateTime.now();
    _seedDefaults();
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket!.listen(_onReceive);
    _meterTimer = Timer.periodic(const Duration(milliseconds: 100), _pushMeters);
  }

  void stop() {
    _meterTimer?.cancel();
    _meterTimer = null;
    _socket?.close();
    _socket = null;
  }

  // ── State ──────────────────────────────────────────────────────────────

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _chLevel(int ch, int bus) => '/ch/${_pad2(ch)}/mix/${_pad2(bus)}/level';
  static String _chPan(int ch, int bus) => '/ch/${_pad2(ch)}/mix/${_pad2(bus)}/pan';
  static String _rtnLevel(int rtn, int bus) => '/rtn/$rtn/mix/${_pad2(bus)}/level';
  static String _rtnPan(int rtn, int bus) => '/rtn/$rtn/mix/${_pad2(bus)}/pan';
  static String _lineInLevel(int bus) => '/rtn/aux/mix/${_pad2(bus)}/level';
  static String _lineInPan(int bus) => '/rtn/aux/mix/${_pad2(bus)}/pan';
  static String _busFader(int bus) => '/bus/$bus/mix/fader';
  static String _busMute(int bus) => '/bus/$bus/mix/on';

  void _seedDefaults() {
    for (int ch = 1; ch <= 16; ch++) {
      for (int bus = 1; bus <= 6; bus++) {
        _state[_chLevel(ch, bus)] = _channelLevels[ch - 1];
        _state[_chPan(ch, bus)] = 0.5;
      }
      _state['/ch/${_pad2(ch)}/config/color'] = _channelColorValue;
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      for (int bus = 1; bus <= 6; bus++) {
        _state[_rtnLevel(rtn, bus)] = 0.3;
        _state[_rtnPan(rtn, bus)] = 0.5;
      }
      _state['/rtn/$rtn/config/color'] = _rtnColorValue;
    }
    _state['/rtn/aux/config/color'] = _lineInColor;
    for (int bus = 1; bus <= 6; bus++) {
      _state[_lineInLevel(bus)] = 0.3;
      _state[_lineInPan(bus)] = 0.5;
      _state[_busFader(bus)] = 0.75;
      _state[_busMute(bus)] = 1;
      _state['/bus/$bus/config/color'] = _busColorValue;
    }
    // Bus 1-2 stereo-paired by default so the demo shows pan knobs / stereo behavior.
    _state['/config/buslink/1-2'] = 1;
    _state['/config/buslink/3-4'] = 0;
    _state['/config/buslink/5-6'] = 0;
  }

  // ── Protocol ───────────────────────────────────────────────────────────

  void _onReceive(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final msg = OSCMessage.fromBytes(dg.data);
      _handle(msg, dg.address, dg.port);
    } catch (_) {}
  }

  void _handle(OSCMessage msg, InternetAddress addr, int port) {
    final address = msg.address;

    if (address == '/meters' && msg.arguments.isNotEmpty && msg.arguments.first == '/meters/1') {
      _meterSubAddr = addr;
      _meterSubPort = port;
      return;
    }

    if (msg.arguments.isEmpty) {
      // GET — reply with current value if known, silently ignore otherwise
      // (matches how the app already tolerates addresses a real console won't answer, e.g. /xremote).
      final value = _state[address];
      if (value != null) _reply(address, value, addr, port);
      return;
    }

    // SET — store and echo back to the sender. The real console pushes changes to
    // /xremote subscribers; since this simulator only ever has one client (this app
    // instance, on the same socket that sent the SET), echoing directly is equivalent.
    final value = msg.arguments.first;
    _state[address] = value;
    _reply(address, value, addr, port);
  }

  void _reply(String address, dynamic value, InternetAddress addr, int port) {
    try {
      final msg = OSCMessage(address, arguments: [value]);
      _socket?.send(msg.toBytes(), addr, port);
    } catch (_) {}
  }

  // ── Meters ─────────────────────────────────────────────────────────────

  void _pushMeters(Timer timer) {
    final addr = _meterSubAddr;
    final port = _meterSubPort;
    if (addr == null || port == null || _socket == null || _startTime == null) return;
    final t = DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
    final blob = _buildMeterBlob(_generateMeterValues(t));
    try {
      final msg = OSCMessage('/meters/1', arguments: [blob]);
      _socket!.send(msg.toBytes(), addr, port);
    } catch (_) {}
  }

  static int _signalToInt16(double level) =>
      (level * -_meterNoiseFloor).toInt() + _meterNoiseFloor;

  static Uint8List _buildMeterBlob(List<int> values) {
    final data = ByteData(4 + values.length * 2);
    data.setInt32(0, values.length, Endian.little);
    for (int i = 0; i < values.length; i++) {
      data.setInt16(4 + i * 2, values[i].clamp(-32768, 0), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  // 40 int16 values matching the X AIR /meters/1 layout (all indices 0-based).
  //   [0-15]  channels 1-16 | [16-17] RTN/AUX L/R | [18-25] FX returns 1-4 L/R
  //   [26-31] bus outputs   | [32-39] fx send/st/monitor
  List<int> _generateMeterValues(double t) {
    final vals = List<int>.filled(40, _signalToInt16(0.0));

    const activity = [
      0.88, 0.82, 0.55, 0.72, 0.91, 0.60, 0.78, 0.45,
      0.86, 0.80, 0.28, 0.65, 0.70, 0.38, 0.58, 0.76,
    ];
    for (int i = 0; i < 16; i++) {
      final base = activity[i];
      final envelope = base * (0.85 + 0.15 * sin(t * (0.35 + i * 0.04) + i * 0.7));
      final signal = envelope * (0.55 + 0.45 * sin(t * (2.3 + i * 0.11) + i * 1.4).abs());
      final sPeak = sin(t * 8.1 + i * 2.3);
      final peak = 0.12 * pow(sPeak > 0 ? sPeak : 0.0, 10);
      vals[i] = _signalToInt16(min(signal + peak, 1.0));
    }

    for (int side = 0; side < 2; side++) {
      final phase = side == 0 ? 0.0 : 0.6;
      const base = 0.72;
      final envelope = base * (0.80 + 0.20 * sin(t * 0.31 + phase));
      final signal = envelope * (0.55 + 0.45 * sin(t * 2.1 + phase).abs());
      final sPeak = sin(t * 7.4 + phase);
      final peak = 0.10 * pow(sPeak > 0 ? sPeak : 0.0, 8);
      vals[16 + side] = _signalToInt16(min(signal + peak, 1.0));
    }

    const fxActivity = [0.55, 0.40, 0.30, 0.20];
    for (int fx = 0; fx < 4; fx++) {
      for (int side = 0; side < 2; side++) {
        final phase = side == 0 ? 0.0 : 0.5;
        final base = fxActivity[fx];
        final envelope = base * (0.80 + 0.20 * sin(t * (0.25 + fx * 0.08) + phase));
        final signal = envelope * (0.55 + 0.45 * sin(t * (1.8 + fx * 0.12) + phase).abs());
        vals[18 + fx * 2 + side] = _signalToInt16(min(signal, 1.0));
      }
    }

    for (int i = 0; i < 6; i++) {
      final fader = (_state[_busFader(i + 1)] as double?) ?? 0.75;
      final baseLvl = 0.82 * fader;
      final envelope = baseLvl * (0.80 + 0.20 * sin(t * (0.28 + i * 0.07) + i * 0.9));
      final signal = envelope * (0.60 + 0.40 * sin(t * (1.9 + i * 0.09) + i * 1.1).abs());
      final sPeak = sin(t * 6.3 + i * 1.8);
      final peak = 0.10 * pow(sPeak > 0 ? sPeak : 0.0, 8);
      vals[26 + i] = _signalToInt16(min(signal + peak, 1.0));
    }

    for (int i = 0; i < 8; i++) {
      vals[32 + i] = _signalToInt16(0.02 * sin(t * 0.2 + i).abs());
    }

    return vals;
  }
}
