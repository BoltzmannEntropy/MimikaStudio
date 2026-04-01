import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _licenseController = TextEditingController();
  final FocusNode _licenseFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isActivating = false;
  bool _isProActivated = false;
  String _selectedProvider = 'polar';

  @override
  void initState() {
    super.initState();
    _loadLicenseState();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _licenseFocusNode.dispose();
    super.dispose();
  }

  bool _isValidProvider(String? value) {
    return value == 'polar' || value == 'lemonsqueezy';
  }

  String _providerLabel(String value) {
    return value == 'lemonsqueezy' ? 'LemonSqueezy' : 'Polar';
  }

  Future<void> _loadLicenseState() async {
    setState(() => _isLoading = true);

    try {
      final settings = await _settingsService.getAllSettings();
      final isPro =
          (settings['pro_activated'] ?? 'false').toLowerCase() == 'true';

      if (!settings.containsKey('pro_activated')) {
        await _settingsService.setSetting('pro_activated', 'false');
      }

      final providerRaw = settings['license_provider'];
      final provider = _isValidProvider(providerRaw) ? providerRaw! : 'polar';
      if (!_isValidProvider(providerRaw)) {
        await _settingsService.setSetting('license_provider', provider);
      }

      final licenseKey = settings['license_key'] ?? '';
      if (_licenseController.text.isEmpty && licenseKey.isNotEmpty) {
        _licenseController.text = licenseKey;
      }

      if (!mounted) return;
      setState(() {
        _isProActivated = isPro;
        _selectedProvider = provider;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load license state: $e')),
      );
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter an existing ${_providerLabel(_selectedProvider)} license key.',
          ),
        ),
      );
      return;
    }

    if (key.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License key appears too short.')),
      );
      return;
    }

    setState(() => _isActivating = true);
    try {
      await _settingsService.setSetting('license_key', key);
      await _settingsService.setSetting('pro_activated', 'true');
      await _settingsService.setSetting('license_provider', _selectedProvider);
      await _settingsService.setSetting(
        'license_activated_at',
        DateTime.now().toUtc().toIso8601String(),
      );

      if (!mounted) return;
      setState(() {
        _isProActivated = true;
        _isActivating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Existing ${_providerLabel(_selectedProvider)} license activated.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to activate license: $e')));
    }
  }

  Widget _buildProviderSelector() {
    return Wrap(
      spacing: 10,
      children: [
        ChoiceChip(
          label: const Text('Polar'),
          selected: _selectedProvider == 'polar',
          onSelected: (_) => setState(() => _selectedProvider = 'polar'),
        ),
        ChoiceChip(
          label: const Text('LemonSqueezy'),
          selected: _selectedProvider == 'lemonsqueezy',
          onSelected: (_) => setState(() => _selectedProvider = 'lemonsqueezy'),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    final backgroundColor = _isProActivated
        ? Colors.green.withValues(alpha: 0.10)
        : const Color(0xFFF1E8DD);
    final iconColor = _isProActivated
        ? Colors.green.shade700
        : Colors.orange.shade700;
    final icon = _isProActivated
        ? Icons.verified_rounded
        : Icons.info_outline_rounded;
    final title = _isProActivated
        ? 'Existing License Active'
        : 'No Trial Expiration';
    final subtitle = _isProActivated
        ? 'Your license remains active on this device. The old 7-day expiration is disabled, and online checkout or portal links are turned off in this build.'
        : 'The previous 7-day countdown is disabled. You can keep using MimikaStudio without a deadline. Polar.sh and LemonSqueezy links are disabled in this build.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        spacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 42),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isProActivated)
            FilledButton.tonal(
              onPressed: () {
                _licenseFocusNode.requestFocus();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              child: const Text(
                'Enter Existing License',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivationCard(BuildContext context) {
    final title = _isProActivated
        ? 'Stored license'
        : 'Activate an existing license';
    final subtitle = _isProActivated
        ? 'You can replace the stored key here if you need to reactivate this device. Online checkout and customer portal links remain disabled in this build.'
        : 'If you already received a Polar or LemonSqueezy key earlier, enter it here. New checkout and customer portal links are intentionally disabled in this build.';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Existing key source',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildProviderSelector(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _licenseController,
                    focusNode: _licenseFocusNode,
                    decoration: InputDecoration(
                      hintText:
                          'Enter your existing ${_providerLabel(_selectedProvider)} license key',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isActivating ? null : _activateLicense,
                  child: _isActivating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Activate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadLicenseState,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildStatusBanner(context),
                const SizedBox(height: 18),
                _buildActivationCard(context),
              ],
            ),
          );
  }
}
