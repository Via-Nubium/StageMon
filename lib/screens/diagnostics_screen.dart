import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/osc_diagnostics.dart';

/// Hidden connection diagnostics, reached from About by tapping the version
/// line seven times. Ships in release builds on purpose: the conditions we
/// expect to provoke the loss — the console acting as its own wifi AP, a
/// crowded 2.4GHz band, distance — are a tester's at a venue, not a
/// developer's at a desk. Which of those actually matters is what this screen
/// is here to find out; nothing has been measured yet.
///
/// Left untranslated: the screen is hidden, its subject matter is raw OSC
/// addresses, and its audience is whoever is being asked to read numbers off
/// a phone during a debugging session.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Polled rather than listened to: meter blobs land 10-20×/s and notifying
    // per packet would be pure overhead. Twice a second is fast enough to
    // watch a sweep fill in — the paced drain takes ~1.2s for a full set.
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: OscDiagnostics.instance.report()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }

  void _replay() {
    final handler = OscDiagnostics.instance.replayHandler;
    if (handler == null) return;
    final count = handler();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Re-sending $count addresses'),
      ),
    );
  }

  Color _lossColor(double ratio) {
    if (ratio <= 0.02) return Colors.greenAccent;
    if (ratio <= 0.10) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _ago(DateTime? then) {
    if (then == null) return 'never';
    final s = DateTime.now().difference(then).inSeconds;
    if (s < 1) return 'just now';
    if (s < 60) return '${s}s ago';
    return '${s ~/ 60}m ${s % 60}s ago';
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: valueColor == null ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = OscDiagnostics.instance;
    final missing = d.missing;
    final lossPct = (d.lossRatio * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy report',
            onPressed: _copy,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: d.canReplay ? _replay : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-send all requests'),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Clears the tallies and re-sends every address this connection '
              'has asked for, so each sweep is measured on its own.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
          const Divider(height: 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'READS & WRITES',
              style: TextStyle(fontSize: 12, color: Colors.white38, letterSpacing: 1),
            ),
          ),
          _row('Sent', '${d.requestCount}'),
          _row('Answered', '${d.answeredCount}'),
          _row(
            'Unanswered',
            '${missing.length}  ($lossPct%)',
            valueColor: _lossColor(d.lossRatio),
          ),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'LINK',
              style: TextStyle(fontSize: 12, color: Colors.white38, letterSpacing: 1),
            ),
          ),
          _row('Meter packets', '${d.meterPackets}'),
          _row(
            'Retry rounds',
            '${d.retryRounds}',
            valueColor: d.retryRounds > 0 ? Colors.orangeAccent : null,
          ),
          _row('Last reply', _ago(d.lastReplyAt)),
          _row('Run started', _ago(d.runStartedAt)),
          _row('Connected', _ago(d.connectedAt)),
          _row('Queue depth / peak', '${d.queueDepth} / ${d.peakQueueDepth}'),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              missing.isEmpty
                  ? 'NO UNANSWERED ADDRESSES'
                  : 'UNANSWERED ADDRESSES (${missing.length})',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white38,
                letterSpacing: 1,
              ),
            ),
          ),
          if (missing.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                'Every address the app asked for came back.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            ...missing.map(
              (a) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                child: Text(
                  a,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
