import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
import '../services/xr18_simulator.dart';
import 'mixer_screen.dart';

enum _DiscoveryStatus { searching, found, notFound }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  _DiscoveryStatus _status = _DiscoveryStatus.searching;
  List<ConsoleInfo> _consoles = [];
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
    _ipController.dispose();
    super.dispose();
  }

  void _discover() async {
    setState(() {
      _status = _DiscoveryStatus.searching;
      _consoles = [];
    });
    try {
      final consoles = await OscService.findAllConsoles().timeout(
        const Duration(seconds: 6),
        onTimeout: () => [],
      );
      if (!mounted) return;
      setState(() {
        _consoles = consoles;
        _status = consoles.isNotEmpty
            ? _DiscoveryStatus.found
            : _DiscoveryStatus.notFound;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _DiscoveryStatus.notFound);
    }
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static const _testedModels = {'XR18', 'X18'};

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
    final isSearching = _status == _DiscoveryStatus.searching;
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
              const SizedBox(height: 24),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSearching ? null : _discover,
                      icon: const Icon(Icons.search),
                      label: Text(l.search),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isSearching || _isConnecting
                          ? null
                          : _connectManual,
                      icon: const Icon(Icons.power_settings_new),
                      label: Text(l.connect),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoverySection(AppLocalizations l) {
    switch (_status) {
      case _DiscoveryStatus.searching:
        return Row(
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
        );

      case _DiscoveryStatus.notFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  l.noMixerFound,
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SimulatorCard(onTap: _isConnecting ? null : _connectSimulator),
          ],
        );

      case _DiscoveryStatus.found:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.mixersFound, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            ..._consoles.map(
              (c) =>
                  _ConsoleCard(console: c, onTap: () => _connectToConsole(c)),
            ),
            _SimulatorCard(onTap: _isConnecting ? null : _connectSimulator),
          ],
        );
    }
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
