import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _privacyPolicyUrl = 'https://via-nubium.github.io/stagemon/privacy.html';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
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
              child: Text(
                '${l.version} $_version',
                style: const TextStyle(fontSize: 13, color: Colors.white54),
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
