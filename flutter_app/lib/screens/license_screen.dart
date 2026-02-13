import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LicenseScreen extends StatelessWidget {
  const LicenseScreen({super.key});

  static const String _overviewUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio/blob/main/LICENSE.md';
  static const String _sourceLicenseUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio/blob/main/LICENSE';
  static const String _binaryLicenseUrl =
      'https://github.com/BoltzmannEntropy/MimikaStudio/blob/main/BINARY-LICENSE.txt';

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
        title: const Text('License'),
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
                          Icons.description,
                          size: 40,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'MimikaStudio License',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Source code and binary terms',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildSection(
                  context,
                  'Source Code License',
                  Icons.code,
                  [
                    'Business Source License 1.1 (BSL) applies to the source code.',
                    'Production use is permitted under the Additional Use Grant.',
                    'See the LICENSE file for full terms.',
                  ],
                ),
                const SizedBox(height: 20),
                _buildSection(
                  context,
                  'Binary Distribution License',
                  Icons.inventory_2,
                  [
                    'The official DMG/executable binaries are governed by a separate license.',
                    'Commercial use or redistribution of the Binary is not allowed.',
                    'See BINARY-LICENSE.txt for full terms.',
                  ],
                ),
                const SizedBox(height: 24),
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
                              onPressed: () => _launchUrl(_overviewUrl),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('License Overview'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _launchUrl(_sourceLicenseUrl),
                              icon: const Icon(Icons.code),
                              label: const Text('Source License'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _launchUrl(_binaryLicenseUrl),
                              icon: const Icon(Icons.inventory_2),
                              label: const Text('Binary License'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Questions? Contact solomon@qneura.ai',
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
