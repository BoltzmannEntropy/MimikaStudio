import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _websiteUrl = 'https://qneura.ai/apps.html';

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.privacy_tip,
                          size: 40,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Privacy Policy',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MimikaStudio by QNeura.ai',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last updated: February 2026',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Local-First Notice
                Card(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: theme.colorScheme.primary,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Privacy-First Design',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Your voice data and files stay on your device unless you choose to share them.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Section 1: Data Collection
                _buildSection(
                  context,
                  'Data Collection',
                  Icons.data_usage,
                  [
                    'MimikaStudio does not collect personal information by default.',
                    'We do not track your usage behavior or sell data to third parties.',
                    'No audio recordings, text inputs, or generated outputs are uploaded without your action.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 2: On-Device Processing
                _buildSection(
                  context,
                  'On-Device Processing',
                  Icons.computer,
                  [
                    'Voice cloning and text-to-speech features run locally using on-device AI models.',
                    'Your content is processed on your machine and remains in your control.',
                    'Generated audio is saved only in locations you specify.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 3: File Access
                _buildSection(
                  context,
                  'File Access Permissions',
                  Icons.folder_open,
                  [
                    'We access only the files and folders you explicitly select.',
                    'Read access is used to process audio or text inputs you provide.',
                    'Write access is used to save generated outputs to your chosen folders.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 4: Network Usage
                _buildSection(
                  context,
                  'Network Usage',
                  Icons.wifi_off,
                  [
                    'MimikaStudio can operate offline after initial setup.',
                    'Optional update or license checks may send basic app and device metadata.',
                    'No audio content or text you generate is transmitted during these checks.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 5: Third-Party Services
                _buildSection(
                  context,
                  'Third-Party Services',
                  Icons.extension,
                  [
                    'MimikaStudio relies on open-source models and system-level services.',
                    'These components run locally and do not transmit your data to third parties.',
                    'If third-party services are enabled in future releases, we will update this policy.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 6: Data Security
                _buildSection(
                  context,
                  'Data Security',
                  Icons.lock_outline,
                  [
                    'Your data stays on your device and is protected by your operating system.',
                    'We recommend using device security features such as passwords or biometrics.',
                    'You control deletion and sharing of your files.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 7: Children's Privacy
                _buildSection(
                  context,
                  'Children\'s Privacy',
                  Icons.child_care,
                  [
                    'MimikaStudio does not collect any personal information from anyone, including children.',
                    'As a local-first application, there are no accounts or personal data to protect.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 8: Changes to Policy
                _buildSection(
                  context,
                  'Changes to This Policy',
                  Icons.update,
                  [
                    'We may update this Privacy Policy from time to time.',
                    'Changes will be reflected in the "Last updated" date at the top of this policy.',
                    'Continued use of MimikaStudio after changes constitutes acceptance of the updated policy.',
                  ],
                ),
                const SizedBox(height: 32),

                // Contact Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contact Us',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'If you have any questions about this Privacy Policy, please contact '
                          'solomon@qneura.ai or visit our website:',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _launchUrl(_websiteUrl),
                          icon: const Icon(Icons.language),
                          label: const Text('QNeura.ai'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Footer
                Center(
                  child: Text(
                    '2026 QNeura.ai - All rights reserved',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<String> points,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...points.map((point) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      point,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
