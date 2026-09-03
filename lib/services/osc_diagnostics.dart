/// Instrumentation for the OSC request path, used by the hidden diagnostics
/// screen (About → tap the version line seven times).
///
/// Deliberately a process-wide singleton instead of something threaded through
/// the widget tree: exactly one [OscService] is alive at a time, the screen is
/// reached from About — two screens that otherwise have no reason to know the
/// network layer exists — and this is cross-cutting observability, not app
/// state. Cheap enough to leave running in release builds (two set inserts per
/// message), which is the point: the loss it exists to measure is expected to
/// need real-venue conditions to show up, so debug-only instrumentation would
/// never see it.
///
/// Nothing here notifies listeners; the screen polls once a second. Meter
/// blobs arrive ~10-20×/s and would make change notifications pure overhead.
class OscDiagnostics {
  static final OscDiagnostics instance = OscDiagnostics._();
  OscDiagnostics._();

  final Set<String> _requested = {};
  final Set<String> _answered = {};
  int _meterPackets = 0;
  int _retryRounds = 0;
  int _queueDepth = 0;
  int _peakQueueDepth = 0;
  DateTime? _connectedAt;
  DateTime? _lastReplyAt;
  DateTime? _runStartedAt;

  /// Installed by OscService so the diagnostics screen can start a new sweep
  /// without holding a reference to the network layer — the screen is reached
  /// from About, which has no business knowing an OscService exists. Null
  /// whenever nothing is connected. Returns how many addresses were queued.
  int Function()? replayHandler;

  /// A sweep needs both something to send with and something to send: right
  /// after connecting, before the first sync has drained, there is nothing to
  /// replay yet.
  bool get canReplay => replayHandler != null && _requested.isNotEmpty;

  /// Addresses actually put on the wire by the paced drain — reads and writes
  /// alike, since both expect a message back. Not the ones merely handed to
  /// `request()`/`send()`, since repeats collapse before sending.
  int get requestCount => _requested.length;

  /// Requested addresses the console answered at least once. Derived from
  /// [missing] so the two can never disagree. Push updates for addresses that
  /// were never requested don't inflate it.
  int get answeredCount => requestCount - missing.length;

  /// The reason this tracks addresses instead of raw counters: it names what
  /// got lost. Seeing `/ch/07/config/name` here is actionable in a way that
  /// "12% loss" is not — it says the names dropped but the faders didn't.
  List<String> get missing =>
      _requested.difference(_answered).toList()..sort();

  int get meterPackets => _meterPackets;

  /// Retry rounds OscService has run this measurement run. Stays at 0 in
  /// normal single-client use; anything above 0 means replies went missing.
  int get retryRounds => _retryRounds;
  int get queueDepth => _queueDepth;
  int get peakQueueDepth => _peakQueueDepth;
  DateTime? get connectedAt => _connectedAt;
  DateTime? get lastReplyAt => _lastReplyAt;

  /// When the current measurement run began — the connection itself, or the
  /// last manual sweep.
  DateTime? get runStartedAt => _runStartedAt ?? _connectedAt;

  double get lossRatio =>
      requestCount == 0 ? 0.0 : missing.length / requestCount;

  void recordSent(String address) => _requested.add(address);

  void recordReply(String address) {
    _answered.add(address);
    _lastReplyAt = DateTime.now();
  }

  void recordRetryRound() => _retryRounds++;

  // Deliberately does not touch _lastReplyAt. Meter blobs land 10-20x/s, so
  // counting them as replies pinned that field to "just now" forever and hid
  // the one thing it exists to show: whether anything we *asked for* is
  // coming back. Meters have their own counter for liveness.
  void recordMeterPacket() => _meterPackets++;

  void recordQueueDepth(int depth) {
    _queueDepth = depth;
    if (depth > _peakQueueDepth) _peakQueueDepth = depth;
  }

  /// Starts a fresh measurement run over the addresses already known to this
  /// connection: hands them back for the caller to re-send, and clears the
  /// tallies so the new run's loss is measured on its own rather than being
  /// masked by the previous run's answers.
  ///
  /// [_requested] is cleared too and refills as the replayed requests actually
  /// reach the wire, which is what makes "Sent" climb live during the sweep.
  /// [_connectedAt] deliberately survives — it describes the socket, not the run.
  List<String> beginReplay() {
    final addresses = _requested.toList()..sort();
    _requested.clear();
    _answered.clear();
    _meterPackets = 0;
    _retryRounds = 0;
    _peakQueueDepth = 0;
    _runStartedAt = DateTime.now();
    return addresses;
  }

  /// Called from OscService.init(), so the numbers always describe the current
  /// connection rather than accumulating across reconnects and wifi recoveries.
  void reset() {
    _requested.clear();
    _answered.clear();
    _meterPackets = 0;
    _retryRounds = 0;
    _queueDepth = 0;
    _peakQueueDepth = 0;
    _connectedAt = DateTime.now();
    _lastReplyAt = null;
    _runStartedAt = null;
  }

  /// Plain-text report for the copy button — testers paste this into a chat.
  String report() {
    final buf = StringBuffer()
      ..writeln('StageMon OSC diagnostics')
      ..writeln('connected at: ${_connectedAt ?? "-"}')
      ..writeln('run started:  ${runStartedAt ?? "-"}')
      ..writeln('last reply:   ${_lastReplyAt ?? "never"}')
      ..writeln('addresses sent:    $requestCount')
      ..writeln('answered:          $answeredCount')
      ..writeln('missing:           ${missing.length} '
          '(${(lossRatio * 100).toStringAsFixed(1)}%)')
      ..writeln('meter packets:     $_meterPackets')
      ..writeln('retry rounds:      $_retryRounds')
      ..writeln('queue depth / peak: $_queueDepth / $_peakQueueDepth');
    if (missing.isNotEmpty) {
      buf.writeln('--- unanswered addresses ---');
      for (final a in missing) {
        buf.writeln(a);
      }
    }
    return buf.toString();
  }
}
