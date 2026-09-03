import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
import '../services/xr18_simulator.dart';
import 'mixer_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _isSearching = true;
  final List<ConsoleInfo> _consoles = [];
  StreamSubscription<ConsoleInfo>? _discoverySub;
  final TextEditingController _ipController = TextEditingController();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _discover();
    _loadLastIp();
  }

  void _loadLastIp() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('last_ip') ?? '';
    if (mounted && ip.isNotEmpty) setState(() => _ipController.text = ip);
  }

  @override
  void dispose() {
    _stopDiscovery();
    _ipController.dispose();
    super.dispose();
  }

  void _stopDiscovery() {
    _discoverySub?.cancel();
    _discoverySub = null;
  }

  // Each console gets its card as soon as it answers, rather than at the end
  // of the search window: with the probe repeating for 6s, waiting for the
  // stream to close would keep a console that answered instantly hidden for
  // most of that time.
  void _discover() {
    _stopDiscovery();
    setState(() {
      _isSearching = true;
      _consoles.clear();
    });
    _discoverySub = OscService.discoverConsoles().listen(
      (console) {
        if (!mounted) return;
        setState(() => _consoles.add(console));
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isSearching = false);
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isSearching = false);
      },
      cancelOnError: true,
    );
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static const _testedModels = {
    'XR18',
    'X18',
    'MR18',
    'XR18V2',
    'X18V2',
    'MR18V2',
  };

  void _connectManual() async {
    final l = AppLocalizations.of(context)!;
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    if (!_isValidIp(ip)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.invalidIp)));
      return;
    }

    setState(() => _isConnecting = true);
    ConsoleInfo? info;
    try {
      info = await OscService.queryConsole(ip);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (info != null) {
      await _connectToConsole(info);
      return;
    }

    if (info == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.noConsoleAtIpTitle),
          content: Text(l.noConsoleAtIpBody(ip)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.tryAnyway),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    _connect(ip);
  }

  Future<void> _connectToConsole(ConsoleInfo console) async {
    if (!_testedModels.contains(console.model)) {
      final l = AppLocalizations.of(context)!;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.untestedModelTitle),
          content: Text(l.untestedModelBody(console.model)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.connectAnyway),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    _connect(console.ip, null, console.model);
  }

  void _connect([
    String? overrideIp,
    XR18Simulator? simulator,
    String? model,
  ]) async {
    final l = AppLocalizations.of(context)!;
    _stopDiscovery();
    final ip = (overrideIp ?? _ipController.text).trim();
    if (ip.isEmpty) return;
    if (simulator == null && !_isValidIp(ip)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.invalidIp)));
      return;
    }
    final service = simulator == null
        ? OscService(ip: ip)
        : OscService(ip: ip, port: simulator.port);
    try {
      await service.init();
    } catch (e) {
      simulator?.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.socketError(e.toString()))));
      return;
    }
    if (!mounted) return;
    if (simulator == null) {
      SharedPreferences.getInstance().then((p) => p.setString('last_ip', ip));
    }
    // Recorded into saved layouts so future console models that might
    // conflict with today's addressing can be told apart later.
    final consoleModel = simulator != null ? 'XR18Sim' : (model ?? 'Unknown');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MixerScreen(
          service: service,
          simulator: simulator,
          consoleModel: consoleModel,
        ),
      ),
    );
    // Back from MixerScreen (disconnect) — the previous discovery results are stale
    // (the console we were connected to may no longer be reachable), so search again.
    if (mounted) _discover();
  }

  void _connectSimulator() async {
    setState(() => _isConnecting = true);
    final simulator = XR18Simulator();
    try {
      await simulator.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.socketError(e.toString()))));
      return;
    }
    if (!mounted) return;
    setState(() => _isConnecting = false);
    _connect('127.0.0.1', simulator);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/icon/icon.png', width: 96, height: 96),
              const SizedBox(height: 12),
              const Text(
                "StageMon",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              _buildDiscoverySection(l),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isSearching ? null : _discover,
                icon: const Icon(Icons.search),
                label: Text(l.search),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 80),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l.orEnterIpManually,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l.mixerIpLabel,
                  hintText: l.mixerIpHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isSearching || _isConnecting
                    ? null
                    : _connectManual,
                icon: const Icon(Icons.power_settings_new),
                label: Text(l.connect),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoverySection(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDiscoveryHeader(l),
        // Consoles stack above the simulator, which is always offered.
        ..._consoles.map(
          (c) => _ConsoleCard(console: c, onTap: () => _connectToConsole(c)),
        ),
        _SimulatorCard(onTap: _isConnecting ? null : _connectSimulator),
      ],
    );
  }

  Widget _buildDiscoveryHeader(AppLocalizations l) {
    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l.searching),
          ],
        ),
      );
    }

    if (_consoles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Text(l.noMixerFound, style: const TextStyle(color: Colors.orange)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(l.mixersFound, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _SimulatorCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _SimulatorCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text(
          l.simulatorMode,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          l.simulatorModeSubtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ConsoleCard extends StatelessWidget {
  final ConsoleInfo console;
  final VoidCallback onTap;

  const _ConsoleCard({required this.console, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const RotatedBox(quarterTurns: 1, child: Icon(Icons.tune)),
        title: Text(
          console.model == 'Unknown'
              ? AppLocalizations.of(context)!.unknownModel
              : console.model,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${console.ip} · ${console.name}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
