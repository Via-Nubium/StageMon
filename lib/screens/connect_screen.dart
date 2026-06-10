import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';
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
      final consoles = await OscService.findAllConsoles()
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
      if (!mounted) return;
      setState(() {
        _consoles = consoles;
        _status = consoles.isNotEmpty ? _DiscoveryStatus.found : _DiscoveryStatus.notFound;
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

  void _connect([String? overrideIp]) async {
    final l = AppLocalizations.of(context)!;
    final ip = (overrideIp ?? _ipController.text).trim();
    if (ip.isEmpty) return;
    if (!_isValidIp(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.invalidIp)),
      );
      return;
    }
    final service = OscService(ip: ip);
    try {
      await service.init();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.socketError(e.toString()))),
      );
      return;
    }
    if (!mounted) return;
    SharedPreferences.getInstance().then((p) => p.setString('last_ip', ip));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MixerScreen(service: service),
      ),
    );
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
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
                      onPressed: isSearching ? null : () => _connect(),
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Text(
              l.noMixerFound,
              style: const TextStyle(color: Colors.orange),
            ),
          ],
        );

      case _DiscoveryStatus.found:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.mixersFound,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            ..._consoles.map(
              (c) => _ConsoleCard(
                console: c,
                onTap: () => _connect(c.ip),
              ),
            ),
          ],
        );
    }
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
        leading: const Icon(Icons.speaker),
        title: Text(
          console.model,
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
