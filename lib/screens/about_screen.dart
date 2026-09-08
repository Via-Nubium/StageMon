import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'diagnostics_screen.dart';

const _privacyPolicyUrl = 'https://via-nubium.github.io/stagemon/privacy.html';

// Volunteer translators, credited under the native name of the language
// they translated (not its English or Spanish name) — see app_eu.arb.
const _translators = <({String language, String name})>[
  (language: 'Euskara', name: 'Iker Viteri Valle'),
];

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  // Standard Android "hidden developer screen" gesture. Diagnostics ships in
  // release because that is where the connection problems it measures are
  // expected to show up, but nobody finds it by accident.
  static const int _tapsToRevealDiagnostics = 7;
  int _versionTaps = 0;
  bool _diagnosticsRevealed = false;

  void _onVersionTap() {
    if (_diagnosticsRevealed) return;
    _versionTaps++;
    if (_versionTaps >= _tapsToRevealDiagnostics) {
      setState(() => _diagnosticsRevealed = true);
    }
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    });
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.about)),
      body: ListView(
        children: [
          const SizedBox(height: 40),
          Center(
            child: Image.asset('assets/icon/icon.png', width: 88, height: 88),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'StageMon',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          if (_version.isNotEmpty)
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onVersionTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  child: Text(
                    '${l.version} $_version ($_buildNumber)',
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            title: Text(l.developer),
            trailing: const Text(
              'Via Nubium',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          if (_translators.isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(title: Text(l.translations)),
            for (final t in _translators)
              ListTile(
                dense: true,
                title: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(t.language, style: const TextStyle(color: Colors.white70)),
                ),
                trailing: Text(t.name, style: const TextStyle(color: Colors.white70)),
              ),
          ],
          const Divider(height: 1),
          ListTile(
            title: Text(l.privacyPolicy),
            trailing: const Icon(Icons.open_in_new, size: 18, color: Colors.white54),
            onTap: _openPrivacyPolicy,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(l.openSourceLicenses),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'StageMon',
              applicationVersion: _version.isNotEmpty ? _version : null,
            ),
          ),
          if (_diagnosticsRevealed) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.network_check, size: 20),
              title: const Text('Diagnostics'),
              trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              l.disclaimer,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
