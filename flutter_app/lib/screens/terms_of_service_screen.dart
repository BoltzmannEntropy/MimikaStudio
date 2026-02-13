import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _websiteUrl = 'https://qneura.ai/apps.html';
  static const String _githubUrl = 'https://github.com/BoltzmannEntropy/MimikaStudio';
  static const String _licenseOverviewUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio/blob/main/LICENSE.md';
  static const String _appleEulaUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

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
        title: const Text('Terms of Service'),
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
                          Icons.gavel,
                          size: 40,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Terms of Service',
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

                // Local-first notice
                Card(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified,
                          color: theme.colorScheme.primary,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Local-first AI',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'MimikaStudio runs voice cloning and text-to-speech locally on your device.',
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

                // Section 1: Acceptance of Terms
                _buildSection(
                  context,
                  '1. Acceptance of Terms',
                  Icons.handshake,
                  [
                    'By downloading, installing, or using MimikaStudio (the "Service"), you agree to be bound by these Terms of Service.',
                    'If you do not agree to these terms, do not use the Service.',
                    'Additional guidelines or rules may apply to specific features and are incorporated by reference.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 2: Description of Service
                _buildSection(
                  context,
                  '2. Description of Service',
                  Icons.auto_awesome,
                  [
                    'MimikaStudio is a local-first voice cloning and text-to-speech application.',
                    'The Service allows you to import text and audio samples, generate voices, and export audio files.',
                    'Some features may rely on on-device AI models and optional plugins.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 3: User Conduct
                _buildSection(
                  context,
                  '3. User Conduct',
                  Icons.rule,
                  [
                    'You agree to use the Service only for lawful purposes and in compliance with applicable regulations.',
                    'Do not use the Service to impersonate others without consent or to create deceptive or harmful content.',
                    'You are responsible for ensuring you have rights to any content you import or generate.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 4: Intellectual Property
                _buildSection(
                  context,
                  '4. Intellectual Property',
                  Icons.lightbulb_outline,
                  [
                    'The Service and its original content (excluding user-provided content) are owned by QNeura.ai and its licensors.',
                    'You retain ownership of your content.',
                    'Nothing in these terms grants you any rights to use QNeura.ai trademarks or branding without permission.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 5: AI Features Disclaimer
                _buildSection(
                  context,
                  '5. AI Features Disclaimer',
                  Icons.tips_and_updates,
                  [
                    'Voice generation and text-to-speech features rely on machine learning models.',
                    'Outputs may be inaccurate, imperfect, or unsuitable for critical use cases.',
                    'You should review and verify important information from the original sources.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 6: Disclaimer of Warranties
                _buildSection(
                  context,
                  '6. Disclaimer of Warranties',
                  Icons.warning_amber,
                  [
                    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.',
                    'This includes, but is not limited to, the implied warranties of merchantability, fitness for a particular purpose, and noninfringement.',
                    'The entire risk as to the quality and performance of the program is with you.',
                    'Should the program prove defective, you assume the cost of all necessary servicing, repair, or correction.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 7: Limitation of Liability
                _buildSection(
                  context,
                  '7. Limitation of Liability',
                  Icons.shield,
                  [
                    'In no event shall the authors, copyright holders, or QNeura.ai be liable for any claim, damages, or other liability.',
                    'This applies whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software.',
                    'This includes any use or other dealings in the software.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 8: Changes to Terms
                _buildSection(
                  context,
                  '8. Changes to Terms',
                  Icons.edit_document,
                  [
                    'We may update these Terms of Service from time to time.',
                    'Changes take effect when posted or otherwise communicated to you.',
                    'Your continued use of the Service after changes indicates acceptance.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 9: Contact Us
                _buildSection(
                  context,
                  '9. Contact Us',
                  Icons.mail_outline,
                  [
                    'If you have questions about these Terms, please contact solomon@qneura.ai or visit https://qneura.ai/apps.html.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 10: External Content Sources
                _buildSection(
                  context,
                  '10. External Content Sources',
                  Icons.public,
                  [
                    'The Service may provide access to or include third-party models, datasets, or libraries.',
                    'These materials are provided by their respective owners and are subject to their own licenses.',
                    'You are responsible for ensuring your use complies with applicable laws and third-party terms.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 11: Apple Standard EULA
                _buildSection(
                  context,
                  '11. Apple Standard EULA',
                  Icons.description,
                  [
                    'If you download MimikaStudio via the Apple App Store, the Apple Standard EULA applies.',
                    'Review the standard EULA at https://www.apple.com/legal/internet-services/itunes/dev/stdeula/.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 12: Paid Features
                _buildSection(
                  context,
                  '12. License & Distribution',
                  Icons.description,
                  [
                    'Source code is licensed under Business Source License 1.1 (see LICENSE).',
                    'Official DMG/executable binaries are governed by a separate Binary Distribution License.',
                    'Commercial use or redistribution of the Binary is not allowed.',
                    'See the License page in the app or LICENSE.md for details.',
                  ],
                ),
                const SizedBox(height: 20),

                // Section 13: Paid Features
                _buildSection(
                  context,
                  '13. Paid Features',
                  Icons.shopping_cart,
                  [
                    'If paid features are offered, purchases are processed by the storefront or payment provider.',
                    'Subscription management and cancellations are handled through your account with that provider.',
                  ],
                ),
                const SizedBox(height: 32),

                // Links Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resources',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _launchUrl(_websiteUrl),
                              icon: const Icon(Icons.language),
                              label: const Text('Website'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _launchUrl(_githubUrl),
                              icon: const Icon(Icons.code),
                              label: const Text('Source Code'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _launchUrl(_licenseOverviewUrl),
                              icon: const Icon(Icons.description),
                              label: const Text('License Overview'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _launchUrl(_appleEulaUrl),
                              icon: const Icon(Icons.description),
                              label: const Text('Apple Standard EULA'),
                            ),
                          ],
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
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                    Icons.arrow_right,
                    size: 18,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
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
