import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  static const int _defaultTrialDays = 7;
  static const String _defaultCheckoutUrl = 'https://polar.sh';
  static const String _defaultPortalUrl = 'https://polar.sh';

  final SettingsService _settingsService = SettingsService();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _checkoutUrlController = TextEditingController();
  final TextEditingController _portalUrlController = TextEditingController();
  final FocusNode _licenseFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isActivating = false;
  bool _isProActivated = false;
  int _trialDaysLeft = _defaultTrialDays;
  int _trialDurationDays = _defaultTrialDays;

  @override
  void initState() {
    super.initState();
    _loadLicenseState();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _checkoutUrlController.dispose();
    _portalUrlController.dispose();
    _licenseFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLicenseState() async {
    setState(() => _isLoading = true);

    try {
      final settings = await _settingsService.getAllSettings();

      final isPro =
          (settings['pro_activated'] ?? 'false').toLowerCase() == 'true';
      final trialDays =
          int.tryParse(settings['trial_duration_days'] ?? '') ??
          _defaultTrialDays;

      DateTime trialStart;
      final trialStartRaw = settings['trial_started_at'];
      if (trialStartRaw == null || trialStartRaw.trim().isEmpty) {
        trialStart = DateTime.now().toUtc();
        await _settingsService.setSetting(
          'trial_started_at',
          trialStart.toIso8601String(),
        );
      } else {
        trialStart =
            DateTime.tryParse(trialStartRaw)?.toUtc() ?? DateTime.now().toUtc();
      }

      if (!settings.containsKey('trial_duration_days')) {
        await _settingsService.setSetting(
          'trial_duration_days',
          '$_defaultTrialDays',
        );
      }
      if (!settings.containsKey('pro_activated')) {
        await _settingsService.setSetting('pro_activated', 'false');
      }
      if (!settings.containsKey('license_provider')) {
        await _settingsService.setSetting('license_provider', 'polar');
      }

      final elapsedDays = DateTime.now().toUtc().difference(trialStart).inDays;
      final daysLeft = (trialDays - elapsedDays).clamp(0, trialDays);

      final licenseKey = settings['license_key'] ?? '';
      if (_licenseController.text.isEmpty && licenseKey.isNotEmpty) {
        _licenseController.text = licenseKey;
      }

      final checkoutUrl = settings['polar_checkout_url'] ?? _defaultCheckoutUrl;
      final portalUrl = settings['polar_portal_url'] ?? _defaultPortalUrl;
      _checkoutUrlController.text = checkoutUrl;
      _portalUrlController.text = portalUrl;

      if (!mounted) return;
      setState(() {
        _isProActivated = isPro;
        _trialDurationDays = trialDays;
        _trialDaysLeft = daysLeft;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load Pro license state: $e')),
      );
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid license key.')),
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
      await _settingsService.setSetting('license_provider', 'polar');
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
        const SnackBar(content: Text('License activated (Polar-ready mode).')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to activate license: $e')));
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid URL.')));
      }
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open URL.')));
    }
  }

  Future<void> _buyLicense() async {
    await _openUrl(_checkoutUrlController.text);
  }

  Future<void> _savePolarUrls() async {
    await _settingsService.setSetting(
      'polar_checkout_url',
      _checkoutUrlController.text.trim(),
    );
    await _settingsService.setSetting(
      'polar_portal_url',
      _portalUrlController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Polar URLs saved.')));
  }

  Widget _buildTrialBanner(BuildContext context) {
    if (_isProActivated) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_rounded,
              color: Colors.green.shade700,
              size: 34,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Mimika Pro Active',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text('All Pro features are unlocked on this device.'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final trialEnded = _trialDaysLeft <= 0;
    final title = trialEnded ? 'Trial Ended' : 'Trial Ending Soon';
    final subtitle = trialEnded
        ? 'Your $_trialDurationDays-day trial has ended.'
        : 'You have $_trialDaysLeft day${_trialDaysLeft == 1 ? '' : 's'} left in your trial';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E8DD),
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
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 42,
              ),
              const SizedBox(width: 16),
              Column(
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
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
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
                  'Enter License',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(
                onPressed: _buyLicense,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Buy License',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Upgrade to Mimika Pro',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Polar.sh integration is ready. Configure checkout + portal URLs, then activate Pro with your Polar license key.',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _buyLicense,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Upgrade to Mimika Pro'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openUrl(_portalUrlController.text),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text('Open License Portal'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: const [
                _FeatureChip(
                  icon: Icons.support_agent_rounded,
                  label: 'Priority Support',
                ),
                _FeatureChip(
                  icon: Icons.sync_alt_rounded,
                  label: 'Polar Activation',
                ),
                _FeatureChip(
                  icon: Icons.devices_rounded,
                  label: 'Multiple Devices',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivationCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Already have a license?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _licenseController,
                    focusNode: _licenseFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Enter your Polar license key',
                      border: OutlineInputBorder(),
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
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openUrl(_portalUrlController.text),
                icon: const Icon(Icons.manage_accounts_rounded),
                label: const Text('License Portal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolarConfigCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Polar Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _checkoutUrlController,
              decoration: const InputDecoration(
                labelText: 'Polar Checkout URL',
                hintText: 'https://polar.sh/checkout/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portalUrlController,
              decoration: const InputDecoration(
                labelText: 'Polar Customer Portal URL',
                hintText: 'https://polar.sh/portal/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _savePolarUrls,
              child: const Text('Save Polar URLs'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLicenseState,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildTrialBanner(context),
                  const SizedBox(height: 18),
                  if (!_isProActivated) ...[
                    _buildProCard(context),
                    const SizedBox(height: 18),
                  ],
                  _buildActivationCard(context),
                  const SizedBox(height: 18),
                  _buildPolarConfigCard(),
                ],
              ),
            ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
