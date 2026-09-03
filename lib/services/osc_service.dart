import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:osc/osc.dart';
import 'android_network_binder.dart';
import 'osc_diagnostics.dart';

class ConsoleInfo {
  final String ip;
  final String name;
  final String model;

  const ConsoleInfo({
    required this.ip,
    required this.name,
    required this.model,
  });
}

class OscService {
  String ip;
  final int port;

  RawDatagramSocket? _socket;
  Timer? _xremoteTimer;
  Timer? _heartbeatTimer;
  final Map<String, List<void Function(dynamic)>> _listeners = {};

  // Outbound state requests are paced instead of fired in one burst.
  // MixerController alone asks for ~96 addresses in a single event-loop turn
  // (names, colors, bus links, every fader/pan of the active bus), and then
  // each fader/knob widget re-asks for its own address on init. The XR18's
  // OSC engine drops most of a burst that size — especially over the
  // console's own wifi AP — which is what left channel names and colors
  // blank. Spacing the requests also spaces out the *replies*, so this
  // socket's receive buffer stops overflowing on the way back in.
  // 15ms ≈ 67 msg/s. Measured against a real XR18 over its internal AP with
  // StageMon as the only client: 0ms loses ~50% of replies, ~10ms drops a few
  // now and then, 12ms is clean. The cliff sits right around 100 msg/s, so
  // this keeps a margin under it rather than sitting 2ms above the edge —
  // one console, one firmware, one RF environment is thin evidence to run
  // flush against. Costs ~0.3s on a full sweep.
  static const Duration _requestInterval = Duration(milliseconds: 15);

  // Two lanes, one pace. Writes drain before reads so a fader move never waits
  // behind a sweep — worst case it goes out on the next tick (≤15ms), against
  // a drag that is already throttled to 50ms at the widget. Reads fill the
  // remaining ticks.
  //
  // The lanes differ in how a repeat is handled, and the difference matters:
  // a queued read is *dropped* (asking twice is redundant), while a queued
  // write is *coalesced* — the newer value replaces the pending one, keeping
  // its place in line. Dropping it the way reads are dropped would strand a
  // dragged fader at a stale position, which is worse than the bug this whole
  // mechanism exists to fix.
  final Queue<String> _setQueue = Queue();
  final Map<String, dynamic> _pendingSetValues = {};
  final Queue<String> _requestQueue = Queue();
  final Set<String> _queuedRequests = {};
  Timer? _requestDrainTimer;

  // Retry policy. With the pacing above and no other client, every address
  // answers and these rounds never fire. What does cause loss is another app
  // (Mixing Station, say) running its own full state sync, which saturates
  // the console for several seconds. That is one correlated event, not N
  // independent drops — so whole rounds are retried together, with a backoff
  // long enough to outlast the window, instead of per-address timers that
  // would keep hammering a console that is still busy.
  static const List<Duration> _retryBackoff = [
    Duration(milliseconds: 1500),
    Duration(seconds: 4),
    Duration(seconds: 10),
  ];
  // When the last request of a round leaves the queue its reply is still in
  // flight; evaluating right away would count it as lost.
  static const Duration _replyGrace = Duration(seconds: 1);
  // Past the fast rounds the retries slow down instead of stopping. Giving up
  // stranded the one case that actually reaches here: a console busy with
  // another client keeps pushing meters, so the heartbeat never drops and
  // MixerController's reconnect refresh never fires — nothing would ever
  // re-read those addresses and a fader could sit at 0 indefinitely.
  static const Duration _sustainedRetryInterval = Duration(seconds: 15);

  // Every address written to or read from goes in here and comes out when any
  // message arrives at it. What is still waiting gets *re-read*, never
  // re-written: a GET cannot clobber anything, so there is no need to tell
  // "my packet was dropped" from "someone else overwrote me". Either way the
  // app converges on the console's actual value, which is the only thing it
  // should be showing. A lost fader write used to leave the app displaying a
  // position the console never took; now the fader snaps back and the user
  // sees the move did not land.
  final Set<String> _awaitingReply = {};
  int _retryRound = 0;
  // Kept apart so a write during a backoff wait cannot cancel the pending
  // round and burn through the retry budget early.
  Timer? _roundCheckTimer;
  Timer? _backoffTimer;

  /// Addresses still unanswered after every retry round — the hook for the
  /// "console busy, some settings could not be read" warning. Empty while
  /// recovery is still in progress, so a listener only ever sees a settled
  /// result. Deliberately kept here rather than read back out of
  /// OscDiagnostics: that is instrumentation, it can be removed, and its
  /// tallies are cleared by the diagnostics screen's replay button.
  final ValueNotifier<List<String>> unansweredAddresses = ValueNotifier(
    const [],
  );

  final ValueNotifier<List<double>> channelLevels = ValueNotifier(
    List.filled(16, 0.0),
  );
  final ValueNotifier<List<double>> busLevels = ValueNotifier(
    List.filled(6, 0.0),
  );
  final ValueNotifier<List<double>> lineInLevels = ValueNotifier([0.0, 0.0]);
  final ValueNotifier<List<double>> fxReturnLevels = ValueNotifier(
    List.filled(8, 0.0),
  );
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

  static ConsoleInfo _parseXinfo(String ip, List<dynamic> args) {
    final name = args.length > 1 ? args[1].toString() : ip;
    final model = args.length > 2 ? args[2].toString() : 'Unknown';
    return ConsoleInfo(ip: ip, name: name, model: model);
  }

  /// Broadcasts /xinfo [probeCount] times, one every [probeInterval], and
  /// emits each console the first time it answers. The stream closes one
  /// interval after the last probe, so the default 3 probes span a 6s window.
  ///
  /// A single broadcast is not reliable: a console busy answering another
  /// client drops it, and the user was left pressing "search" again until one
  /// probe happened to land. Repeating the probe costs nothing when the first
  /// one works — a console already emitted is not emitted twice.
  ///
  /// Emitting per console rather than returning a list at the end is what
  /// lets the connect screen show a card as soon as the console answers,
  /// instead of holding everything back for the whole window.
  static Stream<ConsoleInfo> discoverConsoles({
    Duration probeInterval = const Duration(seconds: 2),
    int probeCount = 3,
  }) {
    final controller = StreamController<ConsoleInfo>();
    RawDatagramSocket? socket;
    Timer? probeTimer;
    final seen = <String>{};

    void stop() {
      probeTimer?.cancel();
      probeTimer = null;
      socket?.close();
      socket = null;
    }

    controller.onCancel = stop;

    Future<void> run() async {
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
        return;
      }
      // The listener may have cancelled while the bind was in flight.
      if (controller.isClosed) {
        stop();
        return;
      }
      socket!.broadcastEnabled = true;
      socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        try {
          final reply = OSCMessage.fromBytes(dg.data);
          if (reply.address != '/xinfo') return;
          final ip = dg.address.address;
          if (!seen.add(ip)) return;
          if (!controller.isClosed) {
            controller.add(_parseXinfo(ip, reply.arguments));
          }
        } catch (_) {}
      });

      var probesLeft = probeCount;
      void probe() {
        probesLeft--;
        try {
          final msg = OSCMessage('/xinfo', arguments: []);
          socket!.send(
            msg.toBytes(),
            InternetAddress('255.255.255.255'),
            10024,
          );
        } catch (_) {}
      }

      probe();
      probeTimer = Timer.periodic(probeInterval, (_) {
        // The tick after the last probe is the grace window for its replies.
        if (probesLeft <= 0) {
          stop();
          controller.close();
          return;
        }
        probe();
      });
    }

    unawaited(run());
    return controller.stream;
  }

  static Future<ConsoleInfo?> queryConsole(
    String ip, {
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

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    socket.close();
    return result;
  }

  Future<void> init() async {
    // Whatever is still queued was aimed at the socket about to be replaced.
    _clearRequestQueue();
    _clearRetryState();
    OscDiagnostics.instance.reset();
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
    OscDiagnostics.instance.replayHandler = _replayRequests;
  }

  // Re-queues every address this connection has already asked for, so the
  // diagnostics screen can run a second sweep under the same conditions and
  // watch the loss happen. Goes through request() rather than touching the
  // queue directly, keeping the single insertion point that keeps
  // _requestQueue and _queuedRequests in agreement.
  int _replayRequests() {
    final addresses = OscDiagnostics.instance.beginReplay();
    for (final address in addresses) {
      request(address);
    }
    return addresses.length;
  }

  void _onReceive(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket!.receive();
    if (dg == null) return;
    try {
      final msg = OSCMessage.fromBytes(dg.data);
      if (msg.address == '/meters/1') {
        OscDiagnostics.instance.recordMeterPacket();
        _parseMeterBlob(msg);
        return;
      }
      // Recorded before the listener lookup: an address answering at all is
      // what the diagnostics care about, even with nothing subscribed to it.
      OscDiagnostics.instance.recordReply(msg.address);
      // Any message at this address counts, including an /xremote push that
      // beat our own reply back — the value is what we were waiting for.
      _awaitingReply.remove(msg.address);
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
        ? ((data.getInt16(4 + i * 2, Endian.little) - noiseFloor) /
                  (-noiseFloor).toDouble())
              .clamp(0.0, 1.0)
        : 0.0;

    channelLevels.value = List.generate(16, int16);
    busLevels.value = List.generate(6, (i) => int16(26 + i));
    lineInLevels.value = [int16(16), int16(17)];
    fxReturnLevels.value = List.generate(8, (i) => int16(18 + i));
    _resetHeartbeat();
  }

  void _resetHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!isReceiving.value) {
      isReceiving.value = true;
      // The link just came back; anything still missing deserves the fast
      // rounds again rather than resuming on the slow tier.
      _retryRound = 0;
    }
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

  /// Writes a value to the console. Queued on the priority lane rather than
  /// sent inline: the console answers every write with the new value, and that
  /// echo is what confirms the write landed, so writes need the same pacing
  /// and the same tracking as reads. A snapshot recall fires ~40 of these at
  /// once — exactly the burst shape that was losing half its packets.
  void send(String address, dynamic value) {
    if (!_pendingSetValues.containsKey(address)) _setQueue.add(address);
    _pendingSetValues[address] = value;
    _recordQueueDepth();
    _requestDrainTimer ??= Timer.periodic(_requestInterval, _drainRequests);
  }

  // Queues a read of an address. An argument-less message is the X AIR
  // convention for "send me this value"; the reply comes back to the same
  // address and is dispatched through [_listeners] like any push update, so
  // callers register their listener before requesting.
  //
  // An address already queued collapses into the one entry — the fader and
  // knob widgets re-request addresses MixerController just asked for, so
  // dedupe alone removes a good chunk of the startup traffic.
  void request(String address) {
    if (!_queuedRequests.add(address)) return;
    _requestQueue.add(address);
    _recordQueueDepth();
    _requestDrainTimer ??= Timer.periodic(_requestInterval, _drainRequests);
  }

  void _recordQueueDepth() => OscDiagnostics.instance.recordQueueDepth(
    _setQueue.length + _requestQueue.length,
  );

  void _drainRequests(Timer timer) {
    if (_setQueue.isEmpty && _requestQueue.isEmpty) {
      timer.cancel();
      _requestDrainTimer = null;
      // Everything is on the wire; give the replies time to land.
      _scheduleRoundCheck(_replyGrace);
      return;
    }
    if (_setQueue.isNotEmpty) {
      final address = _setQueue.removeFirst();
      final value = _pendingSetValues.remove(address);
      _recordQueueDepth();
      // The lane and the value map are only ever written together, so null
      // here means a bug rather than a legitimately absent value.
      if (value != null) _transmit(address, <Object>[value]);
    } else {
      final address = _requestQueue.removeFirst();
      _queuedRequests.remove(address);
      _recordQueueDepth();
      _transmit(address, const <Object>[]);
    }
  }

  // The one place anything leaves for the console, so reads and writes are
  // tracked identically — both expect a message back at the same address.
  void _transmit(String address, List<Object> arguments) {
    if (_socket == null) return;
    try {
      final message = OSCMessage(address, arguments: arguments);
      _socket!.send(message.toBytes(), InternetAddress(ip.trim()), port);
      _awaitingReply.add(address);
      OscDiagnostics.instance.recordSent(address);
      if (arguments.isNotEmpty) {
        debugPrint("Sent to $address: ${arguments.first}");
      }
    } catch (_) {}
  }

  void _scheduleRoundCheck(Duration delay) {
    // A round is already booked; leave it alone. Without this, a fader move
    // during a backoff wait would replace the pending round with a 1s check
    // and advance the retry index early, spending the budget on a console
    // that has not had its wait yet.
    if (_backoffTimer != null) return;
    _roundCheckTimer?.cancel();
    _roundCheckTimer = Timer(delay, _evaluateRound);
  }

  void _evaluateRound() {
    _roundCheckTimer = null;
    // Something queued more traffic during the grace window (a bus switch, a
    // fader move, a widget rebuild). Let it drain before judging what is
    // missing — its replies have not had their chance yet.
    if (_setQueue.isNotEmpty || _requestQueue.isNotEmpty) {
      _scheduleRoundCheck(_replyGrace);
      return;
    }
    if (_awaitingReply.isEmpty) {
      _retryRound = 0;
      if (unansweredAddresses.value.isNotEmpty) {
        unansweredAddresses.value = const [];
      }
      return;
    }
    if (_retryRound >= _retryBackoff.length) {
      // The fast rounds are spent. Publish what is missing and drop to the
      // slow tier rather than stopping — _retryRound stays at the ceiling, so
      // every later evaluation lands back here.
      unansweredAddresses.value = List.unmodifiable(
        _awaitingReply.toList()..sort(),
      );
      // Gated on meters still arriving, which is a stronger signal than it
      // looks: the meter feed is a subscription this app renews every 9s and
      // the console drops after ~10s, so a blob landing now proves our packets
      // are reaching it and being acted on. Silence means the link is down,
      // more reads would be shouting into a void, and _refreshAll() re-reads
      // everything once the heartbeat recovers. Leaving _awaitingReply
      // populated is deliberate: it is what the next evaluation retries.
      if (isReceiving.value) {
        _backoffTimer = Timer(_sustainedRetryInterval, _retryMissingAddresses);
      }
      return;
    }
    final delay = _retryBackoff[_retryRound];
    _retryRound++;
    _backoffTimer = Timer(delay, _retryMissingAddresses);
  }

  void _retryMissingAddresses() {
    _backoffTimer = null;
    OscDiagnostics.instance.recordRetryRound();
    // Always re-read, never re-write — even for addresses that got here from
    // send(). Re-writing would risk overwriting a value another client set in
    // the meantime; re-reading just asks what it is now. Goes through
    // request() so the queue keeps its single insertion point, and draining
    // schedules the next round check on its own.
    for (final address in _awaitingReply.toList()) {
      request(address);
    }
  }

  void _clearRetryState() {
    _roundCheckTimer?.cancel();
    _roundCheckTimer = null;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _awaitingReply.clear();
    _retryRound = 0;
    unansweredAddresses.value = const [];
  }

  void _clearRequestQueue() {
    _requestDrainTimer?.cancel();
    _requestDrainTimer = null;
    _requestQueue.clear();
    _queuedRequests.clear();
    _setQueue.clear();
    _pendingSetValues.clear();
  }

  void dispose() {
    if (OscDiagnostics.instance.replayHandler == _replayRequests) {
      OscDiagnostics.instance.replayHandler = null;
    }
    _clearRequestQueue();
    _clearRetryState();
    _xremoteTimer?.cancel();
    _xremoteTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.close();
    _socket = null;
    AndroidNetworkBinder.wifiAvailable.removeListener(
      _onWifiAvailabilityChanged,
    );
    unawaited(AndroidNetworkBinder.unbind());
    unansweredAddresses.dispose();
    channelLevels.dispose();
    busLevels.dispose();
    isReceiving.dispose();
  }
}
