import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'license_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import '../version.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _websiteUrl =
      'https://boltzmannentropy.github.io/mimikastudio.github.io/';
  static const String _qneuraUrl = 'https://qneura.ai/apps.html';
  static const String _githubUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio';
  static const String _issuesUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio/issues';

  // TTS Engine URLs
  static const Map<String, String> _engineUrls = {
    'Kokoro TTS': 'https://github.com/hexgrad/kokoro',
    'Supertonic': 'https://github.com/supertone-inc/supertonic',
    'Qwen3-TTS': 'https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base',
    'Chatterbox': 'https://huggingface.co/ResembleAI/chatterbox',
    'IndexTTS-2': 'https://huggingface.co/IndexTeam/IndexTTS-v2',
  };

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.graphic_eq,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // App name
              Text(
                'MimikaStudio',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Version
              Text(
                'Version $appVersion',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                versionName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                'Local-first Voice Cloning & Text-to-Speech',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Important Notice
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Important Notice',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'MimikaStudio is for creative, educational, and productivity use. '
                        'Always ensure you have consent for voice cloning and comply with local law and platform policies.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // What This Project Does
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'What This Project Does',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '• Generates high-quality speech from text locally on Apple Silicon\n'
                        '• Supports few-shot voice cloning from short reference audio\n'
                        '• Reads PDF documents aloud and exports audiobook-ready audio\n'
                        '• Keeps inference on-device for privacy-first workflows',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Links section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Links',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _launchUrl(_websiteUrl),
                        icon: const Icon(Icons.language),
                        label: const Text('Website'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _launchUrl(_githubUrl),
                        icon: const Icon(Icons.code),
                        label: const Text('GitHub'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _launchUrl(_issuesUrl),
                        icon: const Icon(Icons.bug_report),
                        label: const Text('Report Issue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Legal section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Legal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Source Code: Business Source License 1.1 (BSL-1.1)\n'
                        'Binary: Mimika Binary Distribution License',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LicenseScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('License'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: const Text('Privacy Policy'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TermsOfServiceScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.gavel_outlined),
                        label: const Text('Terms of Service'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Model credits section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Model Credits & Licenses',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Primary speech engines used by MimikaStudio',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildEngineChip(
                            'Kokoro TTS',
                            Colors.blue,
                            _engineUrls['Kokoro TTS']!,
                          ),
                          _buildEngineChip(
                            'Supertonic',
                            Colors.deepPurple,
                            _engineUrls['Supertonic']!,
                          ),
                          _buildEngineChip(
                            'Qwen3-TTS',
                            Colors.teal,
                            _engineUrls['Qwen3-TTS']!,
                          ),
                          _buildEngineChip(
                            'Chatterbox',
                            Colors.orange,
                            _engineUrls['Chatterbox']!,
                          ),
                          _buildEngineChip(
                            'IndexTTS-2',
                            Colors.purple,
                            _engineUrls['IndexTTS-2']!,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kokoro (Apache-2.0) · Supertonic (OpenRail) · '
                        'Qwen3-TTS (Apache-2.0) · Chatterbox (MIT) · '
                        'IndexTTS-2 (open model license)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Footer
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Source: BSL-1.1 | Binary: Mimika Binary Distribution License',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _launchUrl(_qneuraUrl),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    '2026 Qneura.ai',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEngineChip(String label, Color color, String url) {
    return ActionChip(
      onPressed: () => _launchUrl(url),
      avatar: Icon(
        Icons.open_in_new,
        size: 16,
        color: Colors.white.withValues(alpha: 0.9),
      ),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: color,
      side: BorderSide.none,
      tooltip: 'Open $label website',
    );
  }
}
